#!/bin/bash
# worktree-manager.sh — git worktree parallel-development manager.
#
# Manages the per-worktree registry, isolated resources, baseline integrity
# and lifecycle for parallel agent/human development on one clone.
#
# Commands:
#   init           Register this worktree and provision its isolated resources
#   list           List all registered worktrees
#   status         Show current worktree status
#   verify         Verify the worktree still matches its registered baseline
#   baseline       Re-record the current branch/HEAD as this worktree's baseline
#   repair         Repair git worktree metadata (prune stale entries)
#   clean          Release this worktree's resources and mark it inactive
#   ports          Show port allocation status (when port adapter is enabled)
#   stop-current   Stop the process this worktree started (when tracked)
#   prune-merged   Remove worktrees whose PR is merged (dir clean & pushed)
#   doctor         Check the installation is complete and healthy
#
# Exit codes for `verify`: 0 = verified, 1 = not a registered worktree,
# 2 = drift detected (never commit or push through drift).

set -euo pipefail

# Script directory (templates are installed into <project>/scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility functions
# shellcheck disable=SC1091
source "$SCRIPT_DIR/worktree-lib.sh"

if ! is_git_repo; then
    echo -e "${RED}Error: not in a git repository${NC}" >&2
    exit 1
fi

REPO_ROOT="$(get_current_worktree)"

# ---------------------------------------------------------------------------
# Project identity + per-project configuration
# ---------------------------------------------------------------------------
# Project slug: basename of origin remote URL, else basename of repo root.
# Slug namespaces the registry so multiple projects never share entries.
derive_project_slug() {
    local url slug
    url=$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)
    if [ -n "$url" ]; then
        slug="$(basename "$url")"
        slug="${slug%.git}"
    else
        slug="$(basename "$REPO_ROOT")"
    fi
    printf '%s' "$slug"
}

PROJECT_SLUG="$(derive_project_slug)"
WT_REGISTRY_ROOT="${WT_REGISTRY_ROOT:-$HOME/.wt-registry}"
REGISTRY_DIR="$WT_REGISTRY_ROOT/$PROJECT_SLUG"
REGISTRY_FILE="$REGISTRY_DIR/registry.json"

# Defaults; a project overrides these in scripts/worktree.config.sh.
WT_MAIN_BRANCH="${WT_MAIN_BRANCH:-main}"
WT_PORTS_START=""
WT_PORTS_END=""
WT_DERIVED_DATA="0"
WT_CACHE_DIRS=""
WT_SENSITIVE_RE='^(\.github/workflows/)'
WT_CONFIG_FILE="$REPO_ROOT/scripts/worktree.config.sh"
# shellcheck disable=SC1090
[ -f "$WT_CONFIG_FILE" ] && source "$WT_CONFIG_FILE"

export REGISTRY_DIR REGISTRY_FILE PROJECT_SLUG WT_MAIN_BRANCH

show_usage() {
    cat <<EOF
Worktree Manager ($PROJECT_SLUG)

Usage: $0 <command> [options]

Commands:
    init            Register this worktree + provision isolated resources
    list            List all registered worktrees
    status          Show current worktree status
    verify          Verify the worktree still matches its registered baseline
    baseline        Re-record current branch/HEAD as this worktree's baseline
    repair          Prune stale git worktree metadata and dangling entries
    clean           Release this worktree's resources (--current / --path P)
    ports           Show port allocation status
    stop-current    Stop the process this worktree started
    prune-merged    Remove worktrees whose PR is merged (--dry-run to preview)
    doctor          Check installation completeness and health

Typical flow:
    git worktree add ~/.wt/<project>/<topic> -b <branch>
    cd ~/.wt/<project>/<topic> && $0 init
    make wt-verify            # before every push (pre-push hook does this)
    $0 prune-merged --dry-run # after merging

Options for 'clean':
    --current         clean the current worktree
    --path PATH       clean a specific worktree
    --delete-build    also delete the isolated build/derived-data dir
    --force           skip confirmation

EOF
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_init() {
    local force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) echo -e "${RED}Error: unknown option '$1'${NC}" >&2; exit 1 ;;
        esac
    done

    init_registry

    local worktree_path branch
    worktree_path=$(get_current_worktree)
    branch=$(get_current_branch)

    echo -e "${BLUE}Initializing worktree resources...${NC}"
    echo -e "Path:     $worktree_path"
    echo -e "Branch:   $branch"
    echo -e "Registry: $REGISTRY_FILE"
    echo ""

    # Gate before any resource work: a feature branch registered on the
    # primary checkout hijacks the shared release ground.
    if primary_registration_refused "$branch"; then
        echo -e "${RED}Error: refusing to register the primary checkout for branch '$branch'${NC}"
        echo ""
        echo "The primary checkout must stay on '$WT_MAIN_BRANCH' — merges and version"
        echo "bumps happen here, and its registry entry must keep matching."
        echo "Run this branch in a linked worktree instead:"
        echo ""
        echo "  git worktree add $HOME/.wt/$PROJECT_SLUG/${branch} -b $branch"
        echo "  cd $HOME/.wt/$PROJECT_SLUG/${branch} && $0 init"
        echo ""
        exit 1
    fi

    local existing_config already_registered=false
    existing_config=$(get_worktree_config "$worktree_path")
    if [ "$(echo "$existing_config" | jq -r 'has("branch")')" = "true" ]; then
        already_registered=true
        [ "$force" = false ] && echo -e "${BLUE}Worktree already registered — reusing its allocation (use --force to re-allocate).${NC}"
    fi

    local index port build_dir tmp_dir
    if [ "$already_registered" = true ]; then
        index=$(echo "$existing_config" | jq -r '.index // 0')
        port=$(echo "$existing_config" | jq -r '.port // ""')
        build_dir=$(echo "$existing_config" | jq -r '.build_dir // ""')
        # Adapters enabled after the first init: allocate only what's missing.
        if [ -z "$port" ] && [ -n "$WT_PORTS_START" ] && [ -n "$WT_PORTS_END" ]; then
            port=$(find_available_port "$WT_PORTS_START" "$WT_PORTS_END" || true)
            [ -z "$port" ] && { echo -e "${RED}Error: no free port in [$WT_PORTS_START, $WT_PORTS_END]${NC}" >&2; exit 1; }
        fi
        if [ -z "$build_dir" ] && [ "$WT_DERIVED_DATA" = "1" ]; then
            build_dir="$REGISTRY_DIR/build/wt-$(worktree_env_key "$worktree_path")"
            mkdir -p "$build_dir"
        fi
    else
        index=$(get_next_worktree_index)
        if [ -n "$WT_PORTS_START" ] && [ -n "$WT_PORTS_END" ]; then
            port=$(find_available_port "$WT_PORTS_START" "$WT_PORTS_END" || true)
            [ -z "$port" ] && { echo -e "${RED}Error: no free port in [$WT_PORTS_START, $WT_PORTS_END]${NC}" >&2; exit 1; }
        fi
        if [ "$WT_DERIVED_DATA" = "1" ]; then
            build_dir="$REGISTRY_DIR/build/wt-$(worktree_env_key "$worktree_path")"
            mkdir -p "$build_dir"
        fi
    fi

    if ! provision_isolated_env "$worktree_path"; then
        echo -e "${RED}Error: could not provision the isolated temp dir${NC}" >&2
        exit 1
    fi
    WT_BUILD_DIR="$build_dir"
    WT_PORT="$port"
    write_wt_env_file "$worktree_path"

    local config head_oid now clean=false
    now=$(format_timestamp)
    head_oid=$(git rev-parse HEAD)
    [ -z "$(git status --porcelain)" ] && clean=true
    config=$(jq -nc \
        --arg branch "$branch" \
        --argjson index "$index" \
        --arg port "${port:-}" \
        --arg build_dir "${build_dir:-}" \
        --arg tmp_dir "$WT_TMP_DIR" \
        --arg created "$now" \
        --arg head "$head_oid" \
        --argjson clean "$clean" \
        '{branch: $branch, index: $index,
          tmp_dir: $tmp_dir, created_at: $created, last_used: $created,
          status: "active",
          baseline: {branch: $branch, head: $head, clean: $clean, recorded_at: $created}}
        | if $port == "" then . else . + {port: $port} end
        | if $build_dir == "" then . else . + {build_dir: $build_dir} end')

    if [ "$already_registered" = true ]; then
        # Preserve created_at; refresh the operational fields.
        config=$(jq -nc --argjson old "$existing_config" --argjson new "$config" \
            '$old + $new | .created_at = $old.created_at | .baseline = $new.baseline | .status = "active"')
    fi

    update_registry "$worktree_path" "$config"

    echo -e "${GREEN}✓${NC} Registered (index $index)"
    if [ -n "$port" ]; then echo -e "${GREEN}✓${NC} Port allocated: $port"; fi
    if [ -n "$build_dir" ]; then echo -e "${GREEN}✓${NC} Isolated build dir: $build_dir"; fi
    echo -e "${GREEN}✓${NC} Isolated TMPDIR: $WT_TMP_DIR"
    echo -e "${GREEN}✓${NC} Baseline recorded: branch=$branch head=$(echo "$head_oid" | cut -c1-10)"
    echo ""
    echo "Source the env before building:   source ./.wt-env.sh"
    if [ "$WT_DERIVED_DATA" = "1" ]; then
        echo "Builds automatically isolate DerivedData via make build."
    fi
}

cmd_list() {
    init_registry
    echo -e "${BLUE}Registered worktrees ($PROJECT_SLUG):${NC}"
    echo ""
    local count
    count=$(jq '.worktrees | length' "$REGISTRY_FILE")
    if [ "$count" -eq 0 ]; then
        echo "  (none — run '$0 init' inside a linked worktree)"
        return 0
    fi
    printf "  %-4s %-28s %-8s %-10s %s\n" "IDX" "BRANCH" "STATUS" "PORT" "PATH"
    jq -r '.worktrees | to_entries[] |
        [.value.index // 0, .value.branch, .value.status // "?", (.value.port // "-"), .key] |
        @tsv' "$REGISTRY_FILE" | sort -n | while IFS=$'\t' read -r idx branch status port path; do
        printf "  %-4s %-28s %-8s %-10s %s\n" "$idx" "$branch" "$status" "$port" "$path"
    done
}

cmd_status() {
    init_registry
    local worktree_path branch
    worktree_path=$(get_current_worktree)
    branch=$(get_current_branch)
    echo -e "${BLUE}Worktree status${NC}"
    echo "  Path:   $worktree_path"
    echo "  Branch: $branch"
    if is_primary_worktree; then
        echo "  Role:   primary checkout (shared release ground)"
    else
        echo "  Role:   linked worktree"
    fi
    local config
    config=$(get_worktree_config "$worktree_path")
    if [ "$(echo "$config" | jq -r 'has("branch")')" != "true" ]; then
        echo -e "  ${YELLOW}Not registered — run '$0 init'${NC}"
    else
        echo "$config" | jq -r '  "  Index:  \(.index)\n  Status: \(.status)\n  Port:   \(.port // "-")\n  Baseline head: \(.baseline.head // "-" | .[0:10])"'
    fi
}

cmd_baseline() {
    init_registry
    local worktree_path
    worktree_path=$(get_current_worktree)
    if ! is_worktree_registered "$worktree_path"; then
        echo -e "${RED}Error: worktree not registered; run '$0 init' first${NC}" >&2
        exit 1
    fi
    local branch head_oid clean=false
    branch=$(get_current_branch)
    head_oid=$(git rev-parse HEAD)
    [ -z "$(git status --porcelain)" ] && clean=true
    merge_registry "$worktree_path" "$(jq -nc \
        --arg branch "$branch" \
        --arg head "$head_oid" \
        --argjson clean "$clean" \
        --arg at "$(format_timestamp)" \
        '{baseline: {branch: $branch, head: $head, clean: $clean, recorded_at: $at}}')"
    echo -e "${GREEN}✓${NC} Baseline recorded: branch=$branch head=$head_oid clean=$clean"
}

cmd_verify() {
    # Exit codes: 0 = verified, 1 = not a registered worktree, 2 = drift.
    init_registry
    local worktree_path
    worktree_path=$(get_current_worktree)

    echo -e "${BLUE}Verifying worktree against registered baseline...${NC}"

    if ! is_worktree_registered "$worktree_path"; then
        echo -e "${RED}✗ Not a registered worktree${NC}"
        echo "Run '$0 init' to register it before starting work."
        exit 1
    fi

    local config registered_branch baseline_branch baseline_head current_branch failed=false
    config=$(get_worktree_config "$worktree_path")
    registered_branch=$(echo "$config" | jq -r '.branch // empty')
    baseline_branch=$(echo "$config" | jq -r '.baseline.branch // empty')
    baseline_head=$(echo "$config" | jq -r '.baseline.head // empty')
    current_branch=$(get_current_branch)

    # 1. Branch ownership: this checkout belongs to one task's branch.
    if [ -n "$registered_branch" ] && [ "$current_branch" != "$registered_branch" ]; then
        echo -e "${RED}✗ Branch drift: checkout is on '$current_branch' but is registered for '$registered_branch'${NC}"
        failed=true
    else
        echo -e "${GREEN}✓${NC} Branch matches registration: $current_branch"
    fi

    # 2. Baseline presence.
    if [ -z "$baseline_head" ]; then
        echo -e "${YELLOW}⚠ No baseline recorded${NC} — record one with: $0 baseline"
    else
        # 3. History intact: every commit since the baseline must sit on top
        #    of it. A reset/rebase elsewhere makes HEAD unreachable from the
        #    baseline and fails here.
        if git merge-base --is-ancestor "$baseline_head" HEAD 2>/dev/null; then
            local ahead
            ahead=$(git rev-list --count "$baseline_head..HEAD" 2>/dev/null || echo "?")
            echo -e "${GREEN}✓${NC} Baseline head $(echo "$baseline_head" | cut -c1-10) is an ancestor of HEAD ($ahead commit(s) ahead)"
        else
            echo -e "${RED}✗ History replaced: baseline $(echo "$baseline_head" | cut -c1-10) is no longer an ancestor of HEAD${NC}"
            failed=true
        fi
        if [ -n "$baseline_branch" ] && [ "$baseline_branch" != "$current_branch" ]; then
            echo -e "${YELLOW}⚠ Baseline was recorded on '$baseline_branch', checkout is on '$current_branch'${NC}"
        fi
    fi

    # 4. Ref-lock contention: a *.lock on OUR branch ref means a sibling
    #    operation is mid-flight right now.
    local common_dir
    common_dir=$(get_git_common_dir_path 2>/dev/null || true)
    if [ -n "$common_dir" ] && [ -e "$common_dir/refs/heads/$current_branch.lock" ]; then
        echo -e "${RED}✗ Ref lock held right now: $common_dir/refs/heads/$current_branch.lock${NC}"
        echo "  Usually transient — wait a few seconds and re-run verify."
        failed=true
    else
        echo -e "${GREEN}✓${NC} No ref lock on $current_branch"
    fi

    # 5. Working tree report (informational — sessions legitimately edit files).
    local dirty
    dirty=$(git status --porcelain 2>/dev/null || true)
    if [ -n "$dirty" ]; then
        local dirty_count
        dirty_count=$(echo "$dirty" | wc -l | tr -d ' ')
        echo -e "${YELLOW}⚠ Working tree dirty: $dirty_count file(s)${NC}"
        echo "$dirty" | head -10 | sed 's/^/    /'
        [ "$dirty_count" -gt 10 ] && echo "    ... ($((dirty_count - 10)) more)"
    else
        echo -e "${GREEN}✓${NC} Working tree clean"
    fi

    # 6. Hooks configured (warn only — commits still work without them).
    local hooks_path
    hooks_path=$(git config --get core.hooksPath 2>/dev/null || true)
    if [ "$hooks_path" = ".githooks" ] && [ -x ".githooks/pre-commit" ]; then
        echo -e "${GREEN}✓${NC} Git hooks installed (core.hooksPath=$hooks_path)"
    else
        echo -e "${YELLOW}⚠ Git hooks not installed; run 'make hooks-install' or: git config core.hooksPath .githooks${NC}"
    fi

    echo ""
    if [ "$failed" = true ]; then
        echo -e "${RED}Verification FAILED — stop and recover before committing/pushing.${NC}"
        echo ""
        echo "Recovery:"
        echo "  Inspect what moved:   git log --oneline --decorate -10"
        echo "  Inspect reflog:       git reflog -10"
        if [ -n "$baseline_head" ]; then
            echo "  Diff vs baseline:     git log --oneline ${baseline_head}..HEAD"
        fi
        echo "  If the drift is yours and intended:"
        echo "      $0 baseline   # accept the new state"
        echo "  If it is NOT yours: investigate before writing anything else here;"
        echo "  committing on moved state is how files leak across tasks."
        exit 2
    fi

    echo -e "${GREEN}Verified: worktree matches its baseline.${NC}"
}

cmd_repair() {
    echo -e "${BLUE}Repairing git worktree metadata...${NC}"
    git worktree prune -v || true
    if [ -f "$REGISTRY_FILE" ]; then
        # Drop registry entries whose directories no longer exist.
        local stale
        stale=$(jq -r '.worktrees | to_entries[] | select((.key | test("^/") | not) or false) | .key' "$REGISTRY_FILE" 2>/dev/null || true)
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            if [ ! -d "$path" ]; then
                remove_registry_entry "$path" && echo -e "${GREEN}✓${NC} Removed stale registry entry: $path"
            fi
        done < <(jq -r '.worktrees | keys[]' "$REGISTRY_FILE" 2>/dev/null)
    fi
    git worktree list
}

cmd_clean() {
    local worktree_path="" delete_build=false force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --current) worktree_path=$(get_current_worktree); shift ;;
            --path) worktree_path="$2"; shift 2 ;;
            --delete-build) delete_build=true; shift ;;
            --force) force=true; shift ;;
            *) echo -e "${RED}Error: unknown option '$1'${NC}" >&2; exit 1 ;;
        esac
    done
    [ -z "$worktree_path" ] && { echo -e "${RED}Error: specify --current or --path PATH${NC}" >&2; exit 1; }

    if ! is_worktree_registered "$worktree_path"; then
        echo -e "${RED}Error: worktree not registered: $worktree_path${NC}" >&2
        exit 1
    fi

    local config port build_dir tmp_dir
    config=$(get_worktree_config "$worktree_path")
    port=$(echo "$config" | jq -r '.port // ""')
    build_dir=$(echo "$config" | jq -r '.build_dir // ""')
    tmp_dir=$(echo "$config" | jq -r '.tmp_dir // ""')

    echo -e "${BLUE}Cleaning up worktree resources...${NC}"
    echo "Path: $worktree_path"
    echo ""

    if [ "$force" = false ]; then
        echo -e "${YELLOW}This will:${NC}"
        [ -n "$port" ] && echo "  - stop the process on port $port"
        [ -n "$tmp_dir" ] && echo "  - delete the isolated temp dir"
        [ "$delete_build" = true ] && [ -n "$build_dir" ] && echo "  - delete the isolated build dir"
        echo "  - remove .wt-env.sh and mark the entry inactive"
        echo ""
        printf 'Continue? (y/N): '
        read -r reply
        case "$reply" in [Yy]*) ;; *) echo "Cancelled"; exit 0 ;; esac
    fi

    if [ -n "$port" ]; then
        local pid
        pid=$(get_pid_by_port "$port" || true)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
            echo -e "${GREEN}✓${NC} Stopped pid $pid on port $port"
        fi
    fi

    [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ] && rm -rf "$tmp_dir" && echo -e "${GREEN}✓${NC} Removed tmp dir"
    if [ "$delete_build" = true ] && [ -n "$build_dir" ] && [ -d "$build_dir" ]; then
        rm -rf "$build_dir" && echo -e "${GREEN}✓${NC} Removed build dir"
    fi

    if [ -f "$worktree_path/.wt-env.sh" ]; then
        rm -f "$worktree_path/.wt-env.sh"
        echo -e "${GREEN}✓${NC} Removed .wt-env.sh"
    fi

    local config_updated
    config_updated=$(echo "$config" | jq '.status = "inactive" | .port = null | .last_used = "'"$(format_timestamp)"'"')
    update_registry "$worktree_path" "$config_updated"
    echo -e "${GREEN}✓${NC} Registry updated (status: inactive)"
    echo ""
    echo "To remove the checkout entirely:  git worktree remove '$worktree_path'"
}

cmd_ports() {
    [ -n "$WT_PORTS_START" ] && [ -n "$WT_PORTS_END" ] || {
        echo "Port adapter not enabled (set WT_PORTS_START/WT_PORTS_END in scripts/worktree.config.sh)."
        return 0
    }
    init_registry
    echo -e "${BLUE}Port allocation ($WT_PORTS_START-$WT_PORTS_END):${NC}"
    jq -r '.worktrees | to_entries[] | select(.value.port != null) |
        "  \(.value.port)\t\(.value.branch)\t\(.key)"' "$REGISTRY_FILE" | sort -n
}

cmd_stop_current() {
    local worktree_path config port pid
    worktree_path=$(get_current_worktree)
    config=$(get_worktree_config "$worktree_path")
    port=$(echo "$config" | jq -r '.port // ""')
    if [ -z "$port" ]; then
        echo "No port allocated for this worktree; nothing to stop."
        return 0
    fi
    pid=$(get_pid_by_port "$port" || true)
    if [ -n "$pid" ]; then
        kill "$pid" && echo -e "${GREEN}✓${NC} Stopped pid $pid (port $port)"
    else
        echo "Nothing listening on port $port."
    fi
}

# Fully remove worktrees whose PR is merged. Every removal is gated on three
# independent signals: the PR is MERGED (or the branch is an ancestor of the
# main branch when it has no PR), the checkout is clean, and every commit is
# pushed. The primary checkout is never touched.
#
# The merge check runs BEFORE the push check on purpose: GitHub deletes the
# head branch after a squash merge, so refs/remotes/origin/<branch> is gone
# and a push gate that short-circuits on it reports merged worktrees as
# "never pushed". Once the PR is known merged, HEAD == its headRefOid proves
# the same thing the missing ref was meant to prove.
cmd_prune_merged() {
    local dry_run=false
    [ "${1:-}" = "--dry-run" ] && dry_run=true

    command -v gh >/dev/null 2>&1 || { echo -e "${RED}Error: gh CLI is required to look up PR state${NC}" >&2; exit 1; }
    [ -f "$REGISTRY_FILE" ] || { echo -e "${YELLOW}No worktree registry found; nothing to prune.${NC}"; exit 0; }

    local main_worktree
    main_worktree=$(get_main_worktree_path 2>/dev/null || echo "")

    local removed=0 kept=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -d "$path" ] || { remove_registry_entry "$path" 2>/dev/null || true; continue; }
        [ "$path" = "$main_worktree" ] && continue

        local cfg branch status
        cfg=$(get_worktree_config "$path")
        branch=$(echo "$cfg" | jq -r '.branch // empty')
        status=$(echo "$cfg" | jq -r '.status // "active"')
        [ -z "$branch" ] && continue

        local reason=""
        if [ "$status" != "active" ]; then
            # Inactive entries still hold a checkout; they are pruned by the
            # same merged-gate below (branch may still have an open PR).
            :
        fi

        # Gate 1: merged?
        local pr_state pr_head
        pr_state=$(gh pr list --repo "$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null | sed -E 's#.*github.com[:/]##; s#\.git$##')" \
            --state merged --head "$branch" --json number,state,headRefOid --limit 1 \
            --jq 'first // empty' 2>/dev/null || echo "")
        if [ -n "$pr_state" ]; then
            pr_head=$(echo "$pr_state" | jq -r '.headRefOid // empty')
            local head_oid
            head_oid=$(git -C "$path" rev-parse HEAD 2>/dev/null || echo "")
            if [ -n "$pr_head" ] && [ "$pr_head" != "$head_oid" ]; then
                reason="PR merged but HEAD moved since ($head_oid != $pr_head)"
            fi
        else
            # No merged PR: is the branch an ancestor of main? (no-PR flows)
            git -C "$REPO_ROOT" fetch --quiet origin "$WT_MAIN_BRANCH" 2>/dev/null || true
            git -C "$REPO_ROOT" merge-base --is-ancestor "$branch" "origin/$WT_MAIN_BRANCH" 2>/dev/null || \
                reason="no merged PR and branch not in $WT_MAIN_BRANCH"
        fi

        # Gate 2: clean checkout?
        if [ -z "$reason" ] && [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
            reason="checkout has uncommitted changes"
        fi

        # Gate 3: everything pushed? (only when no merged PR proved it)
        if [ -z "$reason" ] && [ -z "$pr_state" ]; then
            if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$branch" "origin/$branch" 2>/dev/null; then
                reason="has unpushed commits"
            fi
        fi

        if [ -n "$reason" ]; then
            echo -e "  KEEP $path — $reason"
            kept=$((kept + 1))
            continue
        fi

        if [ "$dry_run" = true ]; then
            echo -e "  REMOVE $path (merged, clean, pushed)"
            removed=$((removed + 1))
        else
            git -C "$REPO_ROOT" worktree remove "$path" || {
                echo -e "${YELLOW}⚠${NC} could not remove $path (git refused); skipping" >&2
                kept=$((kept + 1))
                continue
            }
            remove_registry_entry "$path"
            echo -e "${GREEN}✓${NC} Removed $path"
            removed=$((removed + 1))
        fi
    done < <(jq -r '.worktrees | keys[]' "$REGISTRY_FILE" 2>/dev/null)

    echo ""
    if [ "$dry_run" = true ]; then
        echo "Dry run: $removed would be removed, $kept kept. Re-run without --dry-run to apply."
    else
        echo "Pruned $removed worktree(s); $kept kept."
    fi
}

cmd_doctor() {
    local fail=0
    echo -e "${BLUE}Worktree system doctor ($PROJECT_SLUG)${NC}"
    echo ""

    check() {
        if [ "$2" = "0" ]; then
            echo -e "${GREEN}✓${NC} $1"
        else
            echo -e "${RED}✗${NC} $1"
            fail=1
        fi
    }

    command -v jq >/dev/null 2>&1; check "jq is installed" $?
    command -v git >/dev/null 2>&1; check "git is installed" $?

    local gv
    gv=$(git --version | awk '{print $3}')
    if awk -v v="$gv" 'BEGIN{split(v,a,"."); exit !(a[1]>2 || (a[1]==2 && a[2]>=15))}'; then
        check "git >= 2.15 (worktree --path-format): $gv" 0
    else
        check "git >= 2.15 (worktree --path-format): $gv" 1
    fi

    [ -f "$SCRIPT_DIR/worktree-lib.sh" ]; check "scripts/worktree-lib.sh present" $?
    [ -f "$SCRIPT_DIR/worktree-guard.sh" ]; check "scripts/worktree-guard.sh present" $?
    bash -n "$SCRIPT_DIR/worktree-lib.sh" 2>/dev/null; check "worktree-lib.sh parses" $?
    bash -n "$SCRIPT_DIR/worktree-manager.sh" 2>/dev/null; check "worktree-manager.sh parses" $?

    [ -f "$REPO_ROOT/.githooks/pre-commit" ] && [ -x "$REPO_ROOT/.githooks/pre-commit" ]
    check ".githooks/pre-commit present and executable" $?
    [ -f "$REPO_ROOT/.githooks/pre-push" ] && [ -x "$REPO_ROOT/.githooks/pre-push" ]
    check ".githooks/pre-push present and executable" $?

    [ "$(git config --get core.hooksPath 2>/dev/null)" = ".githooks" ]
    check "core.hooksPath is .githooks" $?

    [ -f "$WT_CONFIG_FILE" ]; check "scripts/worktree.config.sh present" $?

    init_registry >/dev/null 2>&1; check "registry readable at $REGISTRY_FILE" $?

    # Warn about linked worktrees that were never registered.
    local unregistered=""
    while IFS= read -r wt; do
        [ "$wt" = "$REPO_ROOT" ] && continue
        is_worktree_registered "$wt" || unregistered="$unregistered$wt\n"
    done < <(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print}')
    if [ -n "$unregistered" ]; then
        echo -e "${YELLOW}⚠ Linked worktrees not registered:${NC}"
        printf "$unregistered" | sed 's/^/    /'
        echo "    (run '$0 init' inside each before working in them)"
    else
        echo -e "${GREEN}✓${NC} No unregistered linked worktrees"
    fi

    echo ""
    if [ "$fail" = 0 ]; then
        echo -e "${GREEN}Doctor: all checks passed.${NC}"
    else
        echo -e "${RED}Doctor: some checks failed.${NC}"
        exit 1
    fi
}

main() {
    [ $# -eq 0 ] && { show_usage; exit 1; }
    local command="$1"
    shift
    case "$command" in
        init)         cmd_init "$@" ;;
        list)         cmd_list "$@" ;;
        status)       cmd_status "$@" ;;
        verify)       cmd_verify "$@" ;;
        baseline)     cmd_baseline "$@" ;;
        repair)       cmd_repair "$@" ;;
        clean)        cmd_clean "$@" ;;
        ports)        cmd_ports "$@" ;;
        stop-current) cmd_stop_current "$@" ;;
        prune-merged) cmd_prune_merged "$@" ;;
        doctor)       cmd_doctor "$@" ;;
        help|--help|-h) show_usage; exit 0 ;;
        *) echo -e "${RED}Error: unknown command '$command'${NC}" >&2; echo ""; show_usage; exit 1 ;;
    esac
}

main "$@"
