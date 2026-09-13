# Fork delta discovery guide

Use this reference to classify the fork at runtime. Do not store mutable branch heads, commit SHAs, deployed image digests, production inventory names, or incident notes in this public file.

## Sources of authority

- Read the latest stable release from the upstream GitHub Releases API.
- Fetch upstream tags and resolve the selected tag to an exact commit.
- Read fork-only commits from `upstream/main..origin/main` after refreshing both remotes.
- Read deployed image refs from the deployment role at runtime.
- Treat local paths and deployment targets as environment-provided values.

## Delta inventory

For every non-merge fork commit, record the following in the private upgrade report rather than this repository:

| Field             | Required evidence                                            |
| ----------------- | ------------------------------------------------------------ |
| Identity          | Fork commit, subject, and upstream PR when one exists        |
| Patch equivalence | Stable patch ID and durable file signatures                  |
| Release inclusion | Ancestry and content checks against the selected release tag |
| Decision          | Keep, drop, or rework                                        |
| Validation        | Focused test, performance check, and production behavior     |

A merged upstream PR is not enough to drop a fork delta. Confirm that the selected release tag contains the behavior. Conversely, do not retain or cherry-pick a patch when equivalent behavior is already in the release under another commit.

## Durable signature examples

Prefer behavior-oriented signatures that survive rebases and squashes:

- schema columns, defaults, and migration behavior
- UI controls and translated labels
- dashboard query predicates and query-plan shape
- interval-boundary and NULL-handling expressions
- characterization tests and expected result shapes

Do not rely on commit subjects alone.

## Deployment contract

Confirm at runtime that the role:

1. Pre-pulls both immutable images before changing Compose configuration.
2. Skips pre-pull in check mode.
3. Updates containers with `pull: never` after the managed Compose block.
4. Removes legacy assets only after a successful container update.
5. Has no obsolete dashboard bind mounts or runtime patchers.
6. Produces `changed=0` on the final idempotency run.

## Maintenance boundaries

Keep unrelated flaky tests, dependency advisories, registry cleanup, and infrastructure maintenance outside the release-upgrade branch unless they block the upgrade and receive separate approval.
