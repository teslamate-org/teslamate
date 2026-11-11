//! The `close_drive` port against Elixir's `close_drive`, as pinned by the
//! characterization goldens in `elixir/test/fixtures/characterization/
//! goldens`, on a real database.
//!
//! A golden is the database after a recorded scenario. The test replays
//! every golden that has a drive, except those in [`SKIP`]: it inserts
//! the golden's cars, geofences and positions, plus each drive as
//! `start_drive` leaves it (id, car, start date), closes each drive with
//! the port and compares the result with the golden's drives row. The
//! address columns are left out: the port runs without the address
//! lookup, the goldens with a stubbed geocoder. A new golden with a drive
//! is replayed without changing the test; one that cannot be replayed
//! fails it until it is added to [`SKIP`].
//!
//! The deletion of a drive is not compared: a deleted drive leaves no
//! row, and the deletion sets its positions' `drive_id` to NULL, so the
//! golden does not show which positions belonged to it
//! (`driving_without_odometer`).
//!
//! The database the test runs against is `TEST_DATABASE_URL` if set, else
//! `DATABASE_URL`; either way it must be migrated to the `TeslaMate`
//! schema. The goldens are read at run time, so new ones are replayed
//! without changing the test.

use std::fs;
use std::path::{Path, PathBuf};

use diesel_async::{AsyncConnection, AsyncPgConnection, RunQueryDsl, SimpleAsyncConnection};
use serde_json::{Map, Value, json};

use teslamate_rust::database::queries::close_drive::{Drive, Outcome, close_drive_on};

/// Goldens with a drive that the test cannot replay, and why.
const SKIP: [(&str, &str); 1] = [(
    "driving_empty_drive_state",
    "the scenario ends with the drive still open: close_drive never ran",
)];

/// The tables the test inserts, in the order of their foreign keys;
/// drives get skeleton rows instead of the golden's.
const TABLES: [&str; 5] = ["car_settings", "cars", "geofences", "drives", "positions"];

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

/// The database the test runs against: `TEST_DATABASE_URL` if set, else
/// `DATABASE_URL`. Either way it must be migrated to the `TeslaMate`
/// schema; the CI build starts a Postgres, migrates it and points
/// `TEST_DATABASE_URL` at it.
fn test_database_url() -> Result<String> {
    std::env::var("TEST_DATABASE_URL")
        .or_else(|_| std::env::var("DATABASE_URL"))
        .map_err(|_| {
            "neither TEST_DATABASE_URL nor DATABASE_URL is set: the golden test \
             needs a Postgres migrated to the TeslaMate schema"
                .into()
        })
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
    let json: Value = fs::read_to_string(path)?.parse()?;
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
/// (`elixir/test/support/characterization.ex`). Row n becomes id -n, the
/// car -1, and the masked timestamps a fixed value. Any other masked
/// value in a row the test inserts is an error.
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
/// Postgres converts the values to the column types, as it parsed them
/// when the harness read them as text.
async fn insert(conn: &mut AsyncPgConnection, table: &str, rows: Vec<Value>) -> Result<()> {
    if !rows.iter().all(serde_json::Value::is_object) {
        return Err(format!("{table}: a row is not an object").into());
    }
    let sql = format!(
        "INSERT INTO {table} SELECT * FROM jsonb_populate_recordset(NULL::{table}, $1::text::jsonb)"
    );
    diesel::sql_query(&sql)
        .bind::<diesel::sql_types::Text, _>(Value::Array(rows).to_string())
        .execute(conn)
        .await?;
    Ok(())
}

/// The golden's drives row, typed by Postgres like the port's result.
async fn golden_row(conn: &mut AsyncPgConnection, row: &Value) -> Result<Drive> {
    diesel::sql_query("SELECT * FROM jsonb_populate_record(NULL::drives, $1::text::jsonb)")
        .bind::<diesel::sql_types::Text, _>(row.to_string())
        .load::<Drive>(conn)
        .await?
        .into_iter()
        .next()
        .ok_or_else(|| "no row".into())
}

/// Replays one golden: inserts its cars, geofences and positions, each
/// drive as `start_drive` leaves it, and closes every drive, comparing
/// the result with the golden's drives row. Returns how many drives were
/// closed.
async fn replay_golden(
    conn: &mut AsyncPgConnection,
    tables: &Map<String, Value>,
    drives: &[Value],
) -> Result<usize> {
    let mut drives_closed = 0;

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
            rows(tables, table)?
        };
        insert(conn, table, rows)
            .await
            .map_err(|e| format!("cannot insert {table}: {e}"))?;
    }

    for golden_drive in drives {
        let drive_id = golden_drive["id"]
            .as_i64()
            .and_then(|id| i32::try_from(id).ok())
            .ok_or_else(|| "drive without id".to_owned())?;
        if golden_drive["end_date"].is_null() {
            return Err(
                "the drive is still open, so close_drive never ran; add the golden to \
                        SKIP"
                    .into(),
            );
        }

        let mut expected = golden_row(conn, golden_drive).await?;
        // the port runs without the address lookup
        expected.start_address_id = None;
        expected.end_address_id = None;

        let outcome = close_drive_on(conn, drive_id).await?;
        assert_eq!(
            outcome,
            Outcome::Closed(Box::new(expected)),
            "drive {drive_id}"
        );
        drives_closed += 1;
    }
    Ok(drives_closed)
}

/// Replays every golden that has a drive and compares the closed drives.
///
/// The goldens run in a transaction that is rolled back, so the database
/// is unchanged; each golden runs in its own savepoint, rolled back
/// whether it passed or failed, so one bad golden neither hides the next
/// nor leaves its rows behind.
#[tokio::test]
#[allow(clippy::too_many_lines)]
async fn port_closes_drives_like_the_characterization_goldens() -> Result<()> {
    let url = test_database_url()?;
    let mut conn = AsyncPgConnection::establish(&url).await?;
    let mut skipped = Vec::new();
    let (mut replayed, mut drives_closed) = (0, 0);

    // Returning Err(RollbackTransaction) rolls the transaction back: the
    // goldens must never reach the database, pass or fail.
    let outcome = conn
        .transaction::<(), Box<dyn std::error::Error + Send + Sync>, _>(async |conn| {
            for (name, path) in goldens()? {
                if SKIP.iter().any(|(skip, _)| *skip == name) {
                    skipped.push(name);
                    continue;
                }
                let tables =
                    golden_tables(&path).map_err(|e| format!("{}: {e}", path.display()))?;
                let drives = rows(&tables, "drives")?;
                if drives.is_empty() {
                    continue;
                }

                conn.batch_execute("SAVEPOINT golden").await?;
                let replay = replay_golden(conn, &tables, &drives).await;
                // A failed statement aborts the transaction; the
                // rollback clears that too.
                conn.batch_execute("ROLLBACK TO SAVEPOINT golden").await?;
                conn.batch_execute("RELEASE SAVEPOINT golden").await?;
                let closed = replay.map_err(|e| format!("{name}: {e}"))?;

                replayed += 1;
                drives_closed += closed;
            }

            // Every SKIP entry must have matched a golden, so the list
            // cannot go stale.
            for (skip, reason) in SKIP {
                if !skipped.iter().any(|name| name == skip) {
                    return Err(
                        format!("SKIP lists {skip} ({reason}), which does not exist").into(),
                    );
                }
            }
            if replayed == 0 {
                return Err("no golden with a drive found".into());
            }

            Err(diesel::result::Error::RollbackTransaction.into())
        })
        .await;

    match outcome {
        Err(e)
            if matches!(
                e.downcast_ref::<diesel::result::Error>(),
                Some(diesel::result::Error::RollbackTransaction)
            ) =>
        {
            println!("replayed {replayed} goldens with {drives_closed} drives");
            Ok(())
        }
        Err(e) => Err(e),
        // The callback never returns Ok; a commit would persist goldens.
        Ok(()) => Err("the golden transaction committed instead of rolling back".into()),
    }
}
