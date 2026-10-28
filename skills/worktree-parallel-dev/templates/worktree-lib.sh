#!/bin/bash
# worktree-lib.sh — shared primitives for the worktree parallel-dev system.
#
# Sourced by worktree-manager.sh and (partially) worktree-guard.sh.
# Project-agnostic: the registry location and per-worktree resources are
# derived from the git remote / repo name and scripts/worktree.config.sh.
#
# macOS bash 3.2 compatible: no assoc arrays, no ${var,,}, no `flock`
# (the registry lock is mkdir-based, see with_registry_lock below).

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GIT_RETRY_ATTEMPTS="${GIT_RETRY_ATTEMPTS:-5}"
GIT_RETRY_LOCK_RE='(index\.lock|refs/heads/.+\.lock|Unable to create .*\.lock)'

# Retry a git command while its failure looks like lock contention (parallel
# worktrees share one object database, so ref/index locks are contested).
git_retry() {
    local attempt=1 delay_ms=200 err rc
    while :; do
        err=$("$@" 2>&1 >/dev/null)
        rc=$?
        if [ "$rc" -eq 0 ]; then
            return 0
        fi
        if [[ "$err" =~ $GIT_RETRY_LOCK_RE ]] && [ "$attempt" -lt "$GIT_RETRY_ATTEMPTS" ]; then
            echo -e "${YELLOW}⚠${NC} git lock contention on '$*', retry $attempt/$((GIT_RETRY_ATTEMPTS - 1))" >&2
            sleep "$(awk -v ms="$delay_ms" 'BEGIN { printf "%.1f", ms / 1000 }')"
            attempt=$((attempt + 1))
            delay_ms=$((delay_ms * 2))
            continue
        fi
        [ -n "$err" ] && echo "$err" >&2
        return "$rc"
    done
}

# ---------------------------------------------------------------------------
# Registry lock + atomic publish
#
# mkdir is the atomic lock primitive; a lock whose holder died is taken over
# once its mtime exceeds REGISTRY_LOCK_STALE_SEC AND its recorded pid is no
# longer alive. Readers do not take the lock — writers publish via atomic
# rename, so a reader either sees the old or the new file, never a torn one.
# ---------------------------------------------------------------------------
REGISTRY_LOCK_STALE_SEC="${REGISTRY_LOCK_STALE_SEC:-120}"
REGISTRY_LOCK_TIMEOUT_SEC="${REGISTRY_LOCK_TIMEOUT_SEC:-60}"

# File mtime in epoch seconds, portable across BSD (macOS) and GNU stat.
_stat_mtime() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

with_registry_lock() {
    mkdir -p "$REGISTRY_DIR"
    local lock_dir="$REGISTRY_DIR/registry.lock"
    local iter=0 max_iter=$((REGISTRY_LOCK_TIMEOUT_SEC * 5)) # 0.2s per poll

    until mkdir "$lock_dir" 2>/dev/null; do
        # A failed mkdir followed by a failed stat means the holder RELEASED
        # the lock between the two calls — not a stale lock. Loop; misreading
        # this window as "age since epoch" triggers spurious takeovers under
        # exactly the concurrency this lock exists for.
        local mtime
        mtime=$(_stat_mtime "$lock_dir")
        if [ "$mtime" -eq 0 ]; then
            iter=$((iter + 1))
            if [ "$iter" -ge "$max_iter" ]; then
                echo -e "${RED}Error: timed out after ${REGISTRY_LOCK_TIMEOUT_SEC}s waiting for the registry lock (${lock_dir}). Another session may be mid-init; retry shortly.${NC}" >&2
                return 1
            fi
            sleep 0.05
            continue
        fi
        local lock_age=$(( $(date +%s) - mtime ))
        local holder_pid=""
        [ -f "$lock_dir/pid" ] && holder_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
        if [ "$lock_age" -ge "$REGISTRY_LOCK_STALE_SEC" ]; then
            if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
                echo -e "${RED}Error: registry lock held ${lock_age}s by live pid ${holder_pid}; not taking over. Retry once that session finishes.${NC}" >&2
                return 1
            fi
            echo -e "${YELLOW}⚠${NC} Taking over stale registry lock (age ${lock_age}s, holder ${holder_pid:-unknown} dead)" >&2
            rm -rf "$lock_dir"
            continue
        fi
        iter=$((iter + 1))
        if [ "$iter" -ge "$max_iter" ]; then
            echo -e "${RED}Error: timed out after ${REGISTRY_LOCK_TIMEOUT_SEC}s waiting for the registry lock (${lock_dir}).${NC}" >&2
            return 1
        fi
        sleep 0.2
    done
    # BASHPID is the real holder even inside `... &` forks ($$ stays the
    # parent's); fall back to $$ on bash 3.2 where BASHPID is unset.
    printf '%s\n' "${BASHPID:-$$}" > "$lock_dir/pid"

    local rc=0
    "$@" || rc=$?
    rm -rf "$lock_dir"
    return "$rc"
}

# Publish a jq-produced registry document atomically (write temp + rename in
# the same directory) so concurrent readers never observe a partial file.
_write_registry_atomic() {
    local content="$1" tmp
    tmp=$(mktemp "$REGISTRY_DIR/registry.json.XXXXXX")
    printf '%s\n' "$content" > "$tmp" && mv "$tmp" "$REGISTRY_FILE"
}

# Initialize registry file if it doesn't exist. Creation is guarded by
# noclobber so two first-time inits cannot truncate each other's template.
init_registry() {
    if [ ! -f "$REGISTRY_FILE" ]; then
        mkdir -p "$REGISTRY_DIR"
        (
            set -o noclobber
            printf '%s\n' '{"version":1,"project":"'"$PROJECT_SLUG"'","worktrees":{},"allocation":{}}' \
                > "$REGISTRY_FILE" 2>/dev/null
        ) || true
    fi
    jq -e '.worktrees' "$REGISTRY_FILE" >/dev/null 2>&1 || {
        echo -e "${RED}Error: registry at $REGISTRY_FILE is corrupt; restore or delete it, then re-init.${NC}" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Git context helpers
# ---------------------------------------------------------------------------
is_git_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

get_current_worktree() { git rev-parse --show-toplevel 2>/dev/null; }

get_current_branch() { git branch --show-current 2>/dev/null; }

get_git_dir_path() { git rev-parse --absolute-git-dir 2>/dev/null; }

get_git_common_dir_path() { git rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }

get_main_worktree_path() { git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}'; }

# A linked worktree whose git dir is shared with the common dir is primary.
is_primary_worktree() {
    local git_dir common_dir
    git_dir=$(get_git_dir_path) || return 1
    common_dir=$(get_git_common_dir_path) || return 1
    [ "$git_dir" = "$common_dir" ]
}

# Registration gate: the primary checkout must only ever be registered for
# the main branch. It is shared release ground — version bumps and merges
# land here, and every worktree's guard reads registry entries. Registering
# the primary for a feature branch enshrines that branch as the owner and
# every later main commit fails the branch-mismatch guard. Feature work
# belongs in a linked worktree. Returns 0 when registration is refused.
primary_registration_refused() {
    local branch="$1"
    [ "$branch" = "$WT_MAIN_BRANCH" ] && return 1
    is_primary_worktree
}

is_worktree_registered() {
    local path="$1"
    [ -f "$REGISTRY_FILE" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e --arg p "$path" '.worktrees[$p] != null' "$REGISTRY_FILE" >/dev/null 2>&1
}

# Compact JSON config for one worktree ({} when unregistered/unreadable —
# absence of data must not crash callers; guards handle emptiness).
get_worktree_config() {
    local path="$1"
    [ -f "$REGISTRY_FILE" ] || { echo '{}'; return; }
    jq -c --arg p "$path" '.worktrees[$p] // {}' "$REGISTRY_FILE" 2>/dev/null || echo '{}'
}

# ---------------------------------------------------------------------------
# Registry mutations (all take the lock; all publish atomically)
# ---------------------------------------------------------------------------
_update_registry_locked() {
    local path="$1" config="$2"
    local updated
    updated=$(jq --arg p "$path" --argjson c "$config" '.worktrees[$p] = $c' "$REGISTRY_FILE") || return 1
    _write_registry_atomic "$updated"
}

update_registry() {
    local path="$1" config="$2"
    with_registry_lock _update_registry_locked "$path" "$config"
}

_merge_registry_locked() {
    local path="$1" patch="$2"
    local updated
    updated=$(jq --arg p "$path" --argjson c "$patch" '.worktrees[$p] = ((.worktrees[$p] // {}) + $c)' "$REGISTRY_FILE") || return 1
    _write_registry_atomic "$updated"
}

merge_registry() {
    local path="$1" patch="$2"
    with_registry_lock _merge_registry_locked "$path" "$patch"
}

_remove_registry_entry_locked() {
    local path="$1"
    local updated
    updated=$(jq --arg p "$path" 'del(.worktrees[$p])' "$REGISTRY_FILE") || return 1
    _write_registry_atomic "$updated"
}

remove_registry_entry() {
    local path="$1"
    with_registry_lock _remove_registry_entry_locked "$path"
}

# Stable, collision-free key for a worktree path (two worktrees may share a
# basename under different parents).
worktree_env_key() {
    printf '%s' "$1" | cksum | cut -d ' ' -f1
}

get_next_worktree_index() {
    local max=0 n
    if [ -f "$REGISTRY_FILE" ]; then
        for n in $(jq -r '.allocation.index // 0, ([.worktrees[].index // 0] | max // 0)' "$REGISTRY_FILE" 2>/dev/null); do
            [ "$n" -gt "$max" ] 2>/dev/null && max=$n
        done
    fi
    echo $((max + 1))
}

# ---------------------------------------------------------------------------
# Optional resource adapters — enabled per project in worktree.config.sh
# ---------------------------------------------------------------------------

# Port allocation (WT_PORTS_START/WT_PORTS_END set in config). Ranges must
# not overlap the primary service ports; allocation is registry-tracked and
# liveness-checked.
is_port_in_use() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    else
        nc -z 127.0.0.1 "$port" >/dev/null 2>&1
    fi
}

get_pid_by_port() {
    local port="$1"
    command -v lsof >/dev/null 2>&1 || return 1
    lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1
}

find_available_port() {
    local start="$1" end="$2" used port
    used=$(jq -r '[.worktrees[] | select(.port != null) | .port] | join(" ")' "$REGISTRY_FILE" 2>/dev/null || true)
    for ((port = start; port <= end; port++)); do
        case " $used " in
            *" $port "*) continue ;;
        esac
        if ! is_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

# Isolated per-worktree environment. Always provisions a private TMPDIR
# (shared /tmp TMPDIRs cross-contaminate parallel sessions' temp files).
# When WT_CACHE_DIRS names are configured, one shared-project cache dir per
# name is created (shared on purpose for package caches that are safe for
# concurrent access); unwritable shared roots fall back to per-worktree dirs.
provision_isolated_env() {
    local worktree_path="$1"
    local wt_tmp_dir="$REGISTRY_DIR/tmp/wt-$(worktree_env_key "$worktree_path")"
    mkdir -p "$wt_tmp_dir" 2>/dev/null || return 1
    WT_TMP_DIR="$wt_tmp_dir"
    WT_CACHE_EXPORTS=""
    local name cache_dir
    for name in ${WT_CACHE_DIRS:-}; do
        cache_dir="$REGISTRY_DIR/cache/$name"
        mkdir -p "$cache_dir" 2>/dev/null || true
        if ! touch "$cache_dir/.write-probe" 2>/dev/null; then
            cache_dir="$REGISTRY_DIR/cache/$name-$(worktree_env_key "$worktree_path")"
            mkdir -p "$cache_dir"
        fi
        rm -f "$cache_dir/.write-probe"
        WT_CACHE_EXPORTS="$WT_CACHE_EXPORTS
export WT_CACHE_${name}=\"$cache_dir\""
    done
    return 0
}

# Write the sourcable environment snippet hooks and make targets consume.
write_wt_env_file() {
    local worktree_path="$1"
    {
        echo "# Generated by worktree-manager — per-worktree isolated environment."
        echo "# Source it before builds/tests:  source ./.wt-env.sh"
        echo "export TMPDIR=\"$WT_TMP_DIR/\""
        if [ "${WT_DERIVED_DATA:-0}" = "1" ]; then
            echo "export WT_DERIVED_DATA_PATH=\"$WT_BUILD_DIR\""
        fi
        if [ -n "${WT_PORT:-}" ]; then
            echo "export WT_PORT=\"$WT_PORT\""
        fi
        if [ -n "$WT_CACHE_EXPORTS" ]; then
            printf '%s\n' "$WT_CACHE_EXPORTS"
        fi
    } > "$worktree_path/.wt-env.sh"
}

format_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
