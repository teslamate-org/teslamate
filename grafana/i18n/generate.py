#!/usr/bin/env python3

import argparse
import copy
import json
import re
from pathlib import Path

# Grafana keys whose string values are directly visible to dashboard users.
LOCALIZABLE_KEYS = {
    "title",
    "description",
    "label",
    "displayName",
    "legendFormat",
    "tooltip",
    "noValue",
    "text",
    "alias",
}

# Maps where values are display labels but keys must keep matching the query field.
LOCALIZABLE_VALUE_MAPS = {"renameByName"}
# Maps where both key and value can reference the visible series name.
LOCALIZABLE_KEY_VALUE_MAPS = {"aliasColors"}

SQL_ALIAS_RE = re.compile(r"(?i)(\bAS\s+)([\"'])([^\"']+)(\2)")


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def localized_uid(uid: str, locale: str) -> str:
    return f"{uid}-{locale}"


def translate_exact(value: str, strings: dict[str, str], passthrough: set[str]) -> str:
    if value in strings:
        return strings[value]
    if value in passthrough:
        return value
    return value


def rewrite_sql_aliases(value: str, strings: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        source = match.group(3)
        target = strings.get(source, source)
        return f"{match.group(1)}{match.group(2)}{target}{match.group(4)}"

    return SQL_ALIAS_RE.sub(replace, value)


def rewrite_string(
    value: str,
    strings: dict[str, str],
    passthrough: set[str],
    uid_map: dict[str, str],
    *,
    sql_aliases: bool = False,
) -> str:
    value = translate_exact(value, strings, passthrough)
    if sql_aliases:
        value = rewrite_sql_aliases(value, strings)
    for source_uid, target_uid in uid_map.items():
        value = value.replace(source_uid, target_uid)
    return value


def rewrite(
    value,
    locale: str,
    strings: dict[str, str],
    passthrough: set[str],
    uid_map: dict[str, str],
):
    if isinstance(value, dict):
        localized = {}
        for key, item in value.items():
            if key == "tags" and isinstance(item, list):
                localized[key] = [
                    f"tesla-{locale}" if tag == "tesla" else tag for tag in item
                ]
            elif key in LOCALIZABLE_VALUE_MAPS and isinstance(item, dict):
                localized[key] = {
                    source: rewrite_string(target, strings, passthrough, uid_map)
                    if isinstance(target, str)
                    else rewrite(target, locale, strings, passthrough, uid_map)
                    for source, target in item.items()
                }
            elif key in LOCALIZABLE_KEY_VALUE_MAPS and isinstance(item, dict):
                localized[key] = {
                    rewrite_string(source, strings, passthrough, uid_map): rewrite(
                        target, locale, strings, passthrough, uid_map
                    )
                    for source, target in item.items()
                }
            elif key == "rawSql" and isinstance(item, str):
                localized[key] = rewrite_string(
                    item,
                    strings,
                    passthrough,
                    uid_map,
                    sql_aliases=True,
                )
            elif key in LOCALIZABLE_KEYS and isinstance(item, str):
                localized[key] = rewrite_string(item, strings, passthrough, uid_map)
            elif key == "value" and value.get("id") == "displayName" and isinstance(item, str):
                localized[key] = rewrite_string(item, strings, passthrough, uid_map)
            elif isinstance(item, str):
                # Exact translations are also applied to references such as field
                # matchers so they stay in sync with translated SQL/display aliases.
                localized[key] = rewrite_string(item, strings, passthrough, uid_map)
            else:
                localized[key] = rewrite(item, locale, strings, passthrough, uid_map)
        return localized

    if isinstance(value, list):
        return [rewrite(item, locale, strings, passthrough, uid_map) for item in value]

    if isinstance(value, str):
        return rewrite_string(value, strings, passthrough, uid_map)

    return value


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Generate locale-specific TeslaMate Grafana dashboards without "
            "modifying the original English dashboards."
        )
    )
    parser.add_argument("--source", required=True)
    parser.add_argument("--translations", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    source_dir = Path(args.source)
    translations_dir = Path(args.translations)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    dashboard_paths = sorted(source_dir.rglob("*.json"))
    dashboards = {
        path.relative_to(source_dir).with_suffix("").as_posix(): load_json(path)
        for path in dashboard_paths
    }

    for pack_path in sorted(translations_dir.glob("*.json")):
        pack = load_json(pack_path)
        locale = pack["locale"]
        dashboard_titles = pack.get("dashboard_titles", {})
        strings = pack.get("strings", {})
        passthrough = set(pack.get("passthrough", []))

        uid_map = {
            dashboard["uid"]: localized_uid(dashboard["uid"], locale)
            for dashboard in dashboards.values()
            if dashboard.get("uid")
        }

        for relative_key, dashboard in dashboards.items():
            localized = rewrite(
                copy.deepcopy(dashboard), locale, strings, passthrough, uid_map
            )

            source_uid = dashboard.get("uid")
            if source_uid:
                localized["uid"] = uid_map[source_uid]

            localized["title"] = dashboard_titles.get(
                relative_key, localized.get("title", dashboard.get("title"))
            )

            target = output_dir / f"{relative_key}.{locale}.json"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                json.dumps(localized, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )


if __name__ == "__main__":
    main()
