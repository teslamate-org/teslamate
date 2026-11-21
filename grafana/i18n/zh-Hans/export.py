"""Opt-in display-only Simplified Chinese export of bundled dashboards."""

import argparse
import copy
import hashlib
import json
import pathlib
import re

BASE = pathlib.Path(__file__).resolve().parent
CATALOG = json.loads((BASE / "translations.json").read_text(encoding="utf-8"))
TERMS = CATALOG["terms"]
LONG = CATALOG["descriptions"]
NOTES = CATALOG["notes"]

MISSING = set()


def tr(s, filename="", panel=None):
    if s == "Start" and filename in ("drives.json", "trip.json"):
        return "出发地点"
    if s == "Drive" and filename in ("drives.json", "trip.json", "updates.json"):
        return {
            "drives.json": "行程列表",
            "trip.json": "行程明细",
            "updates.json": "行程",
        }[filename]
    if s == "Charge" and filename == "updates.json":
        return "充电"
    if panel and filename == "charge-details.json":
        title = panel.get("title", "")
        if title in ("Battery Level", "电量百分比") and s in ("Start", "Added", "End"):
            return {
                "Start": "开始电量",
                "Added": "电量增加（百分点）",
                "End": "结束电量",
            }[s]
        if title.startswith(("Ranges", "续航里程")) and s in ("Start", "Added", "End"):
            return {"Start": "开始续航", "Added": "续航增加量", "End": "结束续航"}[s]
    if s == "Efficiency":
        if filename in ("charges.json", "charge-details.json", "charging-stats.json"):
            return "充电效率"
        if filename == "efficiency.json":
            return "基准电耗"
        if filename == "battery-health.json":
            return "基准电耗"
        if filename == "drives.json":
            return "续航达成率"
    if s == "States" and filename == "locations.json":
        return "省 / 州"
    if s == "Charge Stats" and filename == "charge-details.json":
        return "充电统计"
    if s in TERMS:
        return TERMS[s]
    if s in LONG:
        return LONG[s]
    if (
        re.search("[A-Za-z]", s)
        and not s.startswith(("$", "<div"))
        and s not in ("TeslaMate", "NULL", "km", "PostgreSQL", "kWh")
    ):
        MISSING.add(s)
    return s


def walk_display(x, filename):
    if isinstance(x, dict):
        for k, v in x.items():
            if isinstance(v, str) and k in (
                "title",
                "description",
                "label",
                "displayName",
                "text",
                "content",
                "axisLabel",
                "noValue",
            ):
                x[k] = tr(v, filename)
            elif k not in ("targets", "transformations", "matcher"):
                walk_display(v, filename)
        if x.get("id") == "displayName" and isinstance(x.get("value"), str):
            x["value"] = tr(x["value"], filename)
    elif isinstance(x, list):
        for v in x:
            walk_display(v, filename)


def all_panels(d):
    for p in d.get("panels", []):
        yield p
        yield from all_panels(p)


def alias_pattern(s):
    parts = re.split(r"(\$\{[^}]+\}|\$[A-Za-z_][A-Za-z_0-9]*)", s)
    return (
        "^" + "".join(".+?" if p.startswith("$") else re.escape(p) for p in parts) + "$"
    )


def add_name(p, source, translated):
    if not translated or source == translated:
        return
    ovs = p.setdefault("fieldConfig", {}).setdefault("overrides", [])
    # Match display fields without changing SQL or calculation identifiers.
    matcher = (
        {"id": "byRegexp", "options": alias_pattern(source)}
        if "$" in source
        else {"id": "byName", "options": source}
    )
    for ov in ovs:
        if ov["matcher"] == matcher and any(
            v.get("id") == "displayName" for v in ov["properties"]
        ):
            return
    ovs.append(
        {"matcher": matcher, "properties": [{"id": "displayName", "value": translated}]}
    )


def add_mappings(p, name, mappings):
    overrides = p.setdefault("fieldConfig", {}).setdefault("overrides", [])
    names = list(
        dict.fromkeys(
            [name, TERMS.get(name, name)]
            + (
                ["display"]
                if name == "Period"
                else ["current", "charge_type", "type"]
                if name == "Type"
                else []
            )
        )
    )
    overrides.append(
        {
            "matcher": {
                "id": "byNames",
                "options": {"mode": "include", "names": names},
            },
            "properties": [{"id": "mappings", "value": mappings}],
        }
    )


def returned_names(panel, panels, seen=None):
    seen = set() if seen is None else seen
    if panel.get("id") in seen:
        return set()
    seen.add(panel.get("id"))
    names = set()
    for target in panel.get("targets", []):
        sql = target.get("rawSql", "")
        names.update(re.findall(r'(?i)\bas\s+"([^"]+)"', sql))
        names.update(re.findall(r"'([^'\n]+)'\s+as\s+metric\b", sql, re.I))
        source = panels.get(target.get("panelId"))
        if source and target.get("datasource", {}).get("uid") == "-- Dashboard --":
            names.update(returned_names(source, panels, seen))
    for transform in panel.get("transformations", []):
        options = transform.get("options", {})
        names.update(v for v in options.get("renameByName", {}).values() if v)
        if options.get("alias") and options["alias"] in TERMS:
            names.add(options["alias"])
    return names


def translate(d, filename):
    original = copy.deepcopy(d)
    walk_display(d, filename)
    if filename == "efficiency.json":
        d["title"] = "能耗分析"
    for v, ov in zip(
        d.get("templating", {}).get("list", []),
        original.get("templating", {}).get("list", []),
    ):
        if v.get("type") == "custom":
            pairs = []
            for item in ov["query"].split(","):
                a, sep, b = item.strip().partition(" : ")
                value = b.strip() if sep else a
                text = (
                    {"no": "关闭", "yes": "开启"}.get(a, tr(a, filename))
                    if v["name"] == "high_precision"
                    else tr(a, filename)
                )
                pairs.append(f"{text} : {value}" if text != value else value)
            v["query"] = ", ".join(pairs)
            # Labels preserve the SQL/filter values, including emoji activity values.
            assert [
                p.strip().partition(" : ")[2] or p.strip()
                for p in v["query"].split(",")
            ] == [
                p.strip().partition(" : ")[2] or p.strip()
                for p in ov["query"].split(",")
            ]
            value = ov.get("current", {}).get("value")
            labels = {
                p.strip().partition(" : ")[2] or p.strip(): p.strip().partition(" : ")[
                    0
                ]
                for p in pairs
            }
            if isinstance(value, str) and value in labels:
                v.setdefault("current", {})["text"] = labels[value]
    for p, op in zip(all_panels(d), all_panels(original)):
        # Shared queries return raw fields without the source panel's display config.
        # Grafana selects reduced fields by display name after applying overrides.
        reduce = p.get("options", {}).get("reduceOptions", {})
        selector = reduce.get("fields")
        if filename == "temperatures.json" and selector in ("/Inside/", "/Outside/"):
            reduce["fields"] = {
                "/Inside/": "/Inside|车内/",
                "/Outside/": "/Outside|车外/",
            }[selector]
        if filename == "charge-level.json":
            p["description"] = NOTES["charge_level_trends"]
        if filename == "timeline.json":
            p.setdefault("fieldConfig", {}).setdefault("defaults", {})["noValue"] = "—"
            p["description"] = NOTES["timeline_empty_cells"]
        if filename == "states.json" and selector == "/^state$/":
            reduce["fields"] = "/^(state|车辆状态)$/"
        returned = returned_names(op, {q.get("id"): q for q in all_panels(original)})
        p.setdefault("fieldConfig", {}).setdefault("defaults", {}).setdefault(
            "noValue", "暂无数据"
        )
        if filename == "trip.json" and op.get("id") == 40:
            add_name(p, "value", tr("Total Energy consumed (gross)", filename))
            add_mappings(
                p,
                "metric",
                [
                    {
                        "type": "value",
                        "options": {
                            value: {"text": tr(value, filename)}
                            for value in (
                                "Total Energy consumed (gross)",
                                "Total Energy added (AC)",
                                "Total Energy added (DC)",
                            )
                        },
                    }
                ],
            )
        for s in sorted(returned):
            add_name(p, s, tr(s, filename, p))
        for nov, oov in zip(
            p.get("fieldConfig", {}).get("overrides", []),
            op.get("fieldConfig", {}).get("overrides", []),
        ):
            for np, oldp in zip(nov["properties"], oov["properties"]):
                if oldp.get("id") == "displayName":
                    np["value"] = tr(oldp["value"], filename, op)
                if oldp.get("id") == "custom.fillBelowTo":
                    np["value"] = tr(oldp["value"], filename, op)
            if any(
                v.get("id") == "unit" and v.get("value") == "bool_on_off"
                for v in oov["properties"]
            ):
                if not any(v.get("id") == "mappings" for v in nov["properties"]):
                    nov["properties"].append(
                        {
                            "id": "mappings",
                            "value": [
                                {
                                    "type": "value",
                                    "options": {
                                        "true": {"text": "开启"},
                                        "false": {"text": "关闭"},
                                    },
                                }
                            ],
                        }
                    )
        if filename == "states.json" and op.get("title") in (
            "Current State",
            "Last state change",
        ):
            add_name(p, "state", "车辆状态")
            add_mappings(
                p,
                "state",
                [
                    {
                        "type": "value",
                        "options": {
                            v: {"text": tr(v, filename)}
                            for v in (
                                "online",
                                "offline",
                                "asleep",
                                "driving",
                                "charging",
                                "updating",
                                "suspended",
                            )
                        },
                    }
                ],
            )
        if filename == "statistics.json" and op.get("type") == "table":
            months = [
                "January",
                "February",
                "March",
                "April",
                "May",
                "June",
                "July",
                "August",
                "September",
                "October",
                "November",
                "December",
            ]
            mappings = [
                {
                    "type": "regex",
                    "options": {
                        "pattern": r"^(\d{4})\s+" + m + r"\s*$",
                        "result": {"text": "$1年" + str(i) + "月"},
                    },
                }
                for i, m in enumerate(months, 1)
            ]
            mappings += [
                {
                    "type": "regex",
                    "options": {
                        "pattern": r"^week (\d+) starting (\d{4}-\d{2}-\d{2})$",
                        "result": {"text": "第 $1 周（起始 $2）"},
                    },
                },
                {"type": "value", "options": {"Total": {"text": "所选时段合计"}}},
            ]
            add_mappings(p, "Period", mappings)
        if filename == "charges.json" and op.get("type") == "table":
            add_mappings(
                p,
                "Type",
                [
                    {
                        "type": "value",
                        "options": {
                            "AC": {"text": "交流充电"},
                            "DC": {"text": "直流充电"},
                        },
                    }
                ],
            )
        if filename == "timeline.json" and op.get("type") == "table":
            add_mappings(
                p,
                "Action",
                [
                    {
                        "type": "value",
                        "options": {
                            v: {"text": tr(v, filename)}
                            for v in (
                                "🚗 Driving",
                                "🔋 Charging",
                                "🅿️ Parking",
                                "❓ Missing",
                                "💾 Updating",
                            )
                        },
                    }
                ],
            )
        # Unquoted series names and categorical series produced by the standard queries.
        if op.get("targets"):
            sql_text = "\n".join(t.get("rawSql", "") for t in op["targets"])
            for s in (
                "AC",
                "DC",
                "online",
                "offline",
                "asleep",
                "driving",
                "charging",
                "updating",
                "suspended",
                "Online",
                "Offline",
                "Asleep",
                "Driving",
                "Charging",
                "Updating",
                "Suspended",
                "charging (AC)",
                "charging (DC",
            ):
                if "'" + s + "'" in sql_text or (
                    filename == "states.json" and "metric" in sql_text
                ):
                    add_name(p, s, tr(s, filename))
        if "(net)" in op.get("title", ""):
            p["description"] = (
                p.get("description", "") + NOTES["net_consumption"]
            ).strip()
        if "(gross)" in op.get("title", ""):
            p["description"] = (
                p.get("description", "") + NOTES["gross_consumption"]
            ).strip()
        if op.get("title") == "Current Stored Energy":
            p["description"] = NOTES["stored_energy"]
        if filename == "charging-stats.json" and op.get("title") == "Charge Delta":
            p["description"] = NOTES["charge_delta"]
        if filename == "projected-range.json" and op.get("targets"):
            p["description"] = NOTES["projected_range"]
        if "$preferred_range" in op.get("title", "") or "${preferred_range}" in op.get(
            "title", ""
        ):
            p["description"] = (
                p.get("description", "") + NOTES["preferred_range"]
            ).strip()
        assert p.get("targets", []) == op.get("targets", []), filename
        assert p.get("transformations", []) == op.get("transformations", []), filename
    if filename == "dutch-tax.json":
        d["description"] = NOTES["dutch_tax"]
    assert d["uid"] == original["uid"]
    return d


def export(source, output):
    source = pathlib.Path(source).resolve(strict=True)
    output = pathlib.Path(output).resolve()
    if output.exists():
        raise FileExistsError(f"Output already exists: {output}")
    if source == output or source in output.parents:
        raise ValueError("Output must be outside the source dashboard directory")
    if not source.is_dir():
        raise ValueError("Source must be an upstream grafana/dashboards directory")
    files = sorted(source.rglob("*.json"))
    if not files:
        raise ValueError("No source dashboards found")
    expected_sources = CATALOG["source_sha256"]
    if {p.relative_to(source).as_posix() for p in files} != set(expected_sources):
        raise ValueError(
            "Source dashboard set changed; review the catalog before exporting"
        )
    MISSING.clear()
    rendered = []
    uids = set()
    for path in files:
        relative = path.relative_to(source)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != expected_sources[relative.as_posix()]:
            raise ValueError(
                f"Source changed: {relative}; review the catalog before exporting"
            )
        if len(relative.parts) == 1:
            target = pathlib.Path("main") / relative
        elif len(relative.parts) == 2 and relative.parts[0] in ("internal", "reports"):
            target = relative
        else:
            raise ValueError(f"Unexpected source path: {relative}")
        data = json.loads(path.read_text(encoding="utf-8"))
        if (
            not isinstance(data, dict)
            or not isinstance(data.get("uid"), str)
            or not isinstance(data.get("panels"), list)
        ):
            raise ValueError(f"Not a dashboard: {relative}")
        if data["uid"] in uids:
            raise ValueError(f"Duplicate dashboard UID: {data['uid']}")
        uids.add(data["uid"])
        translated = translate(copy.deepcopy(data), path.name)
        validate_unchanged(data, translated)
        rendered.append((target, translated, digest))
    if MISSING:
        raise ValueError(
            "Untranslated display strings; review the source version and catalog: "
            + repr(sorted(MISSING))
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir()
    manifest = []
    for target, data, digest in rendered:
        file = output / target
        file.parent.mkdir(parents=True, exist_ok=True)
        with file.open("x", encoding="utf-8") as handle:
            handle.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        manifest.append(
            {"path": target.as_posix(), "uid": data["uid"], "source_sha256": digest}
        )
    with (output / "manifest.json").open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(manifest, indent=2) + "\n")
    return len(rendered)


def validate_unchanged(before, after):
    if before["uid"] != after["uid"]:
        raise ValueError("Dashboard UID changed")
    old_panels, new_panels = list(all_panels(before)), list(all_panels(after))
    if len(old_panels) != len(new_panels):
        raise ValueError("Panel count changed")
    for old, new in zip(old_panels, new_panels):
        for key in (
            "id",
            "type",
            "datasource",
            "targets",
            "transformations",
            "gridPos",
        ):
            if old.get(key) != new.get(key):
                raise ValueError(f"Non-display panel content changed: {key}")
    variables = before.get("templating", {}).get("list", [])
    translated_variables = after.get("templating", {}).get("list", [])
    if len(variables) != len(translated_variables):
        raise ValueError("Variable count changed")
    for old, new in zip(variables, translated_variables):
        for key in (
            "name",
            "type",
            "datasource",
            "definition",
            "regex",
            "allValue",
            "includeAll",
            "hide",
            "multi",
        ):
            if old.get(key) != new.get(key):
                raise ValueError(f"Variable behavior changed: {key}")
        if old.get("current", {}).get("value") != new.get("current", {}).get("value"):
            raise ValueError("Selected variable value changed")
        if old.get("type") == "custom":

            def values(query):
                return [
                    p.strip().partition(" : ")[2] or p.strip() for p in query.split(",")
                ]

            if values(old["query"]) != values(new["query"]):
                raise ValueError("Custom filter values changed")
        elif old.get("query") != new.get("query"):
            raise ValueError("Variable query changed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "source", type=pathlib.Path, help="Official grafana/dashboards source directory"
    )
    parser.add_argument(
        "output",
        type=pathlib.Path,
        help="New output directory; existing directories are never overwritten",
    )
    args = parser.parse_args()
    try:
        count = export(args.source, args.output)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    print(
        f"Exported {count} Simplified Chinese dashboards; "
        "source files were not changed."
    )


if __name__ == "__main__":
    main()
