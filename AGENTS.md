# AGENTS.md

## Updating Dependencies

Run Mix, Hex, and Nix commands inside the devenv shell. direnv loads it automatically from the repository root; from a non-interactive shell, prefix commands with `direnv exec .`. The Elixir application lives in `elixir/`, so run Mix commands from that directory (or set `MIX_EXS=elixir/mix.exs`) and Nix commands from the repository root.

### Release Age Cooldown

Do not adopt a release until it has been public for the minimum age below. Do not bypass the cooldown (for example with `HEX_COOLDOWN=0d` or `--min-release-age=0`) unless the user explicitly asks for it.

| Ecosystem                          | Local setting                               | Dependabot `cooldown.default-days` |
| ---------------------------------- | ------------------------------------------- | ---------------------------------- |
| Hex                                | `hex: [cooldown: "4d"]` in `elixir/mix.exs` | 5                                  |
| npm (`elixir/assets/`, `website/`) | `min-release-age=4` in `.npmrc`             | 5                                  |

Dependabot counts whole days, so it uses 5 to keep at least 96 hours of release age. When changing a cooldown, update both columns together.

The Hex cooldown only filters versions during resolution; versions already in `elixir/mix.lock` are trusted. Before committing an update, check that every version that changed in `elixir/mix.lock` meets the cooldown, for example with `curl -s https://hex.pm/api/packages/<name>/releases/<version> | jq -r .inserted_at`.

### Hex Packages

1. Find candidates with `mix hex.outdated --all`. `mix deps.get` lists packages with security advisories and links to the OSV entries.
2. Update with `mix deps.update <package>...`. When a fixed version is blocked by a requirement, run `mix hex.outdated <package>` to find the blocking dependency and update that one too.
3. Run `mix deps.unlock --unused` to drop transitive dependencies that are no longer needed.
4. Read the changelog in `elixir/deps/<package>/CHANGELOG.md` for every major version bump and check the affected call sites.
5. Verify with `mix compile` and `mix test`. The tests need the devenv Postgres: start it with `devenv up --detached` and stop it with `process-compose down` afterwards.
6. Run `nix run .#update-nix-hashes` and commit the updated hash in `nix/flake-modules/package.nix` together with `elixir/mix.lock`. The `Verify the pinned hashes` CI job fails when this hash is stale. The workflow pushes the fix itself only on Dependabot pull requests.

When an advisory has no fixed release, check whether TeslaMate uses the affected code path and record the result in the pull request description.

### npm Packages

`elixir/assets/` and `website/` are separate npm projects with their own `package-lock.json`. Run `npm install` or `npm update` inside the directory. `elixir/assets/package.json` links `phoenix`, `phoenix_html`, and `phoenix_live_view` to `../deps/*`, so run `mix deps.get` first; these three follow the Hex versions and are excluded from Dependabot.

### Nix Flake Inputs

`flake.lock` is updated weekly by the `update-flake-lock` workflow. To update it by hand, run `nix flake update` and then `nix run .#update-nix-hashes`.

### Commits

Use `fix(deps):` when an update addresses a security advisory or bug, and `build(deps):` for routine version bumps, matching the Dependabot commits. Use `build(nix):` for a hash-only follow-up commit.
