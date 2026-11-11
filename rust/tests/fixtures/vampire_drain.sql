-- Fixtures for the vampire-drain comparison test in
-- src/database/queries/vampire_drain.rs. The test runs them in a transaction
-- that it rolls back, so the database is unchanged afterwards.
--
-- Every row has a negative id: real ids come from sequences and are
-- positive, so nothing here can clash with real data. The eids, vids and
-- VINs of the cars are just as impossible for a real car.
--
-- Timeline (UTC) of car -1, the car the test queries: 2024-03-01 08:00 to
-- 2024-03-05 18:00, both ends exactly on an entry, with a minimum duration
-- of 6 hours.
--
--   D0 drive   02-28 10:00-11:00  before the time range, filtered out
--   D1 drive   03-01 08:00-09:00  first entry in the range
--      G1 parked 11 h: a row; asleep 09:30-15:00 and 15:30-19:00 (9 h)
--   C1 charge  03-01 20:00-23:00
--      G2 parked 2 h: shorter than the minimum duration, filtered out
--   D2 drive   03-02 01:00-01:30
--      G3 parked 19 h: the odometer moved 5 km, filtered out
--   D3 drive   03-02 20:30-21:00
--      G4 parked 12 h: the range increased, filtered out
--   C2 charge  03-03 09:00-10:00
--      G5 parked 24 h: a row with reduced range (battery level 93 >
--         usable 90); offline 09:45-12:00 overlaps its start, asleep
--         07:00-10:30 its end (2 h + 3 h)
--   D4 drive   03-04 10:00-10:45
--      G6 parked 24 h: a row; asleep from 11:00 on, still open
--   C3 charge  03-05 10:45-12:00
--      G7 parked exactly 6 h: filtered out, as the minimum is exclusive
--   D5 drive   03-05 18:00-18:30  last entry in the range
--   C4 charge  04-02 10:00-11:00  after the time range, filtered out
--
-- Ideal and rated range move in the same direction everywhere, so both
-- preferred ranges give the same rows with different values.
--
-- Car -2 has a different efficiency, and entries and states inside car -1's
-- parked periods, so a query missing any car filter returns other rows:
--   charge  03-01 12:00-13:00  splits G1 (charges filter)
--   offline 03-01 15:00-15:30  in G1 while car -1 is online (states filter)
--   drive   03-03 18:00-18:30  splits G5 (drives filter)
--   asleep  03-04 00:00-02:00  in G5 while car -1 is online (states filter)
--   efficiency 0.2 instead of 0.153 changes consumption (cars join)

INSERT INTO car_settings (id) VALUES (-1), (-2);

INSERT INTO cars (id, eid, vid, vin, efficiency, settings_id, inserted_at, updated_at)
VALUES
  (-1, -1, -1, 'TESLAMATE-TEST-VAMPIRE-DRAIN-1', 0.153, -1, '2024-01-01', '2024-01-01'),
  (-2, -2, -2, 'TESLAMATE-TEST-VAMPIRE-DRAIN-2', 0.2,   -2, '2024-01-01', '2024-01-01');

INSERT INTO positions (id, car_id, date, latitude, longitude, odometer, battery_level, usable_battery_level)
VALUES
  ( -1, -1, '2024-02-28 10:00', 52.5, 13.4,  970, 80, 80), -- D0 start
  ( -2, -1, '2024-02-28 11:00', 52.5, 13.4, 1000, 75, 75), -- D0 end
  ( -3, -1, '2024-03-01 08:00', 52.5, 13.4, 1000, 75, 75), -- D1 start
  ( -4, -1, '2024-03-01 09:00', 52.5, 13.4, 1030, 70, 70), -- D1 end
  ( -5, -1, '2024-03-01 20:00', 52.5, 13.4, 1030, 65, 65), -- C1
  ( -6, -1, '2024-03-02 01:00', 52.5, 13.4, 1030, 90, 90), -- D2 start
  ( -7, -1, '2024-03-02 01:30', 52.5, 13.4, 1050, 85, 85), -- D2 end
  ( -8, -1, '2024-03-02 20:30', 52.5, 13.4, 1055, 84, 84), -- D3 start
  ( -9, -1, '2024-03-02 21:00', 52.5, 13.4, 1070, 80, 80), -- D3 end
  (-10, -1, '2024-03-03 09:00', 52.5, 13.4, 1070, 78, 78), -- C2
  (-11, -1, '2024-03-04 10:00', 52.5, 13.4, 1070, 93, 90), -- D4 start
  (-12, -1, '2024-03-04 10:45', 52.5, 13.4, 1100, 88, 85), -- D4 end
  (-13, -1, '2024-03-05 10:45', 52.5, 13.4, 1100, 84, 84), -- C3
  (-14, -1, '2024-04-02 10:00', 52.5, 13.4, 1120, 80, 80), -- C4
  (-15, -1, '2024-03-05 18:00', 52.5, 13.4, 1100, 99, 99), -- D5 start
  (-16, -1, '2024-03-05 18:30', 52.5, 13.4, 1120, 96, 96), -- D5 end
  (-21, -2, '2024-03-01 12:00', 48.1, 11.6, 5000, 50, 50), -- car -2 charge
  (-22, -2, '2024-03-03 18:00', 48.1, 11.6, 5000, 60, 60), -- car -2 drive start
  (-23, -2, '2024-03-03 18:30', 48.1, 11.6, 5020, 55, 55); -- car -2 drive end

INSERT INTO drives (id, car_id, start_date, end_date, start_km, end_km,
                    start_ideal_range_km, end_ideal_range_km,
                    start_rated_range_km, end_rated_range_km,
                    start_position_id, end_position_id)
VALUES
  ( -1, -1, '2024-02-28 10:00', '2024-02-28 11:00',  970, 1000, 320, 300, 300, 280,  -1,  -2), -- D0
  ( -2, -1, '2024-03-01 08:00', '2024-03-01 09:00', 1000, 1030, 300, 270, 280, 252,  -3,  -4), -- D1
  ( -3, -1, '2024-03-02 01:00', '2024-03-02 01:30', 1030, 1050, 400, 380, 380, 361,  -6,  -7), -- D2
  ( -4, -1, '2024-03-02 20:30', '2024-03-02 21:00', 1055, 1070, 375, 360, 356, 342,  -8,  -9), -- D3
  ( -5, -1, '2024-03-04 10:00', '2024-03-04 10:45', 1070, 1100, 412, 380, 392, 362, -11, -12), -- D4
  ( -6, -1, '2024-03-05 18:00', '2024-03-05 18:30', 1100, 1120, 447, 430, 427, 410, -15, -16), -- D5
  (-11, -2, '2024-03-03 18:00', '2024-03-03 18:30', 5000, 5020, 300, 280, 290, 270, -22, -23); -- car -2

INSERT INTO charging_processes (id, car_id, position_id, start_date, end_date,
                                start_ideal_range_km, end_ideal_range_km,
                                start_rated_range_km, end_rated_range_km,
                                start_battery_level, end_battery_level)
VALUES
  ( -1, -1,  -5, '2024-03-01 20:00', '2024-03-01 23:00', 266, 400, 248.5, 380, 65,  90), -- C1
  ( -2, -1, -10, '2024-03-03 09:00', '2024-03-03 10:00', 365, 420, 347,   400, 78,  95), -- C2
  ( -3, -1, -13, '2024-03-05 10:45', '2024-03-05 12:00', 377, 450, 359.5, 430, 84, 100), -- C3
  ( -4, -1, -14, '2024-04-02 10:00', '2024-04-02 11:00', 370, 450, 350,   430, 80, 100), -- C4
  (-11, -2, -21, '2024-03-01 12:00', '2024-03-01 13:00', 200, 260, 190,   250, 50,  70); -- car -2

INSERT INTO states (id, car_id, state, start_date, end_date)
VALUES
  ( -1, -1, 'online',  '2024-03-01 08:00', '2024-03-01 09:30'),
  ( -2, -1, 'asleep',  '2024-03-01 09:30', '2024-03-01 15:00'), -- in G1
  ( -3, -1, 'online',  '2024-03-01 15:00', '2024-03-01 15:30'), -- in G1, not counted
  ( -4, -1, 'asleep',  '2024-03-01 15:30', '2024-03-01 19:00'), -- in G1
  ( -5, -1, 'online',  '2024-03-01 19:00', '2024-03-03 09:45'),
  ( -6, -1, 'offline', '2024-03-03 09:45', '2024-03-03 12:00'), -- across the start of G5
  ( -7, -1, 'online',  '2024-03-03 12:00', '2024-03-04 07:00'),
  ( -8, -1, 'asleep',  '2024-03-04 07:00', '2024-03-04 10:30'), -- across the end of G5
  ( -9, -1, 'online',  '2024-03-04 10:30', '2024-03-04 11:00'),
  (-10, -1, 'asleep',  '2024-03-04 11:00', NULL),               -- open, in G6
  (-21, -2, 'offline', '2024-03-01 15:00', '2024-03-01 15:30'), -- in G1, other car
  (-22, -2, 'asleep',  '2024-03-04 00:00', '2024-03-04 02:00'); -- in G5, other car
