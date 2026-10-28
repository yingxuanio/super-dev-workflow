#!/bin/bash
# worktree-guard.sh — worktree commit/push guards.
#
# Sourced by .githooks/pre-commit and .githooks/pre-push. Every guard:
#   - degrades to a no-op when its inputs are missing (no jq, no registry,
#     unregistered checkout) so old branches and CI never break on it;
#   - FAILS LOUD with recovery steps when it detects state another flow moved
#     under this checkout — committing through that state is how one task's
#     files end up in another task's PR.
#
# Overrides:
#   WT_GUARD=0                              disable all guards
#   WTGUARD_REGISTRY=<path>                 registry location override
#   WT_GUARD_ALLOW_BRANCH_SWITCH=1          commit on a different branch knowingly
#   WT_GUARD_ALLOW_SHARED_SENSITIVE=1       commit shared/release files knowingly

# Registry path resolution. The hooks source this guard WITHOUT the manager,
# so REGISTRY_FILE is usually unset here: derive it from the repo exactly the
# way worktree-manager.sh does (origin basename → ~/.wt-registry/<slug>/).
# WTGUARD_REGISTRY still wins when a caller pins an explicit path.
wtguard_registry_path() {
    local top url slug
    top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    url=$(git -C "$top" config --get remote.origin.url 2>/dev/null || true)
    if [ -n "$url" ]; then
        slug="$(basename "$url")"
        slug="${slug%.git}"
    else
        slug="$(basename "$top")"
    fi
    printf '%s' "$HOME/.wt-registry/$slug/registry.json"
}

WTGUARD_REGISTRY="${WTGUARD_REGISTRY:-$(wtguard_registry_path || echo "$HOME/.wt-registry/registry.json")}"
# Release/shared surfaces: changes here affect every worktree, so a second
# worktree touching the same file at the same time is cross-task pollution
# until proven otherwise. Projects override via worktree.config.sh
# (WT_SENSITIVE_RE), which exports WTGUARD_SENSITIVE_RE.
WTGUARD_SENSITIVE_RE="${WTGUARD_SENSITIVE_RE:-${WT_SENSITIVE_RE:-'^(\.github/workflows/)'}}"

wtguard_top() { git rev-parse --show-toplevel 2>/dev/null; }

wtguard_current_branch() { git branch --show-current 2>/dev/null; }

# Echo the registered branch for this checkout, or nothing when unregistered
# / registry unreadable. Never fails — absence of data must not block commits.
wtguard_registered_branch() {
    [ -f "$WTGUARD_REGISTRY" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local top branch
    top=$(wtguard_top) || return 1
    branch=$(jq -r --arg path "$top" '.worktrees[$path].branch // empty' \
        "$WTGUARD_REGISTRY" 2>/dev/null) || return 1
    [ -n "$branch" ] || return 1
    printf '%s\n' "$branch"
}

wtguard_branch_matches_registry() {
    local registered current
    registered=$(wtguard_registered_branch) || return 0
    [ "${WT_GUARD_ALLOW_BRANCH_SWITCH:-}" = "1" ] && return 0
    current=$(wtguard_current_branch)
    [ "$current" = "$registered" ] && return 0
    cat >&2 <<EOF
[wt-guard] STOP: branch mismatch.
This checkout is registered for branch '$registered' but is on '$current'.
Another session may have switched branches here, or this commit runs in the
wrong checkout — committing now is how one task's files land in another's PR.

Recovery:
  1. Inspect what moved:   git log --oneline --decorate -5 && git status --short
  2. This is your worktree: git checkout '$registered'
  3. You meant another task: cd to that task's worktree (worktree-manager.sh list)
  4. Deliberate branch switch: re-run with WT_GUARD_ALLOW_BRANCH_SWITCH=1
EOF
    return 1
}

# Fail when a staged shared/release file ALSO has uncommitted changes in
# another registered, on-disk worktree — the fingerprint of one session
# sweeping another task's concurrent shared-file work into its commit.
wtguard_no_foreign_sensitive_files() {
    [ "${WT_GUARD_ALLOW_SHARED_SENSITIVE:-}" = "1" ] && return 0
    [ -f "$WTGUARD_REGISTRY" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local staged sensitive=()
    while IFS= read -r staged; do
        [ -n "$staged" ] || continue
        # bash 3.2: regex match with a variable pattern needs [[ =~ ]] and an
        # unquoted variable; store in a var so metacharacters are safe.
        local re="$WTGUARD_SENSITIVE_RE"
        [[ "$staged" =~ $re ]] && sensitive+=("$staged")
    done < <(git diff --cached --name-only --diff-filter=ACMR)
    ((${#sensitive[@]} > 0)) || return 0

    local top other conflicts=""
    top=$(wtguard_top) || return 0
    while IFS= read -r other; do
        [ -n "$other" ] && [ "$other" != "$top" ] && [ -d "$other" ] || continue
        # One git call per sibling worktree, pathspec-filtered to the staged
        # sensitive files.
        local hits
        hits=$(git -C "$other" status --porcelain -- "${sensitive[@]}" 2>/dev/null) || continue
        if [ -n "$hits" ]; then
            conflicts+="${other}"$'\n'"$hits"$'\n'
        fi
    done < <(jq -r '.worktrees | keys[]' "$WTGUARD_REGISTRY" 2>/dev/null)

    [ -z "$conflicts" ] && return 0
    cat >&2 <<EOF
[wt-guard] STOP: staged shared file(s) also have uncommitted changes in another worktree:
$conflicts
Two tasks editing the same shared surface concurrently is the observed
cross-task pollution pattern. Coordinate first, or stage only your task's files.

Recovery:
  1. Unstage the foreign file(s): git restore --staged <path>
  2. Check the other worktree really owns them: worktree-manager.sh list
  3. Both changes are genuinely yours and coordinated:
     re-run with WT_GUARD_ALLOW_SHARED_SENSITIVE=1
EOF
    return 1
}

# Append a one-line record to THIS worktree's private git dir (each linked
# worktree has its own), then trim to the last 200 lines. Post-hoc diagnosis
# of "which hook blocked what, when" without touching shared state.
wtguard_journal() {
    local event="$1" verdict="$2"
    local gitdir
    gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0
    local entry
    entry="$(date -u +%Y-%m-%dT%H:%M:%SZ)"$'\t'"$event"$'\t'"$(wtguard_current_branch)"$'\t'"$(git rev-parse HEAD 2>/dev/null)"$'\t'"$verdict"
    printf '%s\n' "$entry" >> "$gitdir/wt-guard-journal.log" || return 0
    local trimmed
    trimmed=$(tail -n 200 "$gitdir/wt-guard-journal.log" 2>/dev/null) || return 0
    printf '%s\n' "$trimmed" > "$gitdir/wt-guard-journal.log" 2>/dev/null || true
}
