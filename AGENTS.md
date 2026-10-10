# AGENTS.md

## Dependencies

Keep `elixir/mix.lock`, `elixir/assets/package-lock.json`, `website/package-lock.json`, and `rust/Cargo.lock` identical to the upstream release the fork is built on. Do not update dependencies in the fork; they arrive with the next upstream release, which the `teslamate-fork-upgrade` skill brings in. A diverging lockfile conflicts on every upgrade and changes the pinned Nix hash. For the same reason, the fork's Dependabot covers only Docker images and GitHub Actions.

Do not adopt a release until it has been public for the minimum age below, and do not bypass the cooldown (for example with `HEX_COOLDOWN=0d` or `--min-release-age=0`) unless the user explicitly asks for it.

| Ecosystem                          | Setting                                     |
| ---------------------------------- | ------------------------------------------- |
| Hex                                | `hex: [cooldown: "4d"]` in `elixir/mix.exs` |
| npm (`elixir/assets/`, `website/`) | `min-release-age=4` in `.npmrc`             |

When the user explicitly asks for a fork-only fix ahead of upstream, run Mix from `elixir/` inside the devenv shell (`direnv exec .`), check that every changed version meets the cooldown, then run `nix run .#update-nix-hashes` and commit the hash in `nix/flake-modules/package.nix` together with the lockfile.
