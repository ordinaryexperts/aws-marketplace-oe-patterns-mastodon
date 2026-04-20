# Upgrade Workflow Doc Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a single canonical `UPGRADE.md` in `aws-marketplace-utilities` that documents the end-to-end upstream-version upgrade workflow for any AWS Marketplace pattern repo, and add a one-line pointer to it from each pattern repo's `CLAUDE.md`.

**Architecture:** Pure markdown documentation. Source of truth lives in `aws-marketplace-utilities/UPGRADE.md`. Each pattern repo's `CLAUDE.md` adds a single-line reference link. No helper scripts, no config files.

**Tech Stack:** Markdown. Uses existing `common.mk` targets (documented, not modified). Uses `gh` CLI for upstream version lookups.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `aws-marketplace-utilities/UPGRADE.md` | Create | Canonical end-to-end upgrade doc (Phase 1-6 + Prereqs + Troubleshooting) |
| `aws-marketplace-utilities/CHANGELOG.md` | Modify | Note addition of UPGRADE.md |
| `aws-marketplace-oe-patterns-mastodon/CLAUDE.md` | Modify | Add pointer to UPGRADE.md |
| (deferred) Other pattern repo CLAUDE.mds | Modify | Add same pointer — done as follow-up PRs |

**Repo locations on disk:**
- `/home/dylan/src/oe/patterns/aws-marketplace-utilities`
- `/home/dylan/src/oe/patterns/aws-marketplace-oe-patterns-mastodon`

**Git model for utilities repo:** git-flow. `main` is production, `develop` is integration. Work goes on a `feature/*` branch off `develop`.

---

## Task 1: Set up feature branch in utilities repo

**Files:**
- None yet (branch setup only)

- [ ] **Step 1: Verify utilities repo state**

```bash
cd /home/dylan/src/oe/patterns/aws-marketplace-utilities
git status
git branch --show-current
```

Expected: clean tree, on `develop`.

- [ ] **Step 2: Create feature branch**

```bash
git checkout -b feature/upgrade-workflow-doc
```

- [ ] **Step 3: Verify branch**

```bash
git branch --show-current
```

Expected: `feature/upgrade-workflow-doc`.

---

## Task 2: Write UPGRADE.md — header and prerequisites

**Files:**
- Create: `/home/dylan/src/oe/patterns/aws-marketplace-utilities/UPGRADE.md`

- [ ] **Step 1: Create UPGRADE.md with header + Prerequisites section**

```markdown
# Upgrade Workflow

End-to-end guide for upgrading the upstream application version in an AWS Marketplace pattern repo.

Applies to any repo using `common.mk` from this repository (Mastodon, Discourse, Jitsi, Open WebUI, WordPress, Zulip, Pixelfed, PeerTube, BlueSky PDS, Plane, OpenHands, Rails, ConsulDemocracy, Atlantis, Devika, Backstage, SuiteCRM, Errbit, etc.).

## When to use this

Use this doc when the upstream project (e.g. mastodon/mastodon) has released a new version that you want to ship as a new release of the pattern.

Do NOT use this doc for:
- CDK library version bumps
- Infrastructure refactors unrelated to an upstream upgrade
- Bug fixes in the pattern code itself

## Prerequisites

- AWS profile configured. Typically `oe-patterns-dev` for testing: `export AWS_PROFILE=oe-patterns-dev`.
- Docker + docker-compose available (all `make` targets run through docker-compose).
- `gh` CLI authenticated: `gh auth status`.
- Pattern repo checked out.
- Working from a `feature/upgrade` branch (git-flow).

## Phases at a glance

1. **Research** — identify target version, diff dependencies
2. **Code changes** — bump version in packer script, validate locally
3. **AMI build** — build new AMI, update CDK `AMI_ID`
4. **Integration test** — run taskcat
5. **Release** — git-flow release, CHANGELOG, tag
6. **Marketplace publishing** — copy AMI to regions, publish template, update PLF
```

- [ ] **Step 2: Commit**

```bash
cd /home/dylan/src/oe/patterns/aws-marketplace-utilities
git add UPGRADE.md
git commit -m "docs: add UPGRADE.md header and prerequisites"
```

---

## Task 3: Write UPGRADE.md — Phase 1 (Research)

**Files:**
- Modify: `aws-marketplace-utilities/UPGRADE.md` (append)

- [ ] **Step 1: Append Phase 1 section**

Append to `UPGRADE.md`:

````markdown

## Phase 1: Research

**Success criterion:** You have identified the target upstream version and reviewed its dependency diff against the currently-deployed version. No hard blockers (e.g., major runtime version bump requiring packer script changes) are unaddressed.

### 1.1 Find the current version

Look in the pattern repo's packer install script (typically `packer/ubuntu_2404_appinstall.sh`). The version is usually a variable near the top:

```bash
MASTODON_VERSION=4.5.6         # Mastodon
JITSI_VERSION=stable-10590     # Jitsi
OPEN_WEBUI_VERSION=0.6.43      # Open WebUI
WORDPRESS_VERSION=6.7.2        # WordPress
```

Discourse pins a git commit of `discourse_docker` plus a base image tag — see the `git checkout <sha>` and `discourse/base:<tag>` lines.

### 1.2 Find the latest upstream version

| Install method | Example repos | Version lookup |
|---|---|---|
| Source build (git + bundler/npm) | Mastodon | `gh release list --repo <owner>/<upstream>` |
| Docker base image | Discourse, Jitsi | Docker Hub tag list, or upstream release tags via `gh api repos/<u>/tags` |
| Pip package | Open WebUI | `pip index versions <package>` or PyPI release page |
| Direct download (ZIP/tar) | WordPress | Upstream release / downloads page |

Example:

```bash
gh release list --repo mastodon/mastodon --limit 10
```

### 1.3 Diff dependencies

For source-build repos, compare key dependency files between the old and new tags:

```bash
gh api repos/<owner>/<upstream>/compare/v<old>...v<new> \
  --jq '.files[] | select(.filename | test("^(\\.ruby-version|\\.nvmrc|Gemfile|Gemfile\\.lock|package\\.json|Dockerfile)$")) | .filename'
```

If `.ruby-version`, `.nvmrc`, or Dockerfile base images changed, the packer script probably needs updates beyond the version variable bump.

For Docker-based repos, compare the Dockerfile / compose file image tags in the upstream diff.

For pip packages, compare `requirements.txt` / `pyproject.toml` / `setup.py`.

For direct-download repos, read the upstream release notes and migration guide.

### 1.4 Read the upstream release notes

Always read the release notes between the current and target versions. Flag:
- Database migrations that require downtime or manual steps
- Breaking config changes (env vars removed/renamed)
- Minimum runtime version bumps (Ruby, Node, Python, PHP)
- Removed features you depend on
````

- [ ] **Step 2: Commit**

```bash
git add UPGRADE.md
git commit -m "docs: add Phase 1 (Research) to UPGRADE.md"
```

---

## Task 4: Write UPGRADE.md — Phase 2 (Code changes)

**Files:**
- Modify: `aws-marketplace-utilities/UPGRADE.md` (append)

- [ ] **Step 1: Append Phase 2 section**

Append:

````markdown

## Phase 2: Code changes

**Success criterion:** `make synth` and `make lint` both succeed with the new version in place. No CDK template errors.

### 2.1 Create a feature branch (if not already on one)

```bash
cd /path/to/pattern-repo
git checkout develop
git pull
git checkout -b feature/upgrade
```

### 2.2 Bump the version variable

Edit `packer/ubuntu_2404_appinstall.sh` (or `packer/ubuntu_2204_appinstall.sh` for older WordPress). Update the single version variable identified in Phase 1.

If Phase 1 found additional dependency changes:
- New Ruby version → update `RUBY_VERSION=`
- New Node major → update the `setup_XX.x` curl URL in the Node.js section
- New Python minor → update `PYTHON_VERSION=`
- New packer script version from this utilities repo → update `SCRIPT_VERSION=`

### 2.3 Local validation

```bash
make synth
make lint
```

Expected: synth writes `cdk.out/` without errors; lint reports no issues (or only pre-existing warnings).

If synth errors, the upstream change may have required a CDK code change. Investigate and fix before continuing.
````

- [ ] **Step 2: Commit**

```bash
git add UPGRADE.md
git commit -m "docs: add Phase 2 (Code changes) to UPGRADE.md"
```

---

## Task 5: Write UPGRADE.md — Phase 3 (AMI build)

**Files:**
- Modify: `aws-marketplace-utilities/UPGRADE.md` (append)

- [ ] **Step 1: Append Phase 3 section**

Append:

````markdown

## Phase 3: AMI build

**Success criterion:** Packer build exits 0. New AMI ID captured. `AMI_ID` constant in the CDK stack updated.

### 3.1 Build the AMI

```bash
AWS_PROFILE=oe-patterns-dev make ami-ec2-build TEMPLATE_VERSION=<new-version>
```

Typical duration: 20-40 minutes depending on the pattern.

Build output is also saved to `logs/ami-build-YYYYMMDD-HHMMSS.log` (see utilities repo README).

### 3.2 Capture the new AMI ID

The successful build prints lines like:

```
--> amazon-ebs: AMIs were created:
us-east-1: ami-0827c962454fe7bc0
```

Or at the bottom:

```
AMI_ID="ami-0827c962454fe7bc0"
```

### 3.3 Update the CDK stack

Edit `cdk/<app>/<app>_stack.py`. Find the `AMI_ID=` constant near the top:

```python
AMI_ID="ami-0827c962454fe7bc0" # ordinary-experts-patterns-<app>-<version>
```

Update both the ID and the trailing comment.

### 3.4 Verify synth still passes

```bash
make synth
```

Expected: clean synth with the new AMI ID.
````

- [ ] **Step 2: Commit**

```bash
git add UPGRADE.md
git commit -m "docs: add Phase 3 (AMI build) to UPGRADE.md"
```

---

## Task 6: Write UPGRADE.md — Phase 4 (Integration test)

**Files:**
- Modify: `aws-marketplace-utilities/UPGRADE.md` (append)

- [ ] **Step 1: Append Phase 4 section**

Append:

````markdown

## Phase 4: Integration test

**Success criterion:** `make test-main` completes with taskcat reporting `CREATE_COMPLETE` in all configured regions and no stack rollback.

### 4.1 Run taskcat

```bash
AWS_PROFILE=oe-patterns-dev make test-main
```

Typical duration: 20-40 minutes.

### 4.2 Interpret results

Search the output (or the taskcat log under `taskcat_outputs/`) for:

- `CREATE_COMPLETE` — stack deployed successfully
- `CREATE_FAILED` / `ROLLBACK_IN_PROGRESS` — stack failed; investigate
- `DELETE_COMPLETE` — taskcat cleaned up after itself

Example successful tail:

```
[INFO   ] : ┏ stack Ⓜ tCaT-<stack-name>
[INFO   ] : ┣ region: us-east-1
[INFO   ] : ┗ status: CREATE_COMPLETE
```

### 4.3 If tests fail

Most test failures manifest as EC2 user data script errors (the stack creates fine but instances fail to become healthy).

- Check CloudFormation events in the AWS console for the failure reason
- Check EC2 user data logs via the `debugging-ec2-user-data` skill — CloudWatch Logs group `/aws/ec2/<stack>` or SSM session on the instance
- Check `/var/log/cloud-init-output.log` on the instance for script errors

Common causes:
- Upstream app expects a newer runtime version that wasn't updated in the packer script
- Upstream config format changed; user_data.sh needs an update
- Network/IAM issue fetching secrets from Secrets Manager

### 4.4 Clean up failed tests

If taskcat leaves stacks or buckets behind:

```bash
make clean-snapshots-tcat
make clean-logs-tcat
make clean-buckets-tcat
```

### 4.5 Commit

```bash
git add packer/*.sh cdk/*/*_stack.py
git commit -m "feat: upgrade to <upstream> <new-version>"
git push -u origin feature/upgrade
```
````

- [ ] **Step 2: Commit**

```bash
git add UPGRADE.md
git commit -m "docs: add Phase 4 (Integration test) to UPGRADE.md"
```

---

## Task 7: Write UPGRADE.md — Phase 5 (Release)

**Files:**
- Modify: `aws-marketplace-utilities/UPGRADE.md` (append)

- [ ] **Step 1: Append Phase 5 section**

Append:

````markdown

## Phase 5: Release

**Success criterion:** Version tag pushed to origin. `CHANGELOG.md` updated and merged to `develop` and `main`.

This follows git-flow.

### 5.1 Open a PR from feature/upgrade → develop

Use `gh pr create` or the GitHub web UI. Get review, merge.

### 5.2 Start a release branch

```bash
git checkout develop
git pull
git checkout -b release/<new-pattern-version>
```

The pattern version is independent from the upstream version — it is the version of the CloudFormation template / Marketplace product (e.g. `2.4.0`). Bump major/minor/patch per semver of what changed.

### 5.3 Update CHANGELOG.md

Document the upgrade, breaking changes, and any manual migration steps users need to follow.

### 5.4 Finish the release

```bash
git commit -am "<pattern-version>"
git checkout main
git merge --no-ff release/<new-pattern-version>
git tag <new-pattern-version>
git checkout develop
git merge --no-ff release/<new-pattern-version>
git branch -d release/<new-pattern-version>
git push origin main develop <new-pattern-version>
```
````

- [ ] **Step 2: Commit**

```bash
git add UPGRADE.md
git commit -m "docs: add Phase 5 (Release) to UPGRADE.md"
```

---

## Task 8: Write UPGRADE.md — Phase 6 (Marketplace publishing)

**Files:**
- Modify: `aws-marketplace-utilities/UPGRADE.md` (append)

- [ ] **Step 1: Append Phase 6 section**

Append:

````markdown

## Phase 6: Marketplace publishing

**Success criterion:** AMI copied to all supported regions. CloudFormation template published to S3. PLF submitted and visible in the AWS Marketplace console.

### 6.1 Copy the AMI to all supported regions

```bash
AWS_PROFILE=oe-patterns-dev make ami-ec2-copy AMI_ID=<new-ami-id>
```

Duration: 10-20 minutes. If any region fails, re-run just that region manually or retry the target.

### 6.2 Publish the CloudFormation template to S3

```bash
AWS_PROFILE=oe-patterns-dev make publish TEMPLATE_VERSION=<new-pattern-version>
```

This uploads the synthesized template to the public artifact bucket used by the Marketplace listing.

### 6.3 Generate and submit the PLF

```bash
AWS_PROFILE=oe-patterns-dev make gen-plf AMI_ID=<new-ami-id> TEMPLATE_VERSION=<new-pattern-version>
AWS_PROFILE=oe-patterns-dev make plf AMI_ID=<new-ami-id> TEMPLATE_VERSION=<new-pattern-version>
```

For partial updates, use `make plf-skip-pricing` or `make plf-skip-region` as appropriate.

### 6.4 Verify in AWS Marketplace Management Portal

- Log in to the AWS Marketplace Management Portal
- Confirm the new version appears in the product's version list
- Confirm the AMI IDs match the copied regions
- Confirm the template URL resolves and is the correct version
- Submit for AWS review if required by the product lifecycle
````

- [ ] **Step 2: Commit**

```bash
git add UPGRADE.md
git commit -m "docs: add Phase 6 (Marketplace publishing) to UPGRADE.md"
```

---

## Task 9: Write UPGRADE.md — Troubleshooting section

**Files:**
- Modify: `aws-marketplace-utilities/UPGRADE.md` (append)

- [ ] **Step 1: Append Troubleshooting section**

Append:

````markdown

## Troubleshooting

### AMI build fails

**Symptoms:** `make ami-ec2-build` exits non-zero, Packer logs show provisioning errors.

- Missing system packages — upstream may have added a new dependency. Add to the `apt install` line in the packer script.
- Runtime version mismatch — upstream bumped Ruby/Node/Python. Update the version variable in the packer script (see Phase 1.3).
- Network timeout during `git clone` or `apt-get` — retry; if persistent, the upstream repo/package mirror may be down.
- Asset precompile OOM — increase Packer instance type in `packer/ami.json`.

### `make synth` errors

**Symptoms:** CDK throws during synthesis.

- CDK library mismatch — check `cdk/setup.py` for `oe-patterns-cdk-common` pin; upgrade if needed.
- Missing `CfnParameter` — the upstream upgrade may require a new configuration parameter. Add to the stack.
- Python import errors — run `make build` to rebuild the devenv container.

### Taskcat `CREATE_FAILED`

**Symptoms:** Stack creation fails during `make test-main`.

- EC2 instances fail health checks — most common. Investigate user_data execution:
  - CloudFormation console → Events tab on the failed stack
  - Use the `debugging-ec2-user-data` skill
  - SSM session into the instance, check `/var/log/cloud-init-output.log` and `/var/log/syslog`
- Secrets Manager access denied — IAM role change needed
- Database connection — Aurora may not be ready; check timeouts in user_data.sh

### Taskcat `DELETE_FAILED`

**Symptoms:** Taskcat cannot fully tear down resources after test.

- S3 bucket not empty — use the AWS console or CLI to empty then delete
- Snapshot retention — run `make clean-snapshots-tcat`
- Orphaned security groups / ENIs — manual cleanup in the AWS console

### AMI copy timeouts

**Symptoms:** `make ami-ec2-copy` hangs or fails in a specific region.

- EBS snapshot quota — check Service Quotas in the target region
- Cross-region bandwidth — retry the specific region
- Region not enabled on the account — enable or skip

### Reference: existing skills

- `debugging-ec2-user-data` — step-by-step EC2 boot failure investigation
- Pattern repo `CLAUDE.md` — project-specific context and conventions
````

- [ ] **Step 2: Commit**

```bash
git add UPGRADE.md
git commit -m "docs: add Troubleshooting section to UPGRADE.md"
```

---

## Task 10: Update utilities repo CHANGELOG and README

**Files:**
- Modify: `aws-marketplace-utilities/CHANGELOG.md`
- Modify: `aws-marketplace-utilities/README.md`

- [ ] **Step 1: Read current CHANGELOG**

```bash
cat aws-marketplace-utilities/CHANGELOG.md
```

- [ ] **Step 2: Add unreleased entry**

Add at top of CHANGELOG.md:

```markdown
## Unreleased

- Added `UPGRADE.md` — end-to-end upstream-version upgrade workflow for pattern repos.
```

- [ ] **Step 3: Add section to README**

Append to `README.md`:

```markdown
## Upgrade Workflow

See [UPGRADE.md](./UPGRADE.md) for the end-to-end process of upgrading the upstream application version in any AWS Marketplace pattern repo that uses `common.mk`.
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md README.md
git commit -m "docs: reference UPGRADE.md from CHANGELOG and README"
```

---

## Task 11: Verify UPGRADE.md end-to-end

**Files:**
- Read-only review

- [ ] **Step 1: Read the complete UPGRADE.md**

```bash
cat /home/dylan/src/oe/patterns/aws-marketplace-utilities/UPGRADE.md | less
```

- [ ] **Step 2: Verify commands against Mastodon's actual workflow**

Cross-reference every command in UPGRADE.md against the Mastodon repo's real `Makefile` / `common.mk` targets:

```bash
grep -E '^[a-z-]+:' /home/dylan/src/oe/patterns/aws-marketplace-utilities/common.mk | head -40
```

Ensure each referenced target actually exists: `ami-ec2-build`, `ami-ec2-copy`, `synth`, `lint`, `test-main`, `clean-snapshots-tcat`, `clean-logs-tcat`, `clean-buckets-tcat`, `publish`, `gen-plf`, `plf`, `plf-skip-pricing`, `plf-skip-region`.

- [ ] **Step 3: Fix any mismatches found**

If a target name differs, update UPGRADE.md. Commit as a separate fix.

- [ ] **Step 4: Push feature branch**

```bash
cd /home/dylan/src/oe/patterns/aws-marketplace-utilities
git push -u origin feature/upgrade-workflow-doc
```

---

## Task 12: Open PR against utilities repo

**Files:**
- None (PR only)

- [ ] **Step 1: Open PR using gh**

```bash
cd /home/dylan/src/oe/patterns/aws-marketplace-utilities
gh pr create --base develop --title "Add UPGRADE.md — standardized upgrade workflow" --body "$(cat <<'EOF'
## Summary

- Adds `UPGRADE.md` documenting the end-to-end upstream-version upgrade workflow for any pattern repo using `common.mk`.
- Covers 6 phases: Research → Code → AMI → Test → Release → Publish, plus Prerequisites and Troubleshooting.
- No code changes — pure documentation.

## Test plan

- [ ] Review each phase against the Mastodon upgrade we just completed (4.5.1 → 4.5.9)
- [ ] Cross-reference all referenced `make` targets against `common.mk`
- [ ] Spot-check commands for syntax correctness
EOF
)"
```

- [ ] **Step 2: Note PR URL**

Report the returned PR URL for review.

---

## Task 13: Add pointer to Mastodon's CLAUDE.md

**Files:**
- Modify: `/home/dylan/src/oe/patterns/aws-marketplace-oe-patterns-mastodon/CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md to find insertion point**

```bash
grep -n 'Files to Update When Releasing\|Git Workflow\|## ' /home/dylan/src/oe/patterns/aws-marketplace-oe-patterns-mastodon/CLAUDE.md
```

- [ ] **Step 2: Add Upgrade Workflow section**

Add a new section near the top (after "Project Overview" and before "Development Environment"):

```markdown
## Upgrade Workflow

For upgrading the upstream Mastodon version, follow the process in [aws-marketplace-utilities/UPGRADE.md](https://github.com/ordinaryexperts/aws-marketplace-utilities/blob/main/UPGRADE.md).
```

- [ ] **Step 3: Commit on Mastodon repo**

Note: this commit goes on the Mastodon repo's current branch (`feature/upgrade`), since we are already mid-upgrade there.

```bash
cd /home/dylan/src/oe/patterns/aws-marketplace-oe-patterns-mastodon
git add CLAUDE.md
git commit -m "docs: reference shared UPGRADE.md from CLAUDE.md"
```

---

## Task 14: Plan rollout to remaining pattern repos (follow-up)

**Files:**
- None — deliverable is a tracking list

- [ ] **Step 1: List remaining repos needing the CLAUDE.md pointer**

```bash
gh repo list ordinaryexperts --limit 50 --json name --jq '.[] | select(.name | test("^aws-marketplace-oe-patterns-") and (test("cdk-common") | not)) | .name'
```

- [ ] **Step 2: Record the list in a follow-up GitHub issue**

Open an issue in `aws-marketplace-utilities` titled `Roll out UPGRADE.md pointer to all pattern repo CLAUDE.mds`, listing each repo as a checkbox. Each repo's update is a 1-line PR to its own CLAUDE.md and is not blocking.

---

## Review checklist

Before requesting plan review:
- [ ] Every `make` target referenced exists in `common.mk`
- [ ] Every file path is absolute when under `/home/dylan`, or relative-from-repo-root with repo name specified
- [ ] Git-flow commands are syntactically correct
- [ ] No implementation beyond markdown + CLAUDE.md pointer
