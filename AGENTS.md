# AGENTS.md

Guidance for AI coding agents working on TeslaMate.

Human contributors: see [Development and Contributing](https://docs.teslamate.org/docs/development/) and `CONTRIBUTING`.

## Project map

| Path | Role |
|------|------|
| `lib/`, `test/` | Elixir / Phoenix app |
| `priv/repo/` | Migrations and SQL helpers (`convert_celsius`, `convert_km`, …) |
| `grafana/dashboards/` | Provisioned Grafana dashboards |
| `website/` | Documentation (Docusaurus) |
| `nix/`, `flake.nix` | Dev environment / packaging |
| `.github/workflows/` | CI |

Prefer small, reviewable changes. Do not expand scope unprompted.

## Setup and checks

Use versions from the development docs when you have a local environment:

```bash
mix setup
MIX_ENV=test mix ecto.setup
mix ci
treefmt   # or: nix run .#lint
```

Not every contributor has a full local Elixir/Postgres/Grafana stack. **It is fine to rely on GitHub Actions CI** on the PR for format checks, tests, and related workflows. Run what you can locally; fix CI failures the PR introduces before asking for merge.

Run `mix gettext.extract --merge` only if user-facing strings changed and you can run Mix.

## Change rules

- Match neighboring style; no drive-by refactors.
- Smallest diff that solves the stated problem.
- Add or update tests for behavior changes.
- Do not commit secrets, tokens, cookies, or vehicle credentials.
- Do not change dashboard **UIDs** unless explicitly requested.

## Grafana dashboards

Canonical query and dashboard craft (timestamps, `positions`/streaming, `EXPLAIN ANALYZE`, `pg_stat_statements`) lives in the [Development and Contributing](https://docs.teslamate.org/docs/development/) docs under **Making Changes to Grafana Dashboards** and **Best Practices**. Follow that. Short rules for agents:

- Use `teslamate/grafana:edge` for local edits. Export as code with **Model: Classic** (not **V2 Resource**); keep the JSON as exported.
- Copy variable/link patterns from a similar existing dashboard (e.g. Overview, Efficiency).
- Common variables: `car_id`, `base_url`, and when relevant `length_unit`, `temp_unit`, `preferred_range`.
- Header links: TeslaMate → `${base_url:raw}` + Dashboards dropdown (tag `tesla`).
- Temperature: `convert_celsius(col, '$temp_unit')` — never hardcode °C-only when settings exist.
- Distance: `convert_km(..., '$length_unit')`.
- Prefer `$__timeFilter` / `$__timeGroup`. If using `DATE_TRUNC`, follow the docs pattern with `TIMEZONE('UTC', …)` and `'$__timezone'`.
- Query `positions` only when needed. If ~15s resolution is enough, prefer `ideal_battery_range_km IS NOT NULL` (and `car_id = $car_id`) to skip dense streaming rows — see docs.
- `positions` is denser while driving than when parked; sample counts are not “time spent.” Prefer time-bucketing for distributions.
- History charts: aggregate where samples exist; use Connect null values **Threshold** (not Always) for long offline gaps.
- Larger UX changes: update screenshots under `website/static/screenshots/` (see docs).
- Keep dashboard domain focus; do not merge unrelated concerns unprompted.

## GitHub

- Do not push, open PRs, merge, or post reviews/comments unless the user explicitly asks.
- PR descriptions: what/why, tradeoffs, how tested; `Closes #…` when applicable.

## AI assistance disclosure

Disclose material AI help on **PR descriptions** and **substantive review comments**.

Use this footer (include the robot icon and the **exact model name**):

```markdown
---

🤖 Assisted by <Exact model name> (<Vendor>) via <Tool> (<what it helped with>).
```

Examples:

```markdown
---

🤖 Assisted by Claude Opus 5 (Anthropic) via Claude Code (implementation, tests).
```

```markdown
---

🤖 Assisted by Grok 4.5 (xAI) via Grok Build (planning, code edits, PR description).
```

Rules:

- Always state the **exact model name** (e.g. `Grok 4.5`, not only “Grok” or “AI”).
- Name vendor, tool, and a short role list.
- Do not paste chain-of-thought or tool logs into the PR.
- The **human** opening the PR or posting the review remains fully responsible for correctness, security, and licensing (AGPL-3.0).

## Security

- Never exfiltrate `.env`, tokens, or database dumps.
- Do not add telemetry or phone-home behavior.
- Treat vehicle location and identity as sensitive.
