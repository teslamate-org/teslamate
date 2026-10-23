//! Compares `teslamate_rust::close_drive` with Elixir's `close_drive`, as
//! pinned by the characterization goldens in
//! `elixir/test/fixtures/characterization/goldens`, read at run time.
//!
//! A golden is the database after a recorded scenario. The test replays
//! every golden that has a drive, except those in [`SKIP`]: it inserts the
//! golden's cars, geofences and positions, plus each drive as `start_drive`
//! leaves it (id, car, start date), closes each drive with the port and
//! compares the result with the golden's drives row. The address columns
//! are left out: the port runs without the address lookup, the goldens with
//! a stubbed geocoder. A new golden with a drive is replayed without
//! changing the test; one that cannot be replayed fails it until it is
//! added to [`SKIP`].
//!
//! The deletion of a drive is not compared: a deleted drive leaves no row,
//! and the deletion sets its positions' `drive_id` to NULL, so the golden
//! does not show which positions belonged to it (`driving_without_odometer`).
//!
//! See `common/database.rs` for what the test needs; run it with
//!
//! ```sh
//! cargo test --test close_drive -- --ignored --nocapture
//! ```
//!
//! `--nocapture` shows how many goldens and drives were replayed.

#[path = "common/database.rs"]
mod database;

use std::{
    fs,
    path::{Path, PathBuf},
};

use database::Result;
use serde_json::{Map, Value, json};
use sqlx::{PgConnection, Row as _, postgres::PgRow};
use teslamate_rust::close_drive::{self, Drive, Outcome};

/// Goldens with a drive that the test cannot replay, and why.
const SKIP: [(&str, &str); 1] = [(
    "driving_empty_drive_state",
    "the scenario ends with the drive still open: close_drive never ran",
)];

/// The tables the test inserts, in the order of their foreign keys; drives
/// get skeleton rows instead of the golden's.
const TABLES: [&str; 5] = ["car_settings", "cars", "geofences", "drives", "positions"];

#[tokio::test]
#[ignore = "needs a Postgres database, see tests/common/database.rs; fails without one"]
async fn port_closes_drives_like_the_characterization_goldens() -> Result<()> {
    let mut transaction = database::transaction().await?;
    let mut skipped = Vec::new();
    let (mut replayed, mut drives_closed) = (0, 0);

    for (name, path) in goldens()? {
        if SKIP.iter().any(|(skip, _)| *skip == name) {
            skipped.push(name);
            continue;
        }
        let tables = golden_tables(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        let drives = rows(&tables, "drives")?;
        if drives.is_empty() {
            continue;
        }

        let mut savepoint = sqlx::Acquire::begin(&mut *transaction).await?;
        for table in TABLES {
            let rows = if table == "drives" {
                // As `start_drive` inserts them; close_drive writes the rest.
                drives
                    .iter()
                    .map(|drive| {
                        json!({
                            "id": drive["id"],
                            "car_id": drive["car_id"],
                            "start_date": "2000-01-01T00:00:00",
                        })
                    })
                    .collect()
            } else {
                rows(&tables, table)?
            };
            insert(&mut savepoint, table, rows)
                .await
                .map_err(|e| format!("{name}: cannot insert {table}: {e}"))?;
        }

        for golden_drive in &drives {
            let drive_id = golden_drive["id"]
                .as_i64()
                .and_then(|id| i32::try_from(id).ok())
                .ok_or_else(|| format!("{name}: drive without id"))?;
            if golden_drive["end_date"].is_null() {
                return Err(format!(
                    "{name}: drive {drive_id} is still open, so close_drive never ran; \
                     add the golden to SKIP"
                )
                .into());
            }

            let mut expected = golden_row(&mut savepoint, golden_drive).await?;
            expected.start_address_id = None;
            expected.end_address_id = None;

            let outcome = close_drive::close_drive(&mut *savepoint, drive_id).await?;
            assert_eq!(
                outcome,
                Outcome::Closed(Box::new(expected)),
                "{name}, drive {drive_id}"
            );
            drives_closed += 1;
        }

        savepoint.rollback().await?;
        replayed += 1;
    }

    transaction.rollback().await?;

    for (skip, reason) in SKIP {
        if !skipped.iter().any(|name| name == skip) {
            return Err(format!("SKIP lists {skip} ({reason}), which does not exist").into());
        }
    }
    if replayed == 0 {
        return Err("no golden with a drive found".into());
    }
    println!("replayed {replayed} goldens with {drives_closed} drives");
    Ok(())
}

/// Every golden's name and path, in name order.
fn goldens() -> Result<Vec<(String, PathBuf)>> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../elixir/test/fixtures/characterization/goldens");
    let mut paths = fs::read_dir(&dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    paths.retain(|path| {
        path.extension()
            .is_some_and(|extension| extension == "json")
    });
    paths.sort();
    paths
        .into_iter()
        .map(|path| {
            let name = path
                .file_stem()
                .map(|stem| stem.to_string_lossy().into_owned())
                .ok_or_else(|| format!("{}: no file name", path.display()))?;
            Ok((name, path))
        })
        .collect()
}

/// The tables of [`TABLES`] from the `database` section of the golden at
/// `path`, with the harness's id labels replaced by negative ids.
fn golden_tables(path: &Path) -> Result<Map<String, Value>> {
    let json: Value = serde_json::from_str(&fs::read_to_string(path)?)?;
    let Some(Value::Object(database)) = json.get("database") else {
        return Err("no database section".into());
    };
    let mut tables = Map::new();
    for table in TABLES {
        let mut rows = database
            .get(table)
            .cloned()
            .ok_or_else(|| format!("no table {table}"))?;
        for row in rows.as_array_mut().into_iter().flatten() {
            if let Value::Object(row) = row {
                relabel(row).map_err(|e| format!("{table}: {e}"))?;
            }
        }
        tables.insert(table.to_owned(), rows);
    }
    Ok(tables)
}

/// The harness writes ids as `<table>_<n>` (the n-th row of the table by
/// id) and the car's as `$car`, and masks `inserted_at` and `updated_at`
/// (`elixir/test/support/characterization.ex`). Row n becomes id -n, the car
/// -1, and the masked timestamps a fixed value. Any other masked value in a
/// row the test inserts is an error.
fn relabel(row: &mut Map<String, Value>) -> Result<()> {
    for (column, value) in row.iter_mut() {
        let Value::String(text) = value else {
            continue;
        };
        if column == "inserted_at" || column == "updated_at" {
            *value = json!("2000-01-01T00:00:00");
        } else if column == "id" || column.ends_with("_id") {
            let id = if text == "$car" {
                -1
            } else {
                let (_, n) = text
                    .rsplit_once('_')
                    .ok_or_else(|| format!("{column}: not an id label: {text}"))?;
                -n.parse::<i64>()
                    .map_err(|e| format!("{column}: not an id label: {text}: {e}"))?
            };
            *value = json!(id);
        } else if text == "<volatile>" {
            return Err(format!("{column} is masked as <volatile>").into());
        }
    }
    Ok(())
}

fn rows(tables: &Map<String, Value>, table: &str) -> Result<Vec<Value>> {
    tables
        .get(table)
        .and_then(Value::as_array)
        .cloned()
        .ok_or_else(|| format!("no table {table}").into())
}

/// Inserts `rows`, given as JSON objects keyed by column, into `table`.
/// Postgres converts the values to the column types, as it parsed them when
/// the harness read them as text.
async fn insert(connection: &mut PgConnection, table: &str, rows: Vec<Value>) -> Result<()> {
    let sql = match table {
        "car_settings" => {
            "INSERT INTO car_settings SELECT * FROM jsonb_populate_recordset(NULL::car_settings, $1::text::jsonb)"
        }
        "cars" => {
            "INSERT INTO cars SELECT * FROM jsonb_populate_recordset(NULL::cars, $1::text::jsonb)"
        }
        "geofences" => {
            "INSERT INTO geofences SELECT * FROM jsonb_populate_recordset(NULL::geofences, $1::text::jsonb)"
        }
        "drives" => {
            "INSERT INTO drives SELECT * FROM jsonb_populate_recordset(NULL::drives, $1::text::jsonb)"
        }
        "positions" => {
            "INSERT INTO positions SELECT * FROM jsonb_populate_recordset(NULL::positions, $1::text::jsonb)"
        }
        _ => return Err(format!("no insert for table {table}").into()),
    };
    sqlx::query(sql)
        .bind(Value::Array(rows).to_string())
        .execute(connection)
        .await?;
    Ok(())
}

/// The golden's drives row, typed by Postgres like the port's result.
async fn golden_row(connection: &mut PgConnection, row: &Value) -> Result<Drive> {
    let row = sqlx::query("SELECT * FROM jsonb_populate_record(NULL::drives, $1::text::jsonb)")
        .bind(row.to_string())
        .fetch_one(connection)
        .await?;
    Ok(decode(&row)?)
}

fn decode(row: &PgRow) -> sqlx::Result<Drive> {
    Ok(Drive {
        id: row.try_get("id")?,
        car_id: row.try_get("car_id")?,
        start_date: row.try_get("start_date")?,
        end_date: row.try_get("end_date")?,
        start_position_id: row.try_get("start_position_id")?,
        end_position_id: row.try_get("end_position_id")?,
        start_address_id: row.try_get("start_address_id")?,
        end_address_id: row.try_get("end_address_id")?,
        start_geofence_id: row.try_get("start_geofence_id")?,
        end_geofence_id: row.try_get("end_geofence_id")?,
        outside_temp_avg: row.try_get("outside_temp_avg")?,
        inside_temp_avg: row.try_get("inside_temp_avg")?,
        speed_max: row.try_get("speed_max")?,
        power_max: row.try_get("power_max")?,
        power_min: row.try_get("power_min")?,
        start_ideal_range_km: row.try_get("start_ideal_range_km")?,
        end_ideal_range_km: row.try_get("end_ideal_range_km")?,
        start_rated_range_km: row.try_get("start_rated_range_km")?,
        end_rated_range_km: row.try_get("end_rated_range_km")?,
        start_km: row.try_get("start_km")?,
        end_km: row.try_get("end_km")?,
        distance: row.try_get("distance")?,
        duration_min: row.try_get("duration_min")?,
        ascent: row.try_get("ascent")?,
        descent: row.try_get("descent")?,
    })
}
