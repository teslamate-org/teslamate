defmodule TeslaMate.ImportTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log.{Car, Drive, ChargingProcess, Position, State, Update}
  alias TeslaMate.{Repo, Log, Repair}

  alias TeslaMate.Import

  alias TeslaMate.Import.{
    Checkpoint,
    FileCheckpoint,
    RejectedRow,
    Rejection,
    RejectionReport,
    Run,
    Status
  }

  import TestHelper, only: [decimal: 1]
  import Mock

  @dir "./test/fixtures/import"

  setup do
    [pid: self()]
  end

  test "logs drives, charges, states and updates", %{pid: pid} do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/01_complete"})

    assert %Import.Status{files: [f0, f1], message: nil, state: :idle} = Import.get_status()
    assert f0 == %{complete: false, date: [2016, 6], path: "#{@dir}/01_complete/TeslaFi62016.csv"}
    assert f1 == %{complete: false, date: [2016, 7], path: "#{@dir}/01_complete/TeslaFi72016.csv"}

    with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
      assert :ok = Import.subscribe()
      assert :ok = Import.run("America/Los_Angeles")

      for {f0, f1} <- [{false, false}, {false, false}, {true, false}, {true, true}] do
        assert_receive %Status{files: [%{complete: ^f0}, %{complete: ^f1}], state: :running}, 3000
      end

      assert_receive %Status{
                       files: [
                         %{complete: true, date: [2016, 6]},
                         %{complete: true, date: [2016, 7]}
                       ],
                       state: :complete
                     },
                     1000

      assert_receive :trigger_run
      assert_receive :trigger_run
      assert_receive :trigger_run

      refute_receive _
    end

    assert [
             %Car{
               id: car_id,
               name: "82420",
               eid: _random,
               vid: 1_111_111_111,
               vin: "1YYSA1YYYFF08YYYY",
               efficiency: nil,
               model: nil,
               trim_badging: nil,
               settings_id: _
             }
           ] = all(Car)

    assert [
             %Drive{
               car_id: ^car_id,
               distance: 1.2049430000006396,
               duration_min: 3,
               start_date: ~U[2016-06-26 18:12:28.000000Z],
               end_date: ~U[2016-06-26 18:15:28.000000Z],
               start_address_id: nil,
               end_address_id: nil,
               start_geofence_id: nil,
               end_geofence_id: nil,
               start_ideal_range_km: decimal(311.73),
               end_ideal_range_km: decimal(311.73),
               start_km: 22414.090164,
               end_km: 22415.295107,
               start_position_id: _,
               end_position_id: _,
               start_rated_range_km: decimal(247.24),
               end_rated_range_km: decimal(247.24),
               inside_temp_avg: decimal(26.5),
               outside_temp_avg: decimal(19.3),
               power_max: nil,
               power_min: nil,
               speed_max: 55
             },
             %Drive{
               car_id: ^car_id,
               distance: 4.962514999999257,
               duration_min: 12,
               start_date: ~U[2016-06-26 19:22:28.000000Z],
               end_date: ~U[2016-06-26 19:34:09.000000Z],
               start_address_id: nil,
               end_address_id: nil,
               start_geofence_id: nil,
               end_geofence_id: nil,
               start_km: 22415.344102,
               end_km: 22420.306617,
               start_position_id: _,
               end_position_id: _,
               start_rated_range_km: decimal(246.07),
               end_rated_range_km: decimal(239.05),
               start_ideal_range_km: decimal(310.27),
               end_ideal_range_km: decimal(301.41),
               inside_temp_avg: decimal(28.8),
               outside_temp_avg: decimal(20.1),
               power_max: nil,
               power_min: nil,
               speed_max: 58
             }
           ] = all(Drive)

    assert [
             %ChargingProcess{
               car_id: ^car_id,
               charge_energy_added: decimal(10.11),
               charge_energy_used: decimal(10.65),
               address_id: nil,
               cost: nil,
               duration_min: 70,
               start_battery_level: 57,
               end_battery_level: 70,
               start_date: ~U[2016-06-26 23:04:32.000000Z],
               end_date: ~U[2016-06-27 00:14:32.000000Z],
               start_ideal_range_km: decimal(298.44),
               end_ideal_range_km: decimal(369.17),
               start_rated_range_km: decimal(236.69),
               end_rated_range_km: decimal(292.79),
               geofence_id: nil,
               outside_temp_avg: decimal(23.5)
             }
           ] = all(ChargingProcess)

    assert [
             %Update{
               car_id: ^car_id,
               start_date: ~U[2016-06-26 14:59:31.000000Z],
               end_date: ~U[2016-06-26 14:59:31.000000Z],
               version: "2.20.30"
             }
           ] = all(Update)

    assert [
             %State{
               car_id: ^car_id,
               start_date: ~U[2016-06-26 14:59:31.000000Z],
               end_date: ~U[2016-07-01 07:25:33.000000Z],
               state: :online
             },
             %State{
               car_id: ^car_id,
               start_date: ~U[2016-07-01 07:25:33.000000Z],
               end_date: nil,
               state: :asleep
             }
           ] = all(State)
  end

  test "handles overlap", %{pid: pid} do
    {:ok, %Car{id: car_id} = car} =
      Log.create_car(%{
        name: "82420",
        eid: 42,
        vid: 1_111_111_111,
        vin: "1YYSA1YYYFF08YYYY"
      })

    {:ok, _} = Log.start_state(car, :asleep, date: ~U[2016-06-26 19:22:28.000000Z])
    {:ok, _} = Log.start_state(car, :online, date: ~U[2016-06-26 20:00:10.000000Z])

    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/01_complete"})

    assert %Import.Status{files: [f0, f1], message: nil, state: :idle} = Import.get_status()
    assert f0 == %{complete: false, date: [2016, 6], path: "#{@dir}/01_complete/TeslaFi62016.csv"}
    assert f1 == %{complete: false, date: [2016, 7], path: "#{@dir}/01_complete/TeslaFi72016.csv"}

    with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
      assert :ok = Import.subscribe()
      assert :ok = Import.run("America/Los_Angeles")

      for {f0, f1} <- [{false, false}, {false, false}, {true, false}] do
        assert_receive %Status{files: [%{complete: ^f0}, %{complete: ^f1}], state: :running}, 3000
      end

      assert_receive %Status{
                       files: [
                         %{complete: true, date: [2016, 6]},
                         %{complete: false, date: [2016, 7]}
                       ],
                       state: :complete
                     },
                     1000

      assert_receive :trigger_run
      assert_receive :trigger_run

      refute_receive _
    end

    assert [
             %Drive{
               car_id: ^car_id,
               duration_min: 3,
               start_date: ~U[2016-06-26 18:12:28.000000Z],
               end_date: ~U[2016-06-26 18:15:28.000000Z]
             }
           ] = all(Drive)

    assert [] = all(ChargingProcess)

    assert [
             %Update{
               car_id: ^car_id,
               start_date: ~U[2016-06-26 14:59:31.000000Z],
               end_date: ~U[2016-06-26 14:59:31.000000Z],
               version: "2.20.30"
             }
           ] = all(Update)

    assert [
             %State{
               car_id: ^car_id,
               start_date: ~U[2016-06-26 19:22:28.000000Z],
               end_date: ~U[2016-06-26 20:00:10.000000Z],
               state: :asleep
             },
             %State{
               car_id: ^car_id,
               start_date: ~U[2016-06-26 20:00:10.000000Z],
               end_date: nil,
               state: :online
             },
             %State{
               car_id: ^car_id,
               start_date: ~U[2016-06-26 14:59:31.000000Z],
               end_date: ~U[2016-06-26 19:22:28.000000Z],
               state: :online
             }
           ] = all(State)
  end

  describe "uses the locale time zone" do
    test "America/Los_Angeles", %{pid: pid} do
      {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/02_timezone"})

      assert %Import.Status{files: [f], message: nil, state: :idle} = Import.get_status()

      assert f == %{
               complete: false,
               date: [2019, 9],
               path: "#{@dir}/02_timezone/TeslaFi92019.csv"
             }

      with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
        assert :ok = Import.subscribe()
        assert :ok = Import.run("America/Los_Angeles")

        assert_receive %Status{files: [%{complete: false}], state: :running}, 3000
        assert_receive %Status{files: [%{complete: false}], state: :running}, 3000
        assert_receive %Status{files: [%{complete: true}], state: :running}, 3000
        assert_receive %Status{files: [%{complete: true}], state: :complete}, 3000

        assert_receive :trigger_run
        assert_receive :trigger_run

        refute_receive _
      end

      assert [
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 10:18:11.000000Z],
                 end_date: ~U[2019-09-01 15:55:12.000000Z],
                 state: :asleep
               },
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 15:55:12.000000Z],
                 end_date: ~U[2019-09-01 22:49:11.000000Z],
                 state: :online
               },
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 22:49:11.000000Z],
                 end_date: ~U[2019-09-01 23:34:12.000000Z],
                 state: :asleep
               },
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 23:34:12.000000Z],
                 end_date: nil,
                 state: :online
               }
             ] = all(State)

      assert [] = all(Drive)
      assert [] = all(ChargingProcess)
    end

    test "Europe/Berlin", %{pid: pid} do
      {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/02_timezone"})

      assert %Import.Status{files: [f], message: nil, state: :idle} = Import.get_status()

      assert f == %{
               complete: false,
               date: [2019, 9],
               path: "#{@dir}/02_timezone/TeslaFi92019.csv"
             }

      with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
        assert :ok = Import.subscribe()
        assert :ok = Import.run("Europe/Berlin")

        assert_receive %Status{files: [%{complete: false}], state: :running}, 1000
        assert_receive %Status{files: [%{complete: false}], state: :running}, 1000
        assert_receive %Status{files: [%{complete: true}], state: :running}, 10000
        assert_receive %Status{files: [%{complete: true}], state: :complete}, 1000

        assert_receive :trigger_run
        assert_receive :trigger_run

        refute_receive _
      end

      assert [
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 01:18:11.000000Z],
                 end_date: ~U[2019-09-01 06:55:12.000000Z],
                 state: :asleep
               },
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 06:55:12.000000Z],
                 end_date: ~U[2019-09-01 13:49:11.000000Z],
                 state: :online
               },
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 13:49:11.000000Z],
                 end_date: ~U[2019-09-01 14:34:12.000000Z],
                 state: :asleep
               },
               %State{
                 car_id: car_id,
                 start_date: ~U[2019-09-01 14:34:12.000000Z],
                 end_date: nil,
                 state: :online
               }
             ] = all(State)

      assert [] = all(Drive)
      assert [] = all(ChargingProcess)
    end

    test "DST change", %{pid: pid} do
      {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/05_dst"})

      assert %Import.Status{files: [f], message: nil, state: :idle} = Import.get_status()

      assert f == %{
               complete: false,
               date: [2019, 10],
               path: "#{@dir}/05_dst/TeslaFi102019.csv"
             }

      with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
        assert :ok = Import.subscribe()
        assert :ok = Import.run("Europe/Berlin")

        assert_receive %Status{files: [%{complete: false}], state: :running}, 1000
        assert_receive %Status{files: [%{complete: false}], state: :running}, 1000
        assert_receive %Status{files: [%{complete: true}], state: :running}, 10000
        assert_receive %Status{files: [%{complete: true}], state: :complete}, 1000

        assert_receive :trigger_run
        assert_receive :trigger_run

        refute_receive _
      end

      assert [
               %TeslaMate.Log.State{
                 car_id: car_id,
                 start_date: ~U[2019-10-26 23:30:40.000000Z],
                 end_date: ~U[2019-10-27 02:14:44.000000Z],
                 state: :asleep
               },
               %TeslaMate.Log.State{
                 car_id: car_id,
                 start_date: ~U[2019-10-27 02:14:44.000000Z],
                 end_date: nil,
                 state: :online
               }
             ] = all(State)

      assert [] = all(Drive)
      assert [] = all(ChargingProcess)
    end
  end

  test "car war permanently unreachable", %{pid: pid} do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/03_empty"})

    assert %Import.Status{files: [f0, f1], message: nil, state: :idle} = Import.get_status()
    assert f0 == %{complete: false, date: [2018, 5], path: "#{@dir}/03_empty/TeslaFi52018.csv"}
    assert f1 == %{complete: false, date: [2018, 6], path: "#{@dir}/03_empty/TeslaFi62018.csv"}

    with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
      assert :ok = Import.subscribe()
      assert :ok = Import.run("Europe/Berlin")

      {t, f} = {true, false}
      assert_receive %Status{files: [%{complete: ^f}, %{complete: ^f}], state: :running}, 1500
      assert_receive %Status{files: [%{complete: ^f}, %{complete: ^f}], state: :running}, 1500
      assert_receive %Status{files: [%{complete: ^t}, %{complete: ^f}], state: :running}, 1500
      assert_receive %Status{files: [%{complete: ^t}, %{complete: ^t}], state: :running}, 1500
      assert_receive %Status{files: [%{complete: ^t}, %{complete: ^t}], state: :complete}, 1500

      assert_receive :trigger_run
      assert_receive :trigger_run
      assert_receive :trigger_run

      refute_receive _
    end

    assert [
             %State{
               car_id: car_id,
               end_date: ~U[2018-06-01 05:27:14.000000Z],
               start_date: ~U[2018-04-30 22:00:14.000000Z],
               state: :asleep
             },
             %State{
               car_id: car_id,
               start_date: ~U[2018-06-01 05:27:14.000000Z],
               end_date: nil,
               state: :online
             }
           ] = all(State)

    assert [] = all(Drive)
    assert [] = all(ChargingProcess)
  end

  @tag :capture_log
  test "detects if file contains data for more than one car", %{pid: pid} do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/06_two_cars"})

    assert %Import.Status{files: [f0], message: nil, state: :idle} = Import.get_status()
    assert f0 == %{complete: false, date: [2020, 6], path: "#{@dir}/06_two_cars/TeslaFi62020.csv"}

    with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
      assert :ok = Import.subscribe()
      assert :ok = Import.run("America/New_York")

      assert_receive %Status{files: [%{complete: false}], state: :running}, 1500
      assert_receive %Status{files: [%{complete: false}], state: :running}, 1500

      assert_receive %Status{
                       files: [%{complete: false}],
                       state: :error,
                       message: :vehicle_changed
                     },
                     1500

      refute Process.whereis(:"api_Car-A")
      refute Process.whereis(:"import_Car-A")

      refute_receive _
    end

    assert [] = all(State)
  end

  @tag :capture_log
  test "accepts newer teslafi format where vin and id may not be defined", %{pid: pid} do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/07_alternative_variant"})

    assert %Import.Status{files: [f], message: nil, state: :idle} = Import.get_status()

    assert f == %{
             complete: false,
             date: [2023, 11],
             path: "#{@dir}/07_alternative_variant/112023.csv"
           }

    with_mock Repair, trigger_run: fn -> ok_fn(:trigger_run, pid) end do
      assert :ok = Import.subscribe()
      assert :ok = Import.run("America/Los_Angeles")

      assert_receive %Status{files: [%{complete: false}], state: :running}, 3000
      assert_receive %Status{files: [%{complete: false}], state: :running}, 3000
      assert_receive %Status{files: [%{complete: true}], state: :running}, 3000
      assert_receive %Status{files: [%{complete: true}], state: :complete}, 3000

      assert_receive :trigger_run
      assert_receive :trigger_run

      refute_receive _
    end
  end

  @tag :capture_log
  test "continues after a malformed row and reports it once", %{pid: _pid} do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/08_resilient"})

    with_mock Repair, trigger_run: fn -> :ok end do
      assert :ok = Import.run("Etc/UTC")

      TestHelper.eventually(
        fn ->
          assert %Status{
                   state: :complete,
                   rejected_rows: 1,
                   rejection_examples: [
                     %Import.RejectedRow{
                       file: "TeslaFi12018.csv",
                       row: 3,
                       reason: :invalid_fields,
                       fields: fields
                     }
                   ]
                 } = Import.get_status()

          assert "drive_state.latitude" in fields
          assert "drive_state.longitude" in fields
        end,
        delay: 50,
        attempts: 100
      )
    end

    positions = all(Position)
    assert Enum.any?(positions, &(&1.date == ~U[2018-01-01 10:02:00.000000Z]))
    refute Enum.any?(positions, &(&1.date == ~U[2018-01-01 10:01:00.000000Z]))
    refute inspect(Import.get_status()) =~ "PRIVATE_COORDINATE_SENTINEL"

    assert %Rejection{
             file_name: "TeslaFi12018.csv",
             file_fingerprint: fingerprint,
             row: 3,
             reason: :invalid_fields,
             fields: fields
           } = Repo.one!(Rejection)

    assert byte_size(fingerprint) == 64
    assert "drive_state.latitude" in fields
    assert "drive_state.longitude" in fields
    refute inspect(Repo.one!(Rejection)) =~ "PRIVATE_COORDINATE_SENTINEL"
    refute inspect(Repo.one!(Rejection)) =~ @dir

    assert %FileCheckpoint{
             file_name: "TeslaFi12018.csv",
             file_fingerprint: ^fingerprint
           } = Repo.one!(FileCheckpoint)
  end

  @tag :capture_log
  test "reports deterministic row errors when no complete vehicle row remains", %{
    pid: _pid
  } do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/04_error"})

    assert %Import.Status{files: [_, _, _], message: nil, state: :idle} = Import.get_status()

    with_mock Repair, trigger_run: fn -> :ok end do
      assert :ok = Import.run("Europe/Berlin")

      TestHelper.eventually(
        fn ->
          assert %Status{
                   files: [
                     %{complete: false},
                     %{complete: false},
                     %{complete: false}
                   ],
                   state: :error,
                   message: :vehicle_data_incomplete,
                   rejected_rows: 4,
                   rejection_examples: examples
                 } = Import.get_status()

          assert length(examples) == 4
          assert Enum.map(examples, & &1.row) == [2, 3, 4, 5]
          assert Process.alive?(Process.whereis(Import))
        end,
        delay: 50,
        attempts: 100
      )
    end
  end

  test "tracks completion by file identity when dates match" do
    first = "/import/012018.csv"
    second = "/import/TeslaFi12018.csv"

    data = %Import{
      files: [
        %{date: [2018, 1], path: first, fingerprint: "first-fingerprint"},
        %{date: [2018, 1], path: second, fingerprint: "second-fingerprint"}
      ],
      completed: MapSet.new([{"012018.csv", "first-fingerprint"}])
    }

    assert %Status{files: [%{complete: true}, %{complete: false}]} =
             Status.into(:running, data)
  end

  @tag :capture_log
  test "quarantines a conflicting VIN without rejecting fallback vehicle IDs" do
    {:ok, _pid} =
      start_supervised({Import, directory: "#{@dir}/09_identity_conflicts"})

    with_mock Repair, trigger_run: fn -> :ok end do
      assert :ok = Import.run("Etc/UTC")

      TestHelper.eventually(
        fn ->
          assert %Status{
                   state: :complete,
                   rejected_rows: 1,
                   rejection_examples: [
                     %RejectedRow{row: 4, fields: ["vin"]}
                   ]
                 } = Import.get_status()
        end,
        delay: 50,
        attempts: 100
      )
    end

    position_dates = Position |> all() |> Enum.map(& &1.date)

    assert ~U[2018-01-01 10:01:00.000000Z] in position_dates
    assert ~U[2018-01-01 10:03:00.000000Z] in position_dates
    assert ~U[2018-01-01 10:04:00.000000Z] in position_dates
    refute ~U[2018-01-01 10:02:00.000000Z] in position_dates
  end

  test "filters rejection reports by exact file identities" do
    {:ok, run} = Checkpoint.start_run(Checkpoint.source_key(tmp_import_dir!()), "Etc/UTC")

    assert :inserted =
             Checkpoint.record_rejection(
               run.id,
               RejectedRow.new("first.csv", 2, :parse_error, [], "fingerprint-1")
             )

    assert :inserted =
             Checkpoint.record_rejection(
               run.id,
               RejectedRow.new("second.csv", 3, :parse_error, [], "fingerprint-2")
             )

    assert :inserted =
             Checkpoint.record_rejection(
               run.id,
               RejectedRow.new("first.csv", 4, :parse_error, [], "fingerprint-2")
             )

    assert %RejectionReport{count: 2, examples: examples} =
             Checkpoint.rejection_report(run.id, [
               {"first.csv", "fingerprint-1"},
               {"second.csv", "fingerprint-2"}
             ])

    assert Enum.map(examples, &{&1.file, &1.row}) == [{"first.csv", 2}, {"second.csv", 3}]
  end

  @tag :capture_log
  test "reports a file error between car discovery and import startup" do
    directory = tmp_import_dir!()
    name = "TeslaFi12018.csv"
    path = Path.join(directory, name)
    File.cp!(Path.join([@dir, "08_resilient", name]), path)

    {:ok, import} = start_supervised({Import, directory: directory})

    with_mock Checkpoint, [:passthrough],
      set_car: fn run_id, car_id ->
        result = passthrough([run_id, car_id])
        File.write!(path, "unsupported delimiter\nsecond row\n")
        result
      end do
      assert :ok = Import.run("Etc/UTC")

      TestHelper.eventually(
        fn ->
          assert %Status{
                   state: :error,
                   message: %RuntimeError{message: "Unsupported delimiter"}
                 } = Import.get_status()

          assert Process.alive?(import)
        end,
        delay: 50,
        attempts: 100
      )
    end
  end

  test "restores an interrupted run with its saved timezone and imports the remaining file" do
    directory = tmp_import_dir!()
    first_name = "TeslaFi62016.csv"
    second_name = "TeslaFi72016.csv"

    File.cp!(Path.join([@dir, "01_complete", first_name]), Path.join(directory, first_name))
    File.cp!(Path.join([@dir, "01_complete", second_name]), Path.join(directory, second_name))

    first_path = Path.join(directory, first_name)
    {:ok, fingerprint} = Checkpoint.file_fingerprint(first_path)
    {:ok, run} = Checkpoint.start_run(Checkpoint.source_key(directory), "America/Los_Angeles")
    :ok = Checkpoint.complete_file(run.id, {first_name, fingerprint})

    {:ok, _pid} = start_supervised({Import, directory: directory})

    assert %Status{
             state: :idle,
             resume_timezone: "America/Los_Angeles",
             files: [
               %{path: ^first_path, complete: true},
               %{path: second_path, complete: false}
             ]
           } = Import.get_status()

    assert second_path == Path.join(directory, second_name)

    with_mock Repair, trigger_run: fn -> :ok end do
      assert :ok = Import.run("Europe/Berlin")

      TestHelper.eventually(
        fn ->
          assert %Status{state: :complete, files: [%{complete: true}, %{complete: true}]} =
                   Import.get_status()
        end,
        delay: 50,
        attempts: 100
      )
    end

    assert [%Run{status: :complete, timezone: "America/Los_Angeles"}] = Repo.all(Run)

    positions = all(Position)
    assert positions != []

    assert Enum.all?(positions, fn position ->
             DateTime.compare(position.date, ~U[2016-07-01 00:00:00Z]) != :lt
           end)
  end

  test "does not restore a completed checkpoint after the file changes" do
    directory = tmp_import_dir!()
    name = "TeslaFi12018.csv"
    path = Path.join(directory, name)
    File.cp!(Path.join([@dir, "08_resilient", name]), path)

    {:ok, old_fingerprint} = Checkpoint.file_fingerprint(path)
    {:ok, run} = Checkpoint.start_run(Checkpoint.source_key(directory), "Etc/UTC")
    :ok = Checkpoint.complete_file(run.id, {name, old_fingerprint})

    File.write!(path, "\n", [:append])
    {:ok, new_fingerprint} = Checkpoint.file_fingerprint(path)
    refute new_fingerprint == old_fingerprint

    {:ok, _pid} = start_supervised({Import, directory: directory})

    assert %Status{state: :idle, files: [%{path: ^path, complete: false}]} =
             Import.get_status()
  end

  test "discards an interrupted run and permits a fresh run" do
    directory = tmp_import_dir!()
    name = "TeslaFi12018.csv"
    path = Path.join(directory, name)
    File.cp!(Path.join([@dir, "08_resilient", name]), path)

    source_key = Checkpoint.source_key(directory)
    {:ok, fingerprint} = Checkpoint.file_fingerprint(path)
    {:ok, run} = Checkpoint.start_run(source_key, "America/Los_Angeles")
    :ok = Checkpoint.complete_file(run.id, {name, fingerprint})

    assert :inserted =
             Checkpoint.record_rejection(
               run.id,
               RejectedRow.new(path, 3, :parse_error, [], fingerprint)
             )

    {:ok, _pid} = start_supervised({Import, directory: directory})

    assert %Status{
             state: :idle,
             resume_timezone: "America/Los_Angeles",
             rejected_rows: 1,
             files: [%{complete: true}]
           } = Import.get_status()

    assert :ok = Import.discard_interrupted_run()

    assert %Status{
             state: :idle,
             resume_timezone: nil,
             rejected_rows: 0,
             files: [%{complete: false}]
           } = Import.get_status()

    assert %Run{status: :abandoned} = Repo.get!(Run, run.id)
    assert Checkpoint.get_active_run(source_key) == nil

    assert {:ok, %Run{timezone: "Etc/UTC"} = new_run} =
             Checkpoint.start_run(source_key, "Etc/UTC")

    assert Repo.get(Run, run.id) == nil
    assert Repo.get!(Run, new_run.id).status == :running
  end

  test "restores the last completed rejection report after restart" do
    directory = tmp_import_dir!()
    name = "TeslaFi12018.csv"
    path = Path.join(directory, name)
    File.cp!(Path.join([@dir, "08_resilient", name]), path)

    {:ok, fingerprint} = Checkpoint.file_fingerprint(path)
    {:ok, run} = Checkpoint.start_run(Checkpoint.source_key(directory), "Etc/UTC")

    assert :inserted =
             Checkpoint.record_rejection(
               run.id,
               RejectedRow.new(path, 3, :parse_error, [], fingerprint)
             )

    :ok = Checkpoint.complete_run(run.id)
    {:ok, _pid} = start_supervised({Import, directory: directory})

    assert %Status{
             state: :idle,
             resume_timezone: nil,
             rejected_rows: 1,
             rejection_examples: [%RejectedRow{file: ^name, row: 3}]
           } = Import.get_status()
  end

  test "rejects an empty import without creating a run" do
    directory = tmp_import_dir!()
    {:ok, _pid} = start_supervised({Import, directory: directory})

    assert {:error, :no_files} = Import.run("Etc/UTC")
    assert Repo.aggregate(Run, :count) == 0
    assert %Status{state: :idle, files: []} = Import.get_status()
  end

  test "returns a safe error when a source already has an active run" do
    source_key = Checkpoint.source_key(tmp_import_dir!())

    assert {:ok, %Run{}} = Checkpoint.start_run(source_key, "Etc/UTC")
    assert {:error, %Ecto.Changeset{} = changeset} = Checkpoint.start_run(source_key, "Etc/UTC")
    assert {"has already been taken", _metadata} = changeset.errors[:source_key]
  end

  @tag :capture_log
  test "captures a runtime failure inside the vehicle process" do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/01_complete"})

    with_mock Repair, trigger_run: fn -> :ok end do
      with_mock Log, [:passthrough],
        insert_position: fn _car_or_drive, _attrs ->
          raise "injected position insert failure"
        end do
        assert :ok = Import.run("America/Los_Angeles")

        TestHelper.eventually(
          fn ->
            assert %Status{state: :error, message: message} = Import.get_status()
            assert inspect(message) =~ "injected position insert failure"
            assert Process.alive?(Process.whereis(Import))
            refute Process.whereis(:api_82420)
            refute Process.whereis(:import_82420)
          end,
          delay: 50,
          attempts: 100
        )
      end
    end
  end

  defp ok_fn(name, pid) do
    send(pid, name)
    :ok
  end

  defp all(struct) do
    struct
    |> order_by(:id)
    |> Repo.all()
  end

  defp tmp_import_dir! do
    directory =
      Path.join(
        System.tmp_dir!(),
        "teslamate-import-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    directory
  end
end
