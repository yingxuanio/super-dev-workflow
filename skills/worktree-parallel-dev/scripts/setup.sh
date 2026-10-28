#!/usr/bin/env bash
# setup.sh — install the worktree parallel-dev system into a project.
#
# Usage: setup.sh [--force] [project-dir]
#
# Idempotent: re-running updates the system scripts and hooks, but never
# overwrites a project-tuned scripts/worktree.config.sh unless --force.

set -euo pipefail

FORCE=false
PROJECT_DIR="."
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        *) PROJECT_DIR="$1"; shift ;;
    esac
done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$SKILL_DIR/templates"

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
cd "$PROJECT_DIR"

command -v git >/dev/null 2>&1 || { echo "Error: git not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required (brew install jq)" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: $PROJECT_DIR is not a git repository" >&2; exit 1; }

echo "Installing worktree parallel-dev system into: $PROJECT_DIR"
echo ""

mkdir -p scripts .githooks

copy_template() {
    local src="$1" dst="$2" mode="${3:-755}"
    if [ -e "$dst" ] && [ "$FORCE" = false ]; then
        echo "  keep   $dst (exists; --force to overwrite)"
    else
        cp "$src" "$dst"
        chmod "$mode" "$dst"
        echo "  write  $dst"
    fi
}

# 1. System scripts
copy_template "$TPL/worktree-lib.sh"     scripts/worktree-lib.sh
copy_template "$TPL/worktree-manager.sh" scripts/worktree-manager.sh
copy_template "$TPL/worktree-guard.sh"   scripts/worktree-guard.sh

# 2. Git hooks
copy_template "$TPL/githooks/pre-commit" .githooks/pre-commit
copy_template "$TPL/githooks/pre-push"   .githooks/pre-push

# 3. Project config — detect defaults on first install
if [ -e scripts/worktree.config.sh ] && [ "$FORCE" = false ]; then
    echo "  keep   scripts/worktree.config.sh (exists; --force to overwrite)"
else
    main_branch=main
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
    [ -n "$default_branch" ] && main_branch="$default_branch"
    sed -e "s/WT_MAIN_BRANCH=\"\${WT_MAIN_BRANCH:-main}\"/WT_MAIN_BRANCH=\"\${WT_MAIN_BRANCH:-$main_branch}\"/" \
        "$TPL/worktree.config.sh" > scripts/worktree.config.sh
    chmod 644 scripts/worktree.config.sh
    echo "  write  scripts/worktree.config.sh (main branch: $main_branch)"
fi

# 4. Hook path — the mechanism that makes the guards actually run
git config core.hooksPath .githooks
echo "  config core.hooksPath=.githooks"

# 5. Gitignore — per-worktree generated env must never be committed
if [ -f .gitignore ]; then
    for entry in ".wt-env.sh" ; do
        if ! grep -qxF "$entry" .gitignore; then
            printf '%s\n' "$entry" >> .gitignore
            echo "  gitignore +$entry"
        fi
    done
fi

# 6. Makefile targets — only when a Makefile already exists or none at all
if [ ! -f Makefile ]; then
    sed -e "s|__SCRIPT__|scripts/worktree-manager.sh|g" "$TPL/Makefile.snippet" > Makefile
    chmod 644 Makefile
    echo "  write  Makefile (wt-* targets)"
elif ! grep -q "^wt-init" Makefile; then
    printf '\n# --- Worktree parallel development -------------------------------------\n' >> Makefile
    sed -e "s|__SCRIPT__|scripts/worktree-manager.sh|g" "$TPL/Makefile.snippet" >> Makefile
    echo "  append Makefile (wt-* targets)"
else
    echo "  keep   Makefile (wt-* targets already present)"
fi

echo ""
echo "Done. Next steps:"
echo "  ./scripts/worktree-manager.sh doctor          # verify the installation"
echo "  git worktree add ~/.wt/$(basename "$(git remote get-url origin 2>/dev/null | sed 's#.*/##; s#\.git$##')")/<topic> -b <branch>"
echo "  cd into the worktree and run: scripts/worktree-manager.sh init"
