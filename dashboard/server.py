#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
import threading
import time
import traceback
from collections import deque
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

REGISTRY_FILE = re.compile(r'\d+\.json')
SESSION_ID = re.compile(r'[0-9a-fA-F-]{8,64}')
SINCE = re.compile(r'(\d+)([mhd])')
SINCE_UNITS = {'m': 60_000, 'h': 3_600_000, 'd': 86_400_000}
DEFAULT_SINCE_MS = 24 * SINCE_UNITS['h']
STATUS_RANK = {'waiting': 0, 'busy': 1, 'idle': 2, 'shell': 2, 'ended': 3}
ENDED_LIMIT = 20
SNAPSHOT_TTL_SECONDS = 2.0
NEGATIVE_LOOKUP_TTL_SECONDS = 10.0
WORKSPACE_PREFIX = '/workspace/'
# Input, output and cache-read price per million tokens; cache writes cost 1.25x input (5 min TTL) and 2x (1 h).
MODEL_PRICES = {
    'claude-fable-5-1': (10.0, 50.0, 0.25),
    'claude-fable-5': (10.0, 50.0, 1.0),
    'claude-opus-5': (5.0, 25.0, 0.5),
    'claude-opus-4': (5.0, 25.0, 0.5),
    'claude-sonnet-5': (2.0, 10.0, 0.2),
    'claude-sonnet-4': (3.0, 15.0, 0.3),
    'claude-haiku-4-5': (1.0, 5.0, 0.1)
}
STATIC_FILES = {
    '/': ('index.html', 'text/html; charset=utf-8'),
    '/sw.js': ('sw.js', 'text/javascript'),
    '/manifest.webmanifest': ('manifest.webmanifest', 'application/manifest+json'),
    '/icon.svg': ('icon.svg', 'image/svg+xml'),
    '/icon-512.png': ('icon-512.png', 'image/png')
}

last_good_registry = {}


def load_registry(path):
    # Claude rewrites the registry file in place, so a read can catch a torn write.
    try:
        with open(path, encoding='utf-8') as fh:
            record = json.load(fh)
    except (OSError, ValueError):
        return last_good_registry.get(path)
    if not isinstance(record, dict):
        return last_good_registry.get(path)
    last_good_registry[path] = record
    return record


def read_run_env(path):
    env = {}
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                key, separator, value = line.rstrip('\n').partition('=')
                if separator:
                    env[key] = value
    except OSError:
        pass
    return env


def read_runs(claude_dir):
    runs = []
    try:
        entries = sorted(os.scandir(os.path.join(claude_dir, 'ai-runs')), key=lambda entry: entry.name)
    except OSError:
        return runs
    for entry in entries:
        if not entry.is_dir():
            continue
        env = read_run_env(os.path.join(entry.path, 'run.env'))
        started_at = env.get('startedAt')
        run = {
            'id': entry.name,
            'worktree': env.get('worktree'),
            'tool': env.get('tool'),
            'model': env.get('model'),
            'resume': env.get('resume'),
            'startedAt': int(started_at) * 1000 if started_at and started_at.isdigit() else None
        }
        registries = []
        sessions_dir = os.path.join(entry.path, 'sessions')
        try:
            names = os.listdir(sessions_dir)
        except OSError:
            names = []
        for name in names:
            if not REGISTRY_FILE.fullmatch(name):
                continue
            record = load_registry(os.path.join(sessions_dir, name))
            if record and record.get('sessionId'):
                registries.append(record)
        runs.append({'run': run, 'registries': registries})
    return runs


def parse_timestamp(value):
    if not value:
        return None
    try:
        return int(datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp() * 1000)
    except ValueError:
        return None


def content_blocks(message):
    content = (message or {}).get('content')
    if isinstance(content, list):
        return [block for block in content if isinstance(block, dict)]
    return []


def tool_summary(name, tool_input):
    tool_input = tool_input if isinstance(tool_input, dict) else {}
    if name == 'Bash':
        text = tool_input.get('description') or tool_input.get('command') or ''
    elif name in ('Edit', 'Read', 'Write', 'NotebookEdit'):
        text = tool_input.get('file_path') or ''
        if text.startswith(WORKSPACE_PREFIX):
            text = text[len(WORKSPACE_PREFIX):]
    elif name == 'Agent':
        text = tool_input.get('description') or tool_input.get('subagent_type') or ''
    elif name == 'AskUserQuestion':
        questions = [question.get('question') for question in tool_input.get('questions') or []
                     if isinstance(question, dict) and question.get('question')]
        text = questions[0] if questions else ''
        if len(questions) > 1:
            text += ' (+%d more)' % (len(questions) - 1)
    elif name == 'ExitPlanMode':
        text = 'Plan awaiting approval'
    elif name == 'WebFetch':
        text = tool_input.get('url') or ''
    elif name == 'WebSearch':
        text = tool_input.get('query') or ''
    elif name == 'Skill':
        text = tool_input.get('skill') or ''
    elif name and name.startswith('mcp__'):
        parts = name.split('__', 2)
        return '%s: %s' % (parts[1], parts[2]) if len(parts) == 3 else name
    else:
        text = tool_input.get('pattern') or tool_input.get('description') or ''
    text = ' '.join(str(text).split())
    return text[:120] if text else (name or '')


def usage_tokens(usage):
    creation = usage.get('cache_creation') or {}
    total = (usage.get('input_tokens') or 0) + (usage.get('output_tokens') or 0)
    total += usage.get('cache_read_input_tokens') or 0
    if creation:
        total += (creation.get('ephemeral_5m_input_tokens') or 0) + (creation.get('ephemeral_1h_input_tokens') or 0)
    else:
        total += usage.get('cache_creation_input_tokens') or 0
    return total


def usage_cost(usage, model):
    prefix = max((key for key in MODEL_PRICES if model and model.startswith(key)), key=len, default=None)
    if not prefix:
        return 0.0
    input_price, output_price, read_price = MODEL_PRICES[prefix]
    creation = usage.get('cache_creation') or {}
    total = (usage.get('input_tokens') or 0) * input_price
    total += (usage.get('output_tokens') or 0) * output_price
    total += (usage.get('cache_read_input_tokens') or 0) * read_price
    if creation:
        total += (creation.get('ephemeral_5m_input_tokens') or 0) * input_price * 1.25
        total += (creation.get('ephemeral_1h_input_tokens') or 0) * input_price * 2.0
    else:
        total += (usage.get('cache_creation_input_tokens') or 0) * input_price * 1.25
    return total / 1_000_000


def summarize_transcript(path):
    title = last_prompt = last_assistant_text = branch = model = permission_mode = cost = None
    effort = None
    turns = 0
    last_turn_ended_at = last_turn_duration_ms = None
    pending_tools = {}
    recent_tools = deque(maxlen=3)
    estimated_cost = 0.0
    estimated_tokens = 0
    priced_messages = set()
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if not isinstance(record, dict) or record.get('isSidechain'):
                continue
            kind = record.get('type')
            if kind == 'assistant':
                message = record.get('message') or {}
                branch = record.get('gitBranch') or branch
                model = message.get('model') or model
                effort = record.get('effort') or effort
                at = parse_timestamp(record.get('timestamp'))
                usage = message.get('usage')
                message_id = message.get('id') or record.get('requestId')
                if usage and message_id not in priced_messages:
                    priced_messages.add(message_id)
                    estimated_cost += usage_cost(usage, message.get('model'))
                    estimated_tokens += usage_tokens(usage)
                for block in content_blocks(message):
                    if block.get('type') == 'tool_use':
                        tool = {'name': block.get('name'), 'summary': tool_summary(block.get('name'), block.get('input')), 'at': at}
                        pending_tools[block.get('id')] = tool
                        recent_tools.append(tool)
                    elif block.get('type') == 'text' and str(block.get('text', '')).strip():
                        last_assistant_text = str(block['text']).strip()[:200]
            elif kind == 'user':
                branch = record.get('gitBranch') or branch
                for block in content_blocks(record.get('message')):
                    if block.get('type') == 'tool_result':
                        pending_tools.pop(block.get('tool_use_id'), None)
            elif kind == 'system' and record.get('subtype') == 'turn_duration':
                turns += 1
                last_turn_ended_at = parse_timestamp(record.get('timestamp'))
                last_turn_duration_ms = record.get('durationMs')
                pending_tools.clear()
            elif kind == 'ai-title':
                title = record.get('aiTitle') or title
            elif kind == 'last-prompt':
                last_prompt = record.get('lastPrompt') or last_prompt
            elif kind == 'permission-mode':
                permission_mode = record.get('permissionMode') or permission_mode
            elif kind == 'cost-state':
                cost = {
                    'usd': record.get('totalCostUSD'),
                    'linesAdded': record.get('totalLinesAdded'),
                    'linesRemoved': record.get('totalLinesRemoved'),
                    'durationMs': record.get('totalDuration'),
                    'startTime': record.get('startTime')
                }
    return {
        'title': title,
        'lastPrompt': last_prompt,
        'lastAssistantText': last_assistant_text,
        'branch': branch,
        'model': model,
        'permissionMode': permission_mode,
        'effort': effort,
        'turns': turns,
        'lastTurnEndedAt': last_turn_ended_at,
        'lastTurnDurationMs': last_turn_duration_ms,
        'pendingTools': list(pending_tools.values()),
        'recentTools': list(recent_tools),
        'cost': cost,
        'estimatedCostUSD': round(estimated_cost, 4),
        'estimatedTokens': estimated_tokens
    }


class TranscriptIndex:
    def __init__(self, claude_dir):
        self.projects_dir = os.path.join(claude_dir, 'projects')
        self.summaries = {}
        self.missing_since = {}

    def find(self, session_id):
        if not SESSION_ID.fullmatch(session_id):
            return None
        checked_at = self.missing_since.get(session_id)
        if checked_at and time.time() - checked_at < NEGATIVE_LOOKUP_TTL_SECONDS:
            return None
        matches = glob.glob(os.path.join(self.projects_dir, '*', session_id + '.jsonl'))
        if not matches:
            self.missing_since[session_id] = time.time()
            return None
        self.missing_since.pop(session_id, None)
        return matches[0]

    def all_paths(self):
        return glob.glob(os.path.join(self.projects_dir, '*', '*.jsonl'))

    def summary(self, path):
        try:
            stat = os.stat(path)
        except OSError:
            return None
        key = (stat.st_size, stat.st_mtime_ns)
        cached = self.summaries.get(path)
        if cached and cached[0] == key:
            return cached[1]
        summary = summarize_transcript(path)
        summary['lastActivityAt'] = int(stat.st_mtime * 1000)
        self.summaries[path] = (key, summary)
        return summary


class Snapshot:
    def __init__(self, claude_dir):
        self.claude_dir = claude_dir
        self.index = TranscriptIndex(claude_dir)
        self.lock = threading.Lock()
        self.cache = {}

    def get(self, since_ms):
        with self.lock:
            cached = self.cache.get(since_ms)
            if cached and time.time() - cached[0] < SNAPSHOT_TTL_SECONDS:
                return cached[1]
            data = self.build(since_ms)
            self.cache = {since_ms: (time.time(), data)}
            return data

    def build(self, since_ms):
        now = int(time.time() * 1000)
        sessions = []
        live_ids = set()
        runs_without_session = 0
        for item in read_runs(self.claude_dir):
            if not item['registries']:
                runs_without_session += 1
            for registry in item['registries']:
                live_ids.add(registry['sessionId'])
                path = self.index.find(registry['sessionId'])
                transcript = self.index.summary(path) if path else None
                sessions.append(self.live_session(registry, item['run'], transcript))
        for path in self.index.all_paths():
            session_id = os.path.splitext(os.path.basename(path))[0]
            if session_id in live_ids:
                continue
            try:
                last_activity_at = int(os.stat(path).st_mtime * 1000)
            except OSError:
                continue
            if now - last_activity_at > since_ms:
                continue
            transcript = self.index.summary(path)
            if transcript:
                sessions.append(self.ended_session(session_id, transcript))
        sessions.sort(key=lambda session: (STATUS_RANK.get(session['status'], 9), -(session['lastActivityAt'] or 0)))
        live = [session for session in sessions if session['status'] != 'ended']
        ended = [session for session in sessions if session['status'] == 'ended'][:ENDED_LIMIT]
        return {'now': now, 'sinceMs': since_ms, 'runsWithoutSession': runs_without_session, 'sessions': live + ended}

    @staticmethod
    def live_session(registry, run, transcript):
        timestamps = [value for value in ((transcript or {}).get('lastActivityAt'), registry.get('updatedAt')) if value]
        return {
            'sessionId': registry['sessionId'],
            'live': True,
            'title': (transcript or {}).get('title') or registry.get('name') or registry['sessionId'][:8],
            'status': registry.get('status') or 'idle',
            'waitingFor': registry.get('waitingFor'),
            'needs': registry.get('needs'),
            'statusUpdatedAt': registry.get('statusUpdatedAt') or registry.get('updatedAt'),
            'startedAt': registry.get('startedAt') or run.get('startedAt'),
            'name': registry.get('name'),
            'lastActivityAt': max(timestamps) if timestamps else None,
            'run': run,
            'transcript': transcript
        }

    @staticmethod
    def ended_session(session_id, transcript):
        return {
            'sessionId': session_id,
            'live': False,
            'title': transcript.get('title') or session_id[:8],
            'status': 'ended',
            'waitingFor': None,
            'needs': None,
            'statusUpdatedAt': transcript.get('lastActivityAt'),
            'startedAt': (transcript.get('cost') or {}).get('startTime'),
            'name': None,
            'lastActivityAt': transcript.get('lastActivityAt'),
            'run': None,
            'transcript': transcript
        }


def parse_since(value):
    match = SINCE.fullmatch(value or '')
    if not match:
        return DEFAULT_SINCE_MS
    return int(match.group(1)) * SINCE_UNITS[match.group(2)]


class Handler(BaseHTTPRequestHandler):
    snapshot = None
    static_dir = os.path.dirname(os.path.abspath(__file__))

    def do_GET(self):
        url = urlparse(self.path)
        if url.path in STATIC_FILES:
            name, content_type = STATIC_FILES[url.path]
            self.serve_file(os.path.join(self.static_dir, name), content_type)
        elif url.path == '/api/sessions':
            since_ms = parse_since(parse_qs(url.query).get('since', [''])[0])
            try:
                body = json.dumps(self.snapshot.get(since_ms)).encode('utf-8')
            except Exception:
                traceback.print_exc()
                self.respond(500, 'text/plain; charset=utf-8', b'Snapshot failed')
                return
            self.respond(200, 'application/json; charset=utf-8', body)
        else:
            self.respond(404, 'text/plain; charset=utf-8', b'Not found')

    def serve_file(self, path, content_type):
        try:
            with open(path, 'rb') as fh:
                body = fh.read()
        except OSError:
            self.respond(404, 'text/plain; charset=utf-8', b'Not found')
            return
        self.respond(200, content_type, body)

    def respond(self, status, content_type, body):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def log_request(self, code='-', size='-'):
        if code != 200:
            super().log_request(code, size)


def main():
    parser = argparse.ArgumentParser(description='Claude Code sessions dashboard')
    parser.add_argument('--claude-dir', default=os.path.expanduser('~/.claude'))
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()

    claude_dir = os.path.abspath(os.path.expanduser(args.claude_dir))
    Handler.snapshot = Snapshot(claude_dir)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.daemon_threads = True
    print('Serving Claude sessions dashboard [claudeDir=%s, url=http://%s:%d]' % (claude_dir, args.host, args.port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
