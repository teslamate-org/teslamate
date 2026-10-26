"""Safety checks for the optional display-only dashboard exporter."""

import copy
import importlib.util
import json
import pathlib
import re
import shutil
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("zh_dashboard_export", HERE / "export.py")
EXPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORTER)


def fixture(title="Overview"):
    return {
        "uid": "example-dashboard",
        "title": title,
        "links": [
            {"title": "Dashboards", "url": "/d/example?from=${__from}&to=${__to}"}
        ],
        "templating": {
            "list": [
                {
                    "name": "action_filter",
                    "type": "custom",
                    "label": "Action",
                    "query": "🚗 Driving,🔋 Charging",
                    "current": {"text": "🚗 Driving", "value": "🚗 Driving"},
                    "includeAll": True,
                    "allValue": "-1",
                },
                {
                    "name": "car_id",
                    "type": "query",
                    "query": "SELECT id AS __value, name AS __text FROM cars",
                    "definition": "SELECT id AS __value, name AS __text FROM cars",
                    "current": {"text": "1", "value": "1"},
                },
            ]
        },
        "panels": [
            {
                "id": 1,
                "type": "timeseries",
                "title": "Charging curve",
                "datasource": {
                    "type": "grafana-postgresql-datasource",
                    "uid": "TeslaMate",
                },
                "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
                "targets": [
                    {
                        "refId": "Time",
                        "rawSql": (
                            'SELECT now() AS "time", 1 AS "Start" ORDER BY "Start" DESC'
                        ),
                        "timeColumn": "time",
                        "groupBy": [{"type": "time"}],
                    }
                ],
                "options": {"xField": "Time", "colorByField": "Start"},
                "transformations": [
                    {"id": "sortBy", "options": {"sort": [{"field": "Start"}]}}
                ],
                "fieldConfig": {
                    "defaults": {
                        "unit": "kwatt",
                        "thresholds": {
                            "mode": "absolute",
                            "steps": [{"color": "green", "value": 0}],
                        },
                    },
                    "overrides": [
                        {
                            "matcher": {"id": "byName", "options": "Start"},
                            "properties": [
                                {"id": "unit", "value": "kwatt"},
                                {
                                    "id": "links",
                                    "value": [
                                        {
                                            "title": "View charge details",
                                            "url": "/d/charge?var-id=${__value.raw}",
                                        }
                                    ],
                                },
                            ],
                        }
                    ],
                },
            }
        ],
    }


class TranslationSafetyTests(unittest.TestCase):
    def test_charge_level_uses_plain_language_and_timeline_null_is_not_data_loss(self):
        original = fixture()
        chart = EXPORTER.translate(copy.deepcopy(original), "charge-level.json")
        label = EXPORTER.tr(
            "$days_moving_average_percentiles Day Moving 7.5% Percentile "
            "(${bucket_width:text} buckets)"
        )
        self.assertIn("电量低位参考线", label)
        self.assertNotIn("分位", label)
        self.assertIn("不是建议的充电上下限", chart["panels"][0]["description"])
        timeline = EXPORTER.translate(copy.deepcopy(original), "timeline.json")
        self.assertEqual(
            timeline["panels"][0]["fieldConfig"]["defaults"]["noValue"], "—"
        )
        EXPORTER.validate_unchanged(original, timeline)

    def test_shared_queries_and_calculated_aliases_receive_display_overrides(self):
        original = fixture()
        source = original["panels"][0]
        source["targets"][0]["rawSql"] = 'SELECT 1 AS "Min Inside [°$temp_unit]"'
        shared = copy.deepcopy(source)
        shared["id"] = 2
        shared["options"] = {"reduceOptions": {"fields": "/Inside/"}}
        shared["targets"] = [{"panelId": 1, "datasource": {"uid": "-- Dashboard --"}}]
        shared["transformations"] = [
            {
                "id": "calculateField",
                "options": {"alias": "Ø Cost per 100 $length_unit"},
            }
        ]
        original["panels"].append(shared)
        translated = EXPORTER.translate(copy.deepcopy(original), "temperatures.json")
        EXPORTER.validate_unchanged(original, translated)
        overrides = translated["panels"][1]["fieldConfig"]["overrides"]
        labels = [
            prop["value"]
            for override in overrides
            for prop in override["properties"]
            if prop["id"] == "displayName"
        ]
        self.assertEqual(
            translated["panels"][1]["options"]["reduceOptions"]["fields"],
            "/Inside|车内/",
        )
        self.assertIn("最低车内温度 [°$temp_unit]", labels)
        self.assertIn("平均每 100 $length_unit 费用", labels)

    def test_shared_query_cycle_does_not_recurse_forever(self):
        panel = {
            "id": 1,
            "targets": [{"panelId": 1, "datasource": {"uid": "-- Dashboard --"}}],
        }
        self.assertEqual(EXPORTER.returned_names(panel, {1: panel}), set())

    def test_temperature_percentile_labels_distinguish_bounds_from_coverage(self):
        self.assertEqual(EXPORTER.tr("15th Percentile"), "15% 分位温度（下边界）")
        self.assertEqual(EXPORTER.tr("85th Percentile"), "85% 分位温度（上边界）")
        description = next(
            value
            for key, value in EXPORTER.LONG.items()
            if key.startswith("For each day")
        )
        self.assertIn("70%", description)
        self.assertIn("85% − 15%", description)

    def test_queries_aliases_time_and_machine_references_are_not_translated(self):
        original = fixture()
        translated = EXPORTER.translate(copy.deepcopy(original), "overview.json")
        EXPORTER.validate_unchanged(original, translated)
        self.assertEqual(translated["title"], "车辆概况")
        before, after = original["panels"][0], translated["panels"][0]
        for key in ("targets", "datasource", "transformations", "options", "gridPos"):
            self.assertEqual(after[key], before[key])
        self.assertEqual(after["fieldConfig"]["defaults"]["unit"], "kwatt")
        self.assertEqual(
            after["fieldConfig"]["defaults"]["thresholds"],
            before["fieldConfig"]["defaults"]["thresholds"],
        )
        self.assertEqual(
            after["fieldConfig"]["overrides"][0]["matcher"],
            before["fieldConfig"]["overrides"][0]["matcher"],
        )
        old_link = before["fieldConfig"]["overrides"][0]["properties"][1]["value"][0]
        new_link = after["fieldConfig"]["overrides"][0]["properties"][1]["value"][0]
        self.assertEqual(new_link["url"], old_link["url"])
        self.assertEqual(new_link["title"], "查看充电详情")

    def test_custom_filter_labels_do_not_change_sql_values(self):
        original = fixture()
        translated = EXPORTER.translate(copy.deepcopy(original), "timeline.json")
        variable = translated["templating"]["list"][0]
        self.assertEqual(
            variable["query"], "🚗 行驶 : 🚗 Driving, 🔋 充电 : 🔋 Charging"
        )
        self.assertEqual(variable["current"]["value"], "🚗 Driving")
        self.assertEqual(variable["allValue"], "-1")
        self.assertEqual(
            translated["templating"]["list"][1], original["templating"]["list"][1]
        )

    def test_same_word_uses_the_panel_context(self):
        original = fixture()
        original["panels"][0]["title"] = "Battery Level"
        original["panels"][0]["targets"][0]["rawSql"] = (
            'SELECT 20 AS "Start", 40 AS "Added", 60 AS "End"'
        )
        translated = EXPORTER.translate(copy.deepcopy(original), "charge-details.json")
        names = [
            prop["value"]
            for item in translated["panels"][0]["fieldConfig"]["overrides"]
            for prop in item["properties"]
            if prop["id"] == "displayName"
        ]
        self.assertIn("电量增加（百分点）", names)
        self.assertIn("开始电量", names)
        self.assertIn("结束电量", names)
        self.assertNotIn("充入电量", names)

    def test_validator_rejects_query_or_transformation_changes(self):
        original = fixture()
        modified = copy.deepcopy(original)
        modified["panels"][0]["targets"][0]["timeColumn"] = "时间"
        with self.assertRaisesRegex(ValueError, "targets"):
            EXPORTER.validate_unchanged(original, modified)
        modified = copy.deepcopy(original)
        modified["panels"][0]["transformations"][0]["options"]["sort"][0]["field"] = (
            "开始"
        )
        with self.assertRaisesRegex(ValueError, "transformations"):
            EXPORTER.validate_unchanged(original, modified)

    def test_existing_output_and_source_files_are_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source, output = root / "source", root / "output"
            source.mkdir()
            data = json.dumps(fixture(), ensure_ascii=False)
            path = source / "overview.json"
            path.write_text(data, encoding="utf-8")
            output.mkdir()
            sentinel = output / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                EXPORTER.export(source, output)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")
            self.assertEqual(path.read_text(encoding="utf-8"), data)
            with self.assertRaisesRegex(ValueError, "outside"):
                EXPORTER.export(source, source / "generated")

    def test_changed_source_requires_catalog_review_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "overview.json").write_text(
                json.dumps(fixture("New upstream metric requiring review")),
                encoding="utf-8",
            )
            output = root / "output"
            with self.assertRaisesRegex(ValueError, "review the catalog"):
                EXPORTER.export(source, output)
            self.assertFalse(output.exists())

    def test_edited_upstream_snapshot_requires_review(self):
        source = HERE.parents[1] / "dashboards"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            edited = root / "source"
            shutil.copytree(source, edited)
            path = edited / "overview.json"
            path.write_bytes(path.read_bytes() + b"\n")
            output = root / "output"
            with self.assertRaisesRegex(ValueError, "Source changed"):
                EXPORTER.export(edited, output)
            self.assertFalse(output.exists())

    def test_missing_catalog_entry_is_detected_before_output(self):
        source = HERE.parents[1] / "dashboards"
        translation = EXPORTER.TERMS.pop("Overview")
        try:
            with tempfile.TemporaryDirectory() as directory:
                output = pathlib.Path(directory) / "output"
                with self.assertRaisesRegex(ValueError, "Untranslated display strings"):
                    EXPORTER.export(source, output)
                self.assertFalse(output.exists())
        finally:
            EXPORTER.TERMS["Overview"] = translation

    def test_month_mapping_matches_raw_and_translated_field_names(self):
        original = fixture()
        original["panels"][0]["type"] = "table"
        translated = EXPORTER.translate(copy.deepcopy(original), "statistics.json")
        mapping = next(
            item
            for item in translated["panels"][0]["fieldConfig"]["overrides"]
            if item["matcher"]["id"] == "byNames"
            and "display" in item["matcher"]["options"]["names"]
        )
        self.assertEqual(
            set(mapping["matcher"]["options"]["names"]),
            {"display", "Period", "统计周期"},
        )
        october = mapping["properties"][0]["value"][9]["options"]
        match = re.fullmatch(october["pattern"], "2026 October   ")
        self.assertIsNotNone(match)
        self.assertEqual(
            october["result"]["text"].replace("$1", match[1]), "2026年10月"
        )
        EXPORTER.validate_unchanged(original, translated)

    def test_all_bundled_dashboards_export_with_stable_uids_and_queries(self):
        source = HERE.parents[1] / "dashboards"
        files = sorted(source.rglob("*.json"))
        original = {path: path.read_bytes() for path in files}
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "export"
            count = EXPORTER.export(source, output)
            self.assertEqual(count, len(files))
            self.assertEqual(count, 24)
            manifest = json.loads(
                (output / "manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(len({item["uid"] for item in manifest}), count)
            for path in files:
                relative = path.relative_to(source)
                target = (
                    relative
                    if len(relative.parts) > 1
                    else pathlib.Path("main") / relative
                )
                before = json.loads(original[path])
                after = json.loads((output / target).read_text(encoding="utf-8"))
                EXPORTER.validate_unchanged(before, after)
                self.assertEqual(path.read_bytes(), original[path])


if __name__ == "__main__":
    unittest.main()
