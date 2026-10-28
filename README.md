# Super Dev Workflow

A Codex plugin that provides the `worktree-parallel-dev` skill for setting up and auditing isolated Git worktree workflows.

## Install

Add this repository as a plugin marketplace source in Codex, then install `super-dev-workflow`.

The plugin contains these skills:

- `worktree-parallel-dev`: install, operate, and audit worktree isolation, branch guards, baselines, hooks, and per-worktree resources.
- `apple-cicd-workflow`: configure and audit GitHub Actions build, signing, notarization, and release workflows for Apple apps.
- `deploy-with-frp`: choose a hosting target and deploy, update, troubleshoot, or remove services through FRP and 1Panel.

## Repository layout

```text
.codex-plugin/plugin.json
skills/worktree-parallel-dev/
skills/apple-cicd-workflow/
skills/deploy-with-frp/
```

## License

The skill is published without an open-source license grant. All rights are reserved unless the repository owner adds a license.
