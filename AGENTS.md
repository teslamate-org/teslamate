# AGENTS.md

## Dependencies

Keep `elixir/mix.lock`, `elixir/assets/package-lock.json`, and `website/package-lock.json` identical to the upstream release the fork is built on. Do not update dependencies in the fork; they arrive with the next upstream release, which the `teslamate-fork-upgrade` skill brings in. A diverging lockfile conflicts on every upgrade and changes the pinned Nix hash.

Do not adopt a release until it has been public for the minimum age below, and do not bypass the cooldown (for example with `HEX_COOLDOWN=0d` or `--min-release-age=0`) unless the user explicitly asks for it.

| Ecosystem                          | Local setting                               | Dependabot `cooldown.default-days` |
| ---------------------------------- | ------------------------------------------- | ---------------------------------- |
| Hex                                | `hex: [cooldown: "4d"]` in `elixir/mix.exs` | 5                                  |
| npm (`elixir/assets/`, `website/`) | `min-release-age=4` in `.npmrc`             | 5                                  |

Dependabot counts whole days, so it uses 5 to keep at least 96 hours of release age. When changing a cooldown, update both columns together.

When the user explicitly asks for a fork-only fix ahead of upstream, run Mix from `elixir/` inside the devenv shell (`direnv exec .`), check that every changed version meets the cooldown, then run `nix run .#update-nix-hashes` and commit the hash in `nix/flake-modules/package.nix` together with the lockfile.
