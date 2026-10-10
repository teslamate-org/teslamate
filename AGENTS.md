# AGENTS.md

## Dependencies

Keep `elixir/mix.lock`, `elixir/assets/package-lock.json`, `website/package-lock.json`, and `rust/Cargo.lock` identical to the upstream release the fork is built on. Do not update dependencies in the fork; they arrive with the next upstream release, which the `teslamate-fork-upgrade` skill brings in. A diverging lockfile conflicts on every upgrade and changes the pinned Nix hash. For the same reason, the fork's Dependabot covers only Docker images and GitHub Actions.

Do not adopt a release until it has been public for the minimum age below, and do not bypass the cooldown (for example with `HEX_COOLDOWN=0d` or `--min-release-age=0`) unless the user explicitly asks for it.

| Ecosystem                          | Setting                                     |
| ---------------------------------- | ------------------------------------------- |
| Hex                                | `hex: [cooldown: "4d"]` in `elixir/mix.exs` |
| npm (`elixir/assets/`, `website/`) | `min-release-age=4` in `.npmrc`             |

When the user explicitly asks for a fork-only fix ahead of upstream, run Mix from `elixir/` inside the devenv shell (`direnv exec .`), check that every changed version meets the cooldown, then run `nix run .#update-nix-hashes` and commit the hash in `nix/flake-modules/package.nix` together with the lockfile.

## Production Data Access

To read production data, load the global `teslamate` skill and follow it; it covers access, the read-only guarantees, and the schema. Change production dashboards through this repository, a new image, and the Ansible deployment, never through the Grafana API.

Use it to check a dashboard query against real data, compare result shapes before and after a change, measure plans with `EXPLAIN (ANALYZE, BUFFERS)`, and compare a deployed dashboard with `grafana/dashboards/`.

For a one-off data fix the user requests, connect to the production Aurora database with `psql` as the TeslaMate owner role. The 1Password item `op://ansible/f6jqsrpzvfqjxge4ntvalkwbte` holds the database, username, and password; pass them through environment variables so they never appear in output, and verify the server against the RDS CA bundle:

```sh
ca=$(mktemp)
curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o "$ca"
PGHOST=rewse-pg.cluster-c8xun5aepybs.ap-northeast-1.rds.amazonaws.com PGPORT=5432 \
  PGDATABASE="$(op read 'op://ansible/f6jqsrpzvfqjxge4ntvalkwbte/database')" \
  PGUSER="$(op read 'op://ansible/f6jqsrpzvfqjxge4ntvalkwbte/username')" \
  PGPASSWORD="$(op read 'op://ansible/f6jqsrpzvfqjxge4ntvalkwbte/password')" \
  PGSSLMODE=verify-full PGSSLROOTCERT="$ca" \
  psql -X -v ON_ERROR_STOP=1 -c "<SQL>"
command rm -f "$ca"
```

Confirm the statement with the user first, narrow the `WHERE` clause so a repeated run changes nothing, and use `RETURNING` to show the affected rows. TeslaMate refreshes some columns from the Tesla API, such as `cars.name` from `display_name` at startup, so a direct write to them lasts only until the next refresh.

Do not put production data in commits, pull requests, issues, or reports: no addresses, coordinates, geofence names, identifiers, or actual timestamps. Report aggregates, row counts, and plan shapes, and use anonymized parameters in any query you share.
