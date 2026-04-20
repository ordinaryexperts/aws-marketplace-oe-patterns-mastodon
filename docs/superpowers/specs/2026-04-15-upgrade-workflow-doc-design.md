# Standardized Upgrade Workflow Doc — Design

## Overview

Create a single canonical `UPGRADE.md` in the `aws-marketplace-utilities` repo that documents the full end-to-end upstream-version upgrade workflow for every AWS Marketplace pattern repo. Each pattern repo's `CLAUDE.md` gets a one-line pointer to this doc.

The goal: one source of truth for how to take a pattern from "upstream released a new version" all the way to "new AMI is live on AWS Marketplace," usable by any team member or AI agent working in any of the ~29 pattern repos.

## Motivation

- There are ~29 pattern repos on GitHub (Mastodon, Discourse, Jitsi, Open WebUI, WordPress, Zulip, Pixelfed, PeerTube, BlueSky PDS, Plane, OpenHands, Rails, ConsulDemocracy, Atlantis, Devika, Backstage, SuiteCRM, Errbit, and others, plus Terraform variants).
- The upgrade workflow is effectively the same across all of them, because `common.mk` (shared from `aws-marketplace-utilities`) normalizes the build/test/publish commands.
- An earlier attempt at full automation (`agents/aws-marketplace-updater/`) was never completed end-to-end and is currently non-functional.
- Simpler option: codify the manual process in markdown, reusable by humans and AI agents.

## Non-Goals

- Automating the upgrade (no scripts beyond what already exists in `common.mk`).
- Per-repo configuration files (`.upgrade.yaml` or similar).
- Replacing or reviving the `aws-marketplace-updater` agent system.
- Covering non-upstream changes (CDK library bumps, infrastructure refactors, bug fixes unrelated to version upgrades).

## Location & Discovery

**Canonical location:** `UPGRADE.md` at the root of `aws-marketplace-utilities`, sibling to `common.mk`.

**Per-repo discovery:** Each pattern repo's `CLAUDE.md` adds one line:

> For upgrading the upstream version, follow the process in [aws-marketplace-utilities/UPGRADE.md](https://github.com/ordinaryexperts/aws-marketplace-utilities/blob/main/UPGRADE.md).

The URL points to `main` so it stays stable as the utilities repo evolves.

**Rationale for utilities repo (vs Claude skill):** The upgrade process is a team process that Claude executes — not Claude-only automation. Putting the source of truth in the utilities repo means it is not tied to any specific AI tool, it is version-controlled alongside the shared infrastructure it references, and teammates can read/edit/contribute to it. A thin Claude skill wrapper can be added later if desired.

## Document Structure

```
UPGRADE.md
├── Overview (what this doc is, when to use it)
├── Prerequisites
│   ├── AWS_PROFILE configured (typically oe-patterns-dev)
│   ├── docker-compose available
│   ├── Repo checked out, on a feature/upgrade branch
│   └── gh CLI authenticated
├── Phase 1: Research
│   ├── Find latest upstream version (per-install-type cheat sheet)
│   └── Diff dependencies since current version
├── Phase 2: Code changes
│   ├── Update version variable in packer/*appinstall.sh
│   ├── Local validation: make synth + make lint
│   └── Create feature/upgrade branch if needed
├── Phase 3: AMI build
│   ├── make ami-ec2-build TEMPLATE_VERSION=<v>
│   ├── Extract new AMI ID from build output
│   └── Update AMI_ID constant in cdk/<app>/<app>_stack.py
├── Phase 4: Integration test
│   ├── make test-main
│   └── Interpreting pass/fail
├── Phase 5: Release
│   ├── git-flow release branch
│   ├── Update CHANGELOG.md
│   ├── Bump template version, tag
│   └── Merge to develop + main
├── Phase 6: Marketplace publishing
│   ├── make ami-ec2-copy (multi-region)
│   ├── make publish TEMPLATE_VERSION=<v>
│   ├── make gen-plf / make plf
│   └── Verification in AWS Marketplace console
└── Troubleshooting (common failures per phase)
```

Each phase is self-contained, with concrete commands, expected-output snippets, explicit success criteria, and rollback notes.

## Handling Install-Method Variation

Install-method differences matter mainly in Phase 1 (version lookup + dep diff). Phases 2-6 are identical across repos because `common.mk` normalizes the surface area. Phase 1 includes a small cheat-sheet table:

| Install method | Example repos | Version lookup | Dep diff command |
|---|---|---|---|
| Source build (git + bundler/npm) | Mastodon | `gh release list --repo <upstream>` | `gh api repos/<u>/compare/v<old>...v<new> --jq '.files[].filename' \| grep -E '(Gemfile\|package\.json\|\.ruby-version\|\.nvmrc)'` |
| Docker base image | Discourse, Jitsi | Docker Hub API or upstream tag list | Compare Dockerfile/compose image tags |
| Pip package | Open WebUI | `pip index versions <pkg>` / PyPI | Compare `requirements.txt` / `setup.py` |
| Direct download (ZIP/tar) | WordPress | Upstream release page | Review upstream release notes |

## Troubleshooting Coverage

Troubleshooting section covers the failures we have actually hit:

- **AMI build fails** — Packer output for missing system packages, upstream dep changes (e.g., Ruby version bump), git clone timeouts.
- **`make synth` errors** — CDK version mismatch, missing `CfnParameter` after upstream-driven config changes.
- **Taskcat `CREATE_FAILED`** — check EC2 user data logs via CloudWatch; links to existing `debugging-ec2-user-data` skill.
- **Taskcat `DELETE_FAILED`** — manual cleanup via `make clean-*-tcat` targets.
- **AMI copy timeouts** — retry with `make ami-ec2-copy`; note region-specific failures.

## Success Criteria (Per Phase)

Each phase states its success criterion explicitly at the top:

1. **Research:** latest version identified, dep diff reviewed, no hard blockers.
2. **Code:** `make synth` + `make lint` pass.
3. **AMI:** build exits 0, new AMI ID captured.
4. **Test:** taskcat reports `CREATE_COMPLETE` in all configured regions, no stack rollback.
5. **Release:** version tag pushed, CHANGELOG merged to `develop` and `main`.
6. **Publish:** AMI visible in AWS Marketplace console, PLF submitted successfully.

## Out of Scope (For Later)

- Helper scripts (e.g., `scripts/check-upstream-version.sh`, `scripts/diff-deps.sh`).
- Per-repo `.upgrade.yaml` config files.
- A Claude Code skill wrapper that invokes the doc via a slash command.

These can be added incrementally if the pure-docs approach reveals specific pain points.

## Open Questions

- Does `aws-marketplace-utilities` have any existing documentation conventions to follow? (To be checked during implementation.)
- Should the doc version-pin references to `common.mk` targets, or always point at `main`? (Current lean: `main`, update doc when `common.mk` interface changes.)
