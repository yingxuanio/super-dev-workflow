# Super Dev Workflow

A Codex plugin for isolated Git worktree development: issue triage, dispatch into parallel worktrees, and the guards that keep those worktrees from contaminating each other.

## Install

Add this repository as a plugin marketplace source in Codex, then install `super-dev-workflow`.

The plugin contains these skills:

- `linear-issue-triage`: triage, rewrite, and batch Linear issues into an executable next batch. Stops before implementation.
- `orchestration-dev-dispatch`: dispatch a confirmed batch into isolated worktree sessions, then review and merge.
- `worktree-dev-flow`: implement in the selected worktree, verify, commit, and open a PR. Reuse a non-main worktree; create a new one from main only after confirmation.
- `worktree-parallel-dev`: install, operate, and audit worktree isolation, branch guards, baselines, hooks, and per-worktree resources.
- `apple-cicd-workflow`: configure and audit GitHub Actions build, signing, notarization, and release workflows for Apple apps.
- `deploy-with-frp`: choose a hosting target and deploy, update, troubleshoot, or remove services through FRP and 1Panel.

## Repository layout

```text
.codex-plugin/plugin.json
skills/linear-issue-triage/
skills/orchestration-dev-dispatch/
skills/worktree-dev-flow/
skills/worktree-parallel-dev/
skills/apple-cicd-workflow/
skills/deploy-with-frp/
```

## License

The skill is published without an open-source license grant. All rights are reserved unless the repository owner adds a license.
