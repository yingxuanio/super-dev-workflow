#!/bin/bash
# worktree.config.sh — per-project configuration for the worktree system.
# Sourced by worktree-manager.sh and the git hooks. Edit freely; keep the
# variable names (the manager and guards read them).

# The branch the PRIMARY checkout must stay on (shared release ground).
WT_MAIN_BRANCH="${WT_MAIN_BRANCH:-main}"

# --- Resource adapters (enable what this project needs) --------------------

# Port allocation range; leave empty if this project runs no dev servers.
WT_PORTS_START=""
WT_PORTS_END=""

# Xcode projects: 1 allocates an isolated per-worktree derived-data dir and
# exports WT_DERIVED_DATA_PATH through .wt-env.sh. Non-Xcode projects: 0.
WT_DERIVED_DATA=0

# Names of shared, concurrency-safe dependency caches to provision under the
# registry (e.g. SPM for Xcode, uv, cargo). Each becomes WT_CACHE_<NAME>.
WT_CACHE_DIRS=""

# --- Shared-surface guard ---------------------------------------------------
# Files matching this regex are release/shared surfaces: when a staged file
# matching it ALSO has uncommitted changes in a sibling worktree, pre-commit
# blocks (cross-task pollution until proven otherwise). Scope this to files
# every task shares — CI workflows, project manifests, release scripts —
# NOT to ordinary source files.
WT_SENSITIVE_RE='^(\.github/workflows/)'

# --- Optional per-project pre-commit hook -----------------------------------
# Runs after the worktree guards with staged files as arguments.
# wt_pre_commit_extra() {
#     local f
#     for f in "$@"; do
#         case "$f" in
#             *.strings|*.lproj/*)
#                 scripts/check-localization.sh || return 1 ;;
#         esac
#     done
#     return 0
# }
