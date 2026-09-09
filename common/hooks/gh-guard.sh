#!/usr/bin/env bash

set -uf

# Commands the agent may attempt. Which of them still need approval is decided by
# permissions.ask in config/claude/managed-settings.json.
ALLOWED="
api
auth status
browse
cache list
config get
config list
help
issue close
issue comment
issue create
issue edit
issue list
issue reopen
issue status
issue view
label create
label edit
label list
pr checkout
pr checks
pr close
pr comment
pr create
pr diff
pr edit
pr list
pr ready
pr reopen
pr review
pr status
pr view
release create
release download
release edit
release list
release upload
release view
repo clone
repo create
repo fork
repo list
repo view
run cancel
run download
run list
run rerun
run view
run watch
search code
search commits
search issues
search prs
search repos
status
version
workflow list
workflow run
workflow view
"

deny() {
    jq -n --arg m "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $m}}'
    exit 0
}

in_list() {
    [ -n "$1" ] || return 1
    printf '%s' "$ALLOWED" | grep -qxF -- "$1"
}

check_api() {
    local method="GET" mutating=0
    while [ $# -gt 0 ]; do
        case "$1" in
            -X|--method) method="${2:-}" ;;
            -X=*|--method=*) method="${1#*=}" ;;
            -f|-F|--field|--raw-field|--input|--field=*|--raw-field=*|--input=*) mutating=1 ;;
        esac
        shift
    done
    case "$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')" in
        GET|HEAD) ;;
        *) mutating=1 ;;
    esac
    [ "$mutating" -eq 0 ] && return 0
    deny "Blocked: gh api write requests are not allowed for the agent. Use a typed gh command, or run it yourself."
}

check_gh() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -R|--repo|--hostname) if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
            --repo=*|--hostname=*) shift ;;
            *) break ;;
        esac
    done

    local verbs=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -*) break ;;
            *) verbs+=("$1"); shift ;;
        esac
    done

    local first="${verbs[0]:-}" path=""
    [ -n "$first" ] || return 0
    [ "${#verbs[@]}" -ge 2 ] && path="$first ${verbs[1]}"

    [ "$first" = "api" ] && check_api "$@"

    in_list "$path" && return 0
    in_list "$first" && return 0

    deny "Blocked: 'gh ${path:-$first}' is not on the agent allowlist. Add it to common/hooks/gh-guard.sh if it should be, or run it yourself."
}

check_git() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|-C|--git-dir|--work-tree|--namespace|--exec-path) if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    [ "${1:-}" = "push" ] && deny "Blocked: the agent cannot push. Push yourself, or open a PR."
    return 0
}

payload="$(cat)"

case "$payload" in
    *gh*|*git*) ;;
    *) exit 0 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: gh-guard.sh cannot inspect this command because jq is missing."}}'
    exit 0
fi

command="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)"
[ -n "$command" ] || exit 0

case "$command" in
    *gh*|*git*) ;;
    *) exit 0 ;;
esac

segments="$(printf '%s' "$command" | sed -E 's/(&&|\|\||\$\(|[;|&()`])/\n/g')"

while IFS= read -r segment; do
    set -- $segment
    while [ $# -gt 0 ]; do
        case "$1" in
            *=*|sudo|env|timeout|nice|nohup|stdbuf|time|[0-9]*) shift ;;
            *) break ;;
        esac
    done
    [ $# -gt 0 ] || continue
    prog="${1##*/}"
    shift
    case "$prog" in
        gh) check_gh "$@" ;;
        git) check_git "$@" ;;
    esac
done <<EOF
$segments
EOF

exit 0
