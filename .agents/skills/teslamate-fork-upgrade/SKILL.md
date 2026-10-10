---
name: teslamate-fork-upgrade
description: Use when upstream teslamate-org/teslamate publishes a new stable release and the deployed rewse/teslamate fork must move to it, or when asked to sync, rebase, or bump the fork, decide which fork patches upstream already ships, rebuild the rewse GHCR TeslaMate and Grafana images, or roll a new fork build out through the ansible-playbooks TeslaMate role. Not for an isolated dashboard or application fix without a version upgrade.
compatibility: Requires git, gh, Python 3, Nix with direnv/devenv, curl, jq, Ansible, 1Password CLI, and access to rewse/teslamate, teslamate-org/teslamate, rewse/ansible-playbooks, GHCR, and the deployment host.
---

# TeslaMate Fork Upgrade

Move the rewse fork to a new upstream release without duplicating fixes upstream already ships, losing rewse-only behavior, publishing an unreviewed image, or changing production before rollback evidence exists.

## Environment

Take every location from the environment; never persist workstation paths, inventory names, or hostnames in this skill or in reports.

| Variable                    | Meaning                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| `TESLAMATE_REPO`            | local `rewse/teslamate` checkout (`origin` = fork, `upstream` = teslamate-org) |
| `ANSIBLE_PLAYBOOKS_REPO`    | local deployment repository checkout                                           |
| `TESLAMATE_DEPLOY_PLAYBOOK` | playbook that includes the `teslamate` role                                    |
| `SKILL_DIR`                 | `$TESLAMATE_REPO/.agents/skills/teslamate-fork-upgrade`                        |

Never work in a dirty checkout. Preserve unrelated user edits; create isolated worktrees instead of stashing, resetting, or cleaning.

The Elixir application lives in `elixir/`: run Mix from there, and Nix, lint, and git from the repository root. Each new worktree needs `direnv allow` before `direnv exec . …` works.

## 1. Read-only inventory

```bash
git -C "$TESLAMATE_REPO" fetch upstream --tags
git -C "$TESLAMATE_REPO" fetch origin
python3 "$SKILL_DIR/scripts/inspect_upgrade_state.py" --target-tag "$TARGET_TAG" --strict
```

The script reports the target tag object, commit, and signature state; the live fork deltas (`custom_non_merge_commits`, already excluding history superseded by a previous upgrade's `-s ours` merge); and the Ansible deployment contract. Exit code 2 means warnings: resolve each one or present it to the user before mutating anything. Read `references/current-deltas.md` for how to classify deltas.

## 2. Choose and trust the target

Default to the newest stable release (`gh release view --repo teslamate-org/teslamate`), never `upstream/main`, a prerelease, or a mutable image tag, unless the user explicitly asks for an unreleased build.

Upstream release tags are annotated but unsigned, so `git verify-tag` fails. Do not hide that. Propose this alternate trust basis and wait for explicit approval: pin the tag object and the commit it points to, and confirm the commit's GitHub verification:

```bash
gh api "repos/teslamate-org/teslamate/commits/$TARGET_COMMIT" --jq .commit.verification
```

Before branching, re-check that `git rev-parse "$TARGET_TAG"` and `"$TARGET_TAG^{commit}"` still equal the pinned values.

Read the release notes, `CHANGELOG.md`, `website/docs/upgrading.mdx`, migrations added since the deployed base, and Docker, Grafana, Erlang, Elixir, and PostgreSQL version changes. Compare runtime configuration changes (`elixir/config/runtime.exs`, `entrypoint.sh`) against the deployment's environment template.

## 3. Classify every fork delta

Build this table before creating the upgrade branch:

| Delta                 | Evidence                                   | In target tag? | Action           | Validation   |
| --------------------- | ------------------------------------------ | -------------: | ---------------- | ------------ |
| commit or upstream PR | PR state, ancestry, patch-id, file content |         yes/no | drop/keep/rework | focused test |

A merged upstream PR is removable only when its merge commit is an ancestor of the target tag (`git merge-base --is-ancestor`). Patch IDs differ when upstream rewrites the patch, so compare the resulting behavior: extract dashboard SQL with `jq -r '..|.rawSql? // empty'` and diff it, and treat a difference as harmless only when you can state why the results match. If no custom delta remains, ask whether to return to official images; do not silently change image provenance.

## 4. Build the candidate

```bash
git -C "$TESLAMATE_REPO" worktree add -b "upgrade/teslamate-${TARGET_TAG#v}" "$UPGRADE_WORKTREE" "$TARGET_COMMIT"
```

Cherry-pick the kept deltas with `-x`, oldest first. Never merge old fork `main` into the release tag with a content merge; it resurrects files at superseded paths and reapplies dropped patches.

Resolve conflicts by kind:

| Conflict                                                           | Resolution                                                                                                                                                                           |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CONFLICT (file location)` after an upstream directory move        | `git add` the file at the suggested new path, after confirming its content is unchanged                                                                                              |
| Relative paths in moved tests (`Path.expand("../…", __DIR__)`)     | keep upstream's depth and the fork's additions                                                                                                                                       |
| gettext `.po`/`.pot`                                               | do not union-merge (it drops shared `msgstr` lines and breaks parsing). Rebuild each catalog as the target tag's file plus the fork-only entries, then `mix gettext.extract --merge` |
| characterization goldens for scenarios new in the target           | `CHARACTERIZATION_RECORD=only:<name> mix test test/teslamate/characterization_test.exs`, then `nix run .#lint` to restore formatting; the diff must contain only the fork's fields   |
| config files that moved (`elixir/mix.exs`, `elixir/assets/.npmrc`) | keep upstream's new keys and the fork's settings; fix path references in `AGENTS.md` and Dependabot comments                                                                         |

Fold conflict fixes into the commit that caused them (`git commit --fixup` plus `git rebase -i --autosquash "$TARGET_COMMIT"` with `GIT_SEQUENCE_EDITOR=true`).

Finally record the fork history so the PR fast-forwards `main` without changing the tree:

```bash
tree=$(git rev-parse HEAD^{tree})
git merge -s ours origin/main -m "Merge rewse/teslamate main into the ${TARGET_TAG} upgrade"
test "$(git rev-parse HEAD^{tree})" = "$tree"
```

## 5. Local quality gates

Start the test database with `direnv exec . devenv up --detached`; stop it with `direnv exec . process-compose down` when done.

```bash
(cd elixir && direnv exec .. mix gettext.extract --check-up-to-date)
(cd elixir && direnv exec .. sh -c 'MIX_ENV=test mix ci')
nix run .#lint                      # must report 0 files changed
nix run .#update-nix-hashes         # commit any changed hash
for f in locations trip visited internal/drive-details vampire-drain; do python3 -m json.tool "grafana/dashboards/$f.json" >/dev/null; done
git diff --check "$TARGET_COMMIT...HEAD"
git range-diff "$TARGET_COMMIT...origin/main" "$TARGET_COMMIT...HEAD"
```

If a fork delta's dashboard filter predicates changed, compare result shape and `EXPLAIN (ANALYZE, BUFFERS)` in read-only transactions with anonymized parameters. Do not weaken a performance threshold to pass. Do not proceed with uncommitted formatting, stale POT files, failing goldens, or new warnings.

## 6. Approval gate: publish

Present the target pin, delta table, commit list, local results, current production refs for rollback, and the exact external writes. Wait for explicit approval.

- Push the branch. If HTTPS is rejected for missing `workflow` scope, push over SSH to the same repository (`git push git@github.com:rewse/teslamate.git <branch>`) without changing git config.
- Open a fork-internal PR to `rewse/teslamate:main`; never push to `main` directly.
- PRs and pushes that touch `.github/` skip almost every job by design. Dispatch `devops.yml` and `update-nix-hashes.yml` on the branch with `gh workflow run --ref`, and require them to pass before merging.
- After merge, the push to `main` skips the image build for the same reason. Dispatch `ghcr_build.yml` on `main`.

## 7. Verify GHCR artifacts

```bash
bash "$SKILL_DIR/scripts/inspect_ghcr_images.sh" main
```

Both images must resolve anonymously (proving they are public), list `linux/amd64`, and carry `org.opencontainers.image.revision` equal to the merged `main` commit. Do not change package visibility, add `write:packages` scope, or delete versions without separate approval.

## 8. Deploy

The `teslamate` role resolves both images at run time from `ghcr.io/rewse/teslamate{,/grafana}:main` (`aged_release`, no cooldown), pre-pulls them by digest, skips the pre-pull and Compose update in check mode, then updates `/etc/compose/teslamate` with `pull: never`. No role variable needs editing: the run after the image build deploys app and Grafana together in one stage. The inspector's `contract` block confirms this shape; stop and ask if it reports a mismatch.

Before the first production command, record the running refs for rollback:

```bash
direnv exec . ansible <host-group> -b -m ansible.builtin.shell -a \
  'docker inspect --format "{{ "{{" }}.Name{{ "}}" }} {{ "{{" }}.Config.Image{{ "}}" }}" $(docker ps -q --filter label=com.docker.compose.project=teslamate)'
```

Then, each step with its own approval:

1. `direnv exec . ansible-playbook "$TESLAMATE_DEPLOY_PLAYBOOK" --tags teslamate --check --diff`; judge by exit code, show the non-secret diff.
2. Apply the same command without `--check`, exactly once.
3. Verify (section 9), then rerun once and require `changed=0`.

When a 1Password lookup fails, verify a real Secret Reference with `direnv exec . op read …`; never infer access from `op whoami`.

## 9. Production validation

- running app and Grafana refs equal the verified digests; restart counts stable
- TeslaMate `/health_check` and Grafana `/api/health`
- migrations and startup logs free of errors
- a fresh browser load of the UI, not a long-lived LiveView tab
- rewse-specific dashboards and controls, checked over fixed historical intervals; restore any temporary setting afterwards
- no new SQL or provisioning errors in Grafana

Never persist addresses, coordinates, identifiers, real timestamps, credentials, query parameters, or screenshots in reports.

## Rollback

Keep the recorded refs until validation completes. For an immediate rollback, override the resolved facts (extra vars outrank `set_fact`), check first, then apply:

```bash
direnv exec . ansible-playbook "$TESLAMATE_DEPLOY_PLAYBOOK" --tags teslamate --check --diff \
  -e '{"__teslamate_image": {"ref": "<previous app ref>"}, "__teslamate_grafana_image": {"ref": "<previous grafana ref>"}}'
```

The next normal run redeploys `main`, so make the rollback durable by reverting the fork `main` through a reviewed PR and rebuilding the images. Leave forward-compatible added columns in place, and never delete location history or rows as rollback.

## Report

Lead with the result and the deployed refs, then cover: target release and trust basis, delta classification, candidate commits, local validation, PR and GHCR artifacts, rollout, functional validation, rollback status, deferred maintenance, and every external action with its approval. List each ruling on ambiguous behavior and its cost if wrong.
