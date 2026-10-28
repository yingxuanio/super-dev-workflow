#!/usr/bin/env bash
# audit-cicd.sh — score a project's GitHub Actions setup against the Apple
# CI/CD standard (fast PR gate + full rehearsed release pipeline).
#
# Usage: audit-cicd.sh [project-dir]
# Exit 0 = all checks pass; 1 = failures listed.

set -uo pipefail

PROJECT_DIR="${1:-.}"
WF="$PROJECT_DIR/.github/workflows"

PASS=0; FAIL=0
ok()  { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "Apple CI/CD audit: $PROJECT_DIR"
echo ""

if [ ! -d "$WF" ]; then
    echo "✗ no .github/workflows directory"
    exit 1
fi

# 0. All workflow files parse as YAML.
parse_fail=0
for f in "$WF"/*.yml "$WF"/*.yaml; do
    [ -e "$f" ] || continue
    ruby -ryaml -e 'begin; YAML.load_file(ARGV[0]); rescue; abort; end' "$f" 2>/dev/null || { parse_fail=1; echo "      parse error: $f"; }
done
[ "$parse_fail" = "0" ] && ok "all workflow files parse as YAML" || bad "workflow YAML parse errors"

# Identify the PR-gate workflow (pull_request trigger without signing) and the
# release workflow (tag push / full pipeline).
pr_wf=""
rel_wf=""
for f in "$WF"/*.yml "$WF"/*.yaml; do
    [ -e "$f" ] || continue
    if grep -q "pull_request" "$f" && ! grep -q "tags:" "$f"; then pr_wf="$f"; fi
    if grep -qE "^\s*tags:\s*$|push:" "$f" && grep -qE "notarytool|codesign" "$f"; then rel_wf="${rel_wf:-$f}"; fi
done

echo "--- PR gate ---"
if [ -n "$pr_wf" ]; then
    ok "PR gate workflow found: $(basename "$pr_wf")"
    grep -q "concurrency:" "$pr_wf" && grep -A2 "concurrency:" "$pr_wf" | grep -q "cancel-in-progress: true" \
        && ok "concurrency: cancel-in-progress keyed per PR" \
        || bad "missing concurrency group with cancel-in-progress"
    grep -qE "^permissions:\s*$|^\s*permissions:" "$pr_wf" \
        && ! grep -A2 "^permissions:" "$pr_wf" | grep -q "write" \
        && ok "minimal permissions (no write on the PR path)" \
        || bad "PR workflow requests write permissions"
    grep -q "timeout-minutes:" "$pr_wf" && ok "job timeouts set" || bad "no timeout-minutes in PR workflow"
    if grep -qE "notarytool" "$pr_wf"; then
        bad "notarization runs on the PR path (move to the release workflow)"
    else
        ok "no notarization on the PR path"
    fi
    grep -qE "grep -qE? .*(diff --name-only|paths:)" "$pr_wf" || grep -q "paths:" "$pr_wf" || grep -q "diff --name-only" "$pr_wf" \
        && ok "change detection or path filters present" \
        || bad "no change detection — every PR rebuilds everything"
else
    bad "no PR gate workflow found"
fi

echo "--- release pipeline ---"
if [ -n "$rel_wf" ]; then
    ok "release workflow found: $(basename "$rel_wf")"
    grep -q "workflow_dispatch" "$rel_wf" \
        && ok "manual dispatch (rehearsal entry point) present" \
        || bad "no workflow_dispatch — the release path cannot be rehearsed"
    grep -q "cancel-in-progress: false" "$rel_wf" \
        && ok "release concurrency never cancelled mid-publish" \
        || bad "release concurrency missing or cancellable"
    grep -q "merge-base --is-ancestor" "$rel_wf" \
        && ok "release provenance check (tag merged into main)" \
        || bad "no provenance check — unmerged tags can release"
    for tool in codesign notarytool stapler spctl; do
        grep -q "$tool" "$rel_wf" && ok "$tool present in pipeline" || bad "$tool missing from release pipeline"
    done
    grep -B8 "delete-keychain" "$rel_wf" | grep -q "always()" \
        && ok "credential cleanup runs on failure (if: always)" \
        || bad "signing keychain not cleaned up with if: always()"
    grep -q "timeout-minutes:" "$rel_wf" && ok "job timeouts set" || bad "no timeout-minutes"
else
    bad "no release workflow found (signing + notarization pipeline)"
fi

echo ""
echo "Audit: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
