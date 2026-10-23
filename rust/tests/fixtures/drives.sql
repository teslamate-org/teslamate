-- Fixtures for tests/drives.rs. The test runs them in a transaction that it
-- rolls back, so the database is unchanged afterwards.
--
-- Every row has a negative id: real ids come from sequences and are
-- positive, so nothing here can clash with real data. The eids, vids and
-- VINs of the cars are just as impossible for a real car.
--
-- The test queries car -1 from 2024-05-01 to 2024-05-31 (UTC). Its drives,
-- with the average speed in km/h:
--
--   id   start        from -> to                 km    min  km/h  notes
--   -10  04-28 08:00  Home -> Work               20     30   40   before the range
--    -1  05-02 08:00  Home -> Work               20     30   40   reduced range in 1 of 4 positions (not > 25 %)
--    -2  05-02 17:00  Work -> Home               22     40   33
--    -3  05-03 09:00  Home -> Bakery             1.5     5   18   no temperature
--    -4  05-03 09:30  Bakery -> Oak Road         12     20   36   reduced range in 2 of 4 positions
--    -5  05-04 10:00  Oak Road -> Gym            80     60   80   steep ascent
--    -6  05-05 12:00  Gym -> (no address)        10     20   30
--    -7  05-06 07:00  (no address) -> Quarry      5     10   30   no range used
--    -8  05-06 08:00  Quarry -> Quarry          0.5      0   45   duration_min 0 (40 s), positions without range
--    -9  05-07 09:00  Main Street -> Main St.  NULL     30        no distance: never listed
--   -11  06-02 10:00  Home -> Home                5     10   30   after the range
--
-- Car -2 (different efficiency) drives Home -> Work on 05-02 12:00 with
-- positions of reduced range, so a query missing a car filter differs.
-- Home, Work and Gym are geofences -11, -12 and -13 (not -1: the dashboard
-- reads a selection of just -1 as its "All" value); the other places only
-- addresses:
-- "Bakery, Shelbyville", "Oak Road, Riverside", "Quarry, Ogdenville",
-- "Main Street 1, Springfield" and one without any part, shown as ''.

INSERT INTO car_settings (id) VALUES (-1), (-2);

INSERT INTO cars (id, eid, vid, vin, efficiency, settings_id, inserted_at, updated_at)
VALUES
  (-1, -1, -1, 'TESLAMATE-TEST-DRIVES-1', 0.153, -1, '2024-01-01', '2024-01-01'),
  (-2, -2, -2, 'TESLAMATE-TEST-DRIVES-2', 0.2,   -2, '2024-01-01', '2024-01-01');

INSERT INTO geofences (id, name, latitude, longitude, inserted_at, updated_at)
VALUES
  (-11, 'Home', 52.520000, 13.405000, '2024-01-01', '2024-01-01'),
  (-12, 'Work', 52.500000, 13.450000, '2024-01-01', '2024-01-01'),
  (-13, 'Gym',  52.480000, 13.300000, '2024-01-01', '2024-01-01');

INSERT INTO addresses (id, name, road, house_number, neighbourhood, city, inserted_at, updated_at)
VALUES
  (-1, NULL,     'Main Street', '1',  NULL,        'Springfield', '2024-01-01', '2024-01-01'),
  (-2, 'Bakery', NULL,          NULL, NULL,        'Shelbyville', '2024-01-01', '2024-01-01'),
  (-3, NULL,     'Oak Road',    NULL, 'Riverside', NULL,          '2024-01-01', '2024-01-01'),
  (-4, NULL,     NULL,          NULL, NULL,        NULL,          '2024-01-01', '2024-01-01'),
  (-5, 'Quarry', NULL,          NULL, NULL,        'Ogdenville',  '2024-01-01', '2024-01-01');

-- drive_id is set at the end, once the drives exist.
INSERT INTO positions (id, car_id, date, latitude, longitude, battery_level, usable_battery_level, ideal_battery_range_km)
VALUES
  (-1001, -1, '2024-04-28 08:00', 52.520000, 13.405000, 82, 82, 310),
  (-1002, -1, '2024-04-28 08:30', 52.500000, 13.450000, 80, 80, 290),
  ( -101, -1, '2024-05-02 08:00', 52.520000, 13.405000, 80, 80, 300),
  ( -102, -1, '2024-05-02 08:10', 52.515000, 13.420000, 79, 79, 293),
  ( -103, -1, '2024-05-02 08:20', 52.510000, 13.435000, 79, 78, 287),
  ( -104, -1, '2024-05-02 08:30', 52.500000, 13.450000, 78, 78, 280),
  ( -201, -1, '2024-05-02 17:00', 52.500000, 13.450000, 78, 78, 400),
  ( -202, -1, '2024-05-02 17:40', 52.520000, 13.405000, 75, 75, 376),
  ( -301, -1, '2024-05-03 09:00', 52.520000, 13.405000, 75, 75, 376),
  ( -302, -1, '2024-05-03 09:05', 52.530000, 13.410000, 74, 74, 374),
  ( -401, -1, '2024-05-03 09:30', 52.530000, 13.410000, 74, 74, 374),
  ( -402, -1, '2024-05-03 09:37', 52.535000, 13.380000, 73, 70, 370),
  ( -403, -1, '2024-05-03 09:44', 52.540000, 13.350000, 72, 69, 366),
  ( -404, -1, '2024-05-03 09:50', 52.545000, 13.320000, 71, 71, 362),
  ( -501, -1, '2024-05-04 10:00', 52.545000, 13.320000, 71, 71, 362),
  ( -502, -1, '2024-05-04 11:00', 52.480000, 13.300000, 60, 60, 290),
  ( -601, -1, '2024-05-05 12:00', 52.480000, 13.300000, 60, 60, 290),
  ( -602, -1, '2024-05-05 12:20', 52.460000, 13.250000, 58, 58, 283),
  ( -701, -1, '2024-05-06 07:00', 52.460000, 13.250000, 58, 58, 283),
  ( -702, -1, '2024-05-06 07:10', 52.440000, 13.200000, 58, 58, 283),
  ( -801, -1, '2024-05-06 08:00', 52.440000, 13.200000, 58, 58, NULL),
  ( -802, -1, '2024-05-06 08:00:40', 52.441000, 13.201000, 57, 57, NULL),
  ( -901, -1, '2024-05-07 09:00', 52.550000, 13.400000, 57, 57, 280),
  ( -902, -1, '2024-05-07 09:30', 52.551000, 13.401000, 56, 56, 278),
  (-1101, -1, '2024-06-02 10:00', 52.520000, 13.405000, 90, 90, 400),
  (-1102, -1, '2024-06-02 10:10', 52.520000, 13.405000, 89, 89, 395),
  (-2101, -2, '2024-05-02 12:00', 52.520000, 13.405000, 50, 40, 250),
  (-2102, -2, '2024-05-02 12:30', 52.500000, 13.450000, 49, 40, 220);

INSERT INTO drives (id, car_id, start_date, end_date, distance, duration_min,
                    start_ideal_range_km, end_ideal_range_km,
                    start_rated_range_km, end_rated_range_km,
                    outside_temp_avg, speed_max, power_max, ascent, descent,
                    start_geofence_id, end_geofence_id,
                    start_address_id, end_address_id,
                    start_position_id, end_position_id)
VALUES
  (-10, -1, '2024-04-28 08:00', '2024-04-28 08:30', 20,   30, 310, 290, 300,   282,   12.0, 100, 120,  10,  10, -11, -12, -1, -1, -1001, -1002),
  ( -1, -1, '2024-05-02 08:00', '2024-05-02 08:30', 20,   30, 300, 280, 290,   272,   10.5, 100, 120,  50,  30, -11, -12, -1, -1,  -101,  -104),
  ( -2, -1, '2024-05-02 17:00', '2024-05-02 17:40', 22,   40, 400, 376, 380,   358,   15.0, 110, 130,  30,  50, -12, -11, -1, -1,  -201,  -202),
  ( -3, -1, '2024-05-03 09:00', '2024-05-03 09:05', 1.5,   5, 376, 374, 358,   356.5, NULL,  40,  40,   0,   0, -11, NULL, -1, -2,  -301,  -302),
  ( -4, -1, '2024-05-03 09:30', '2024-05-03 09:50', 12,   20, 374, 362, 356.5, 345,   -2.5,  60,  70,   5,   5, NULL, NULL, -2, -3,  -401,  -404),
  ( -5, -1, '2024-05-04 10:00', '2024-05-04 11:00', 80,   60, 362, 290, 345,   276,   20.0, 140, 180, 300, 100, NULL, -13, -3, -3,  -501,  -502),
  ( -6, -1, '2024-05-05 12:00', '2024-05-05 12:20', 10,   20, 290, 283, 276,   269.5, 22.5,  70,  90,  20,  40, -13, NULL, -3, -4,  -601,  -602),
  ( -7, -1, '2024-05-06 07:00', '2024-05-06 07:10', 5,    10, 283, 283, 269.5, 269.5, 18.0,  50,  60,   0,   0, NULL, NULL, -4, -5,  -701,  -702),
  ( -8, -1, '2024-05-06 08:00', '2024-05-06 08:00:40', 0.5, 0, 283, 282.5, 269.5, 269, 18.0, 45,  30,   0,   0, NULL, NULL, -5, -5,  -801,  -802),
  ( -9, -1, '2024-05-07 09:00', '2024-05-07 09:30', NULL, 30, 280, 278, 270,   268,   16.0,  60,  50,   0,   0, NULL, NULL, -1, -1,  -901,  -902),
  (-11, -1, '2024-06-02 10:00', '2024-06-02 10:10', 5,    10, 400, 395, 380,   375,   25.0,  60,  50,   0,   0, -11, -11, -1, -1, -1101, -1102),
  (-21, -2, '2024-05-02 12:00', '2024-05-02 12:30', 30,   30, 250, 220, 240,   212,   14.0, 120, 150,  10,  10, -11, -12, -1, -1, -2101, -2102);

-- Position -NNxx belongs to drive -NN.
UPDATE positions SET drive_id = -(abs(id) / 100) WHERE id < 0;
