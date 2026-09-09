#!/usr/bin/env bash

set -uf

FORMAT="${1:-claude}"

READ_ONLY="
api
auth status
browse
cache list
config get
config list
help
issue list
issue status
issue view
label list
pr checkout
pr checks
pr diff
pr list
pr status
pr view
release download
release list
release view
repo clone
repo list
repo view
run download
run list
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
workflow view
"

# Keep in sync with permissions.ask in config/claude/managed-settings.json.
NEEDS_APPROVAL="
issue close
issue comment
issue create
issue edit
issue reopen
label create
label edit
pr close
pr comment
pr create
pr edit
pr ready
pr reopen
pr review
release create
release edit
release upload
repo create
repo fork
run cancel
run rerun
workflow run
"

deny() {
    case "$FORMAT" in
        cursor) jq -n --arg m "$1" '{permission: "deny", user_message: $m, agent_message: $m}' ;;
        *) jq -n --arg m "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $m}}' ;;
    esac
    exit 0
}

in_list() {
    [ -n "$1" ] || return 1
    printf '%s' "$2" | grep -qxF -- "$1"
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

    in_list "$path" "$READ_ONLY" && return 0
    in_list "$first" "$READ_ONLY" && return 0

    if in_list "$path" "$NEEDS_APPROVAL" || in_list "$first" "$NEEDS_APPROVAL"; then
        [ "$FORMAT" = "cursor" ] && deny "Blocked: 'gh ${path:-$first}' writes to GitHub and needs a human. Run it yourself."
        return 0
    fi

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
command="$(jq -r '.tool_input.command // .command // empty' <<<"$payload" 2>/dev/null)"
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
