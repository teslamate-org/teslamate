---
name: teslamate-fork-upgrade
description: Safely upgrade the deployed rewse/teslamate fork when teslamate-org publishes a new stable version or when asked to sync, rebase, or update the fork. Use this skill whenever a user mentions a new TeslaMate release, upgrading the rewse TeslaMate deployment, syncing upstream, rebasing the fork, checking whether custom PRs are included upstream, rebuilding GHCR TeslaMate/Grafana images, refreshing immutable image digests, or rolling the upgrade through the ansible-playbooks TeslaMate role, even if they only ask to “bump TeslaMate.” Do not use for an isolated dashboard or application bug fix unrelated to an upstream version upgrade.
compatibility: Requires git, gh, Python 3, Nix, skopeo, Ansible, 1Password CLI, agent-browser, and access to rewse/teslamate, teslamate-org/teslamate, rewse/ansible-playbooks, GHCR, and the deployment host.
---

# TeslaMate Fork Upgrade

Safely move the deployed rewse fork to a new upstream TeslaMate release without duplicating fixes already released, losing rewse-only behavior, publishing unreviewed images, or changing production before rollback evidence exists.

## Default repositories and deployment

Set repository and deployment locations explicitly; do not encode workstation paths or production inventory names in the skill:

- `TESLAMATE_REPO`: local `rewse/teslamate` checkout
- `ANSIBLE_PLAYBOOKS_REPO`: local deployment repository checkout
- `TESLAMATE_DEPLOY_PLAYBOOK`: deployment playbook path
- `TESLAMATE_DEPLOY_LIMIT`: Ansible inventory limit
- skill root: `$TESLAMATE_REPO/.kiro/skills/teslamate-fork-upgrade`
- upstream: `teslamate-org/teslamate`
- fork: `rewse/teslamate`
- deployment role: `roles/teslamate`

Never work in a dirty checkout. Preserve unrelated user edits and create isolated worktrees instead of stashing, resetting, or cleaning them.

## Start with a read-only inventory

Resolve this skill directory, then run:

```bash
: "${TESLAMATE_REPO:?Set TESLAMATE_REPO}"
: "${ANSIBLE_PLAYBOOKS_REPO:?Set ANSIBLE_PLAYBOOKS_REPO}"
SKILL_DIR="$TESLAMATE_REPO/.kiro/skills/teslamate-fork-upgrade"
python3 "$SKILL_DIR/scripts/inspect_upgrade_state.py" --strict
```

If the default paths do not apply:

```bash
SKILL_DIR="$TESLAMATE_REPO/.kiro/skills/teslamate-fork-upgrade"
python3 "$SKILL_DIR/scripts/inspect_upgrade_state.py" \
  --teslamate-repo "$TESLAMATE_REPO" \
  --ansible-repo "$ANSIBLE_PLAYBOOKS_REPO" \
  --strict
```

Read `references/current-deltas.md` after the script. That file is a snapshot, not authority; refresh every PR state, tag, commit ancestry, and file signature before deciding what remains custom.

Stop before mutation when either repository is dirty, required remotes are missing, production image refs cannot be parsed, or the requested target is ambiguous.

## Choose the upgrade target

Default to the newest stable upstream release, not `upstream/main`, a prerelease, or a mutable image tag. Use edge/main only when the user explicitly requests an unreleased build.

```bash
gh release view --repo teslamate-org/teslamate \
  --json tagName,name,publishedAt,isPrerelease,isDraft,url
git -C "$TESLAMATE_REPO" fetch upstream --tags
git -C "$TESLAMATE_REPO" verify-tag "$TARGET_TAG"
git -C "$TESLAMATE_REPO" show "$TARGET_TAG:VERSION"
```

Read the release notes, `CHANGELOG.md`, `website/docs/upgrading.mdx`, migration files added since the deployed base, Docker/Grafana changes, and the supported Erlang, Elixir, PostgreSQL, Grafana, and Node versions.

Record the exact target tag, commit, and verified signer. If upstream does not publish a verifiable signed tag, stop and request explicit approval for an alternate trust basis that pins the fetched upstream release ref and exact commit; never hide tag-verification failure.

## Classify every fork delta

Build a table before creating an upgrade branch:

| Delta | Current evidence | Included in target tag? | Action | Validation |
|---|---|---:|---|---|
| Upstream PR or rewse commit | PR, patch-id, file signature | yes/no | drop/keep/rework | focused test |

Use all available evidence:

1. Refresh PR state with `gh pr view`.
2. Check whether the PR merge commit is an ancestor of the target tag.
3. Compare stable patch IDs when upstream rebased or squashed the change.
4. Inspect target-tag file content for durable signatures.
5. Confirm the release tag, not merely upstream `main`, contains the behavior.

A merged PR is not removable from the fork until the selected release tag contains it. A matching commit message is not proof. Do not cherry-pick a patch whose behavior is already present under another commit.

If no custom delta remains, stop and ask whether to return to official images or keep the rewse build pipeline. Do not silently change image provenance.

## Build the candidate in an isolated worktree

Create an upgrade branch from the exact upstream release tag:

```bash
git -C "$TESLAMATE_REPO" worktree add \
  -b "upgrade/teslamate-${TARGET_TAG#v}" \
  "$UPGRADE_WORKTREE" \
  "$TARGET_TAG"
```

Apply only deltas classified as still required. Prefer clean cherry-picks of reviewed commits. When commit topology changed, use stable patch IDs and a minimal manual port with tests. Never merge the old fork `main` wholesale into the release tag; that can reintroduce the previous upstream base and already-released patches.

After applying deltas:

```bash
git -C "$UPGRADE_WORKTREE" range-diff "$TARGET_TAG...origin/main" "$TARGET_TAG...HEAD"
git -C "$UPGRADE_WORKTREE" diff --check "$TARGET_TAG...HEAD"
```

Document every dropped, retained, and reworked delta. If a migration or schema changed, verify upgrade and rollback compatibility before building images.

## Run local quality gates

Use the versions and commands documented by the target release. At minimum run:

```bash
(
  cd "$UPGRADE_WORKTREE"
  mix gettext.extract --check-up-to-date
  MIX_ENV=test mix ci
  nix run .#lint
  python3 -m json.tool grafana/dashboards/locations.json >/dev/null
  python3 -m json.tool grafana/dashboards/trip.json >/dev/null
  python3 -m json.tool grafana/dashboards/visited.json >/dev/null
  python3 -m json.tool grafana/dashboards/internal/drive-details.json >/dev/null
  git diff --check "$TARGET_TAG...HEAD"
)
```

Run focused tests for every retained rewse delta. If dashboard SQL changed, compare result shape and `EXPLAIN (ANALYZE, BUFFERS)` using read-only transactions and anonymized parameters. Do not weaken an existing performance threshold to make the upgrade pass.

Do not proceed with uncommitted formatting changes, skipped migrations, failing characterization goldens, stale POT files, or unexplained warnings introduced by the candidate.

## Approval gate: publish the candidate

Before any push, PR creation, merge, package visibility change, or tag deletion, present:

- target release tag and commit
- delta classification table
- candidate commit list and diff scope
- local test and performance results
- rollback plan
- exact external writes requested

Wait for explicit approval.

Push an upgrade branch, then integrate through a Fork-internal PR into `rewse/teslamate:main`. Do not push directly to main unless the user explicitly authorizes that exact action. Preserve hooks and wait for all required checks before merge.

## Verify GHCR artifacts

The Fork main workflow must build both images from the same main commit:

- `ghcr.io/rewse/teslamate:main`
- `ghcr.io/rewse/teslamate/grafana:main`

Verify:

1. main workflow conclusion is success.
2. Linux amd64 exists in both manifests.
3. Packages are public unless a separately approved pull-credential design exists.
4. Anonymous manifest and digest-only inspection succeed.
5. Raw manifest digests match the refs recorded for Ansible.

Use digest-pinned refs; never deploy a mutable tag by itself. Do not add standing `write:packages` scope when the required package state is already satisfied. Do not delete stale versions or cache tags without separate approval.

## Update Ansible fail-closed

Use an isolated Ansible worktree and preserve unrelated work. Update only the two role vars after artifact verification:

- `teslamate_image_ref`
- `teslamate_grafana_image_ref`

Keep deployment ordering fail-closed:

1. Pre-pull both digest-pinned images.
2. Skip pre-pull in check mode.
3. Update the managed Compose block only after both pulls succeed.
4. Run Compose with `pull: never` so it cannot fail on a second registry request after changing the file.
5. Remove legacy assets only after successful container update.

Run the deployment-order unit test, template render, syntax check, `ansible-lint`, and `git diff --check`.

## Choose staged rollout based on risk

Use two stages when the release changes TeslaMate application code, migrations, runtime configuration, or shared database contracts:

1. Deploy the app image while retaining the last known-good Grafana image and overrides.
2. Verify migration, app health, settings/UI, and logs.
3. Deploy the Grafana image and remove obsolete overrides only after the app stage passes.

A dashboard-only update may use one Compose change after both images are pre-pulled, but explain why application staging is unnecessary. Prefer the safer two-stage path when uncertain.

For each production stage:

1. Ask approval for check mode and show the resolved `$TESLAMATE_DEPLOY_PLAYBOOK` and `$TESLAMATE_DEPLOY_LIMIT` without persisting their values.
2. Run check mode and judge success by process exit code, not recap alone.
3. Show the exact non-secret diff.
4. Ask separate approval for apply.
5. Apply exactly once.
6. Verify image ref, health, migration/log state, and expected mounts.
7. Stop before the next stage on any load-bearing failure.

When 1Password access fails, verify a real Secret Reference through the same `direnv exec` environment. Retry the approval flow after independent work is exhausted. Never infer secret access from `op whoami`.

## Production validation

Always verify:

- exact app and Grafana refs and restart counts
- TeslaMate `/health_check` on the published host port
- Grafana `/api/health`
- migrations and startup logs
- fresh browser UI, not a long-lived disconnected LiveView DOM
- rewse-specific dashboards and controls
- no new SQL/provisioning errors
- expected mounts and legacy-file cleanup
- one final Playbook run with `changed=0`

For privacy or filtering behavior, use fixed historical intervals and restore any temporary setting in a finally-style flow. Never persist production addresses, coordinates, identifiers, actual timestamps, credentials, raw query parameters, screenshots, or plans in reports.

If the new upstream release absorbed a rewse delta, verify the released implementation in production before removing the local test, migration compatibility handling, or rollback notes that protect it.

## Rollback

Keep the previous two immutable refs and the Ansible commit that used them until validation completes. On failure:

- restore the previous refs through a reviewed Ansible commit
- run check mode before apply
- leave forward-compatible added columns in place when the previous app safely ignores them
- never delete location history or database rows as rollback
- do not clean old dashboard assets until the new container is running

A failed pre-pull must leave Compose, running containers, and rollback assets unchanged.

## Report format

Return a report with these sections:

```markdown
# TeslaMate Fork Upgrade Report

## Target release
## Fork delta classification
## Candidate branch and commits
## Local validation
## Fork PR and GHCR artifacts
## Ansible changes
## Production rollout
## Functional and performance validation
## Rollback status
## Deferred maintenance
## External actions and approvals
```

Lead with the result and current deployed refs. List every ruling made on ambiguous upgrade behavior and its cost if wrong.
