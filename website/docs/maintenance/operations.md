---
title: Operations and diagnostics
sidebar_label: Operations and diagnostics
---

The **Maintenance** page combines build identity, runtime connection health and a read-only data-health report. This overview is available without enabling any maintenance feature.

Two sensitive capabilities can be enabled separately:

- a bounded, redacted view of recent TeslaMate file logs
- confirmation-only close actions for long-running open drives and charging sessions

Both capabilities are disabled by default. Enabling either one protects the Maintenance page with HTTP Basic Auth and requires these variables:

```yml
environment:
  - TESLAMATE_OPERATIONS_USERNAME=operator
  - TESLAMATE_OPERATIONS_PASSWORD=replace-with-a-long-random-password
```

Basic Auth credentials are only encoded, not encrypted. Use this page only through HTTPS, a VPN or another encrypted connection. These credentials protect the Maintenance page, not the rest of the TeslaMate interface. Continue to secure the whole deployment with the network or reverse-proxy controls described in the [Docker installation guide](../installation/docker).

## Recent logs

Enable bounded rotating file logs with:

```yml
environment:
  - TESLAMATE_FILE_LOGGING_ENABLED=true
```

TeslaMate writes at most 5 MB to the active file and keeps three compressed rotated files. The Maintenance page reads at most the newest 256 KB or 500 lines from the active file. Known credential shapes are redacted before file persistence and again before display, but logs can still contain operational data. Review them before sharing.

The default path is `data/logs/teslamate.log`. To keep logs across container replacement, add a volume:

```yml
services:
  teslamate:
    volumes:
      - teslamate-logs:/opt/app/data/logs

volumes:
  teslamate-logs:
```

Use `TESLAMATE_FILE_LOGGING_PATH` to select another path.

## Close actions

Enable close actions with:

```yml
environment:
  - TESLAMATE_MAINTENANCE_ACTIONS_ENABLED=true
```

The page only offers an action for drives and charging sessions that are still open more than 48 hours after their start time. Selecting **Close session** opens a confirmation dialog. At confirmation time TeslaMate locks and rechecks the exact database record, then refuses the action if the record is no longer open, is too recent, the vehicle is currently in the matching active state or its activity cannot be confirmed.

The action uses TeslaMate's existing completion logic. It never deletes a record. A drive without enough position data to calculate a valid end state is left unchanged for manual review.

Back up the database before enabling maintenance actions. For cases that cannot be closed safely, use the [manual maintenance guide](./manually_fixing_data).
