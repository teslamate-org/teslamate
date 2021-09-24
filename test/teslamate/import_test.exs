defmodule TeslaMate.ImportTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log.{Car, Drive, ChargingProcess, State, Update}
  alias TeslaMate.{Repo, Log, Repair}

  alias TeslaMate.Import.Status
  alias TeslaMate.Import

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
      assert_receive %Status{files: [%{complete: true}], state: :running}, 1500
      assert_receive %Status{files: [%{complete: true}], state: :complete}, 1500

      assert_receive :trigger_run
      assert_receive :trigger_run

      refute_receive _
    end

    assert [] = all(State)
  end

  @tag :capture_log
  test "captures errors of the vehicle process", %{pid: _pid} do
    {:ok, _pid} = start_supervised({Import, directory: "#{@dir}/04_error"})

    assert %Import.Status{files: [_, _, _], message: nil, state: :idle} = Import.get_status()

    assert :ok = Import.subscribe()
    assert :ok = Import.run("Europe/Berlin")

    assert_receive %Status{
                     files: [%{complete: false}, %{complete: false}, %{complete: false}],
                     state: :running
                   },
                   1000

    assert_receive %Status{
                     files: [%{complete: false}, %{complete: false}, %{complete: false}],
                     state: :running
                   },
                   1000

    assert_receive %Status{
                     files: [%{complete: true}, %{complete: false}, %{complete: false}],
                     state: :running
                   },
                   1000

    assert_receive %Status{
                     files: [%{complete: true}, %{complete: true}, %{complete: false}],
                     state: :running
                   },
                   1000

    assert_receive %Status{
                     files: [%{complete: true}, %{complete: true}, %{complete: false}],
                     state: :error,
                     message: msg
                   },
                   1000

    assert {{:badmatch,
             {:error,
              %Ecto.Changeset{
                action: :insert,
                changes: %{date: ~U[2017-12-01 13:36:14.000000Z]},
                errors: [
                  latitude: {"is invalid", [type: :decimal, validation: :cast]},
                  longitude: {"is invalid", [type: :decimal, validation: :cast]}
                ],
                data: %Log.Position{},
                valid?: false
              }}}, [_ | _]} = msg

    refute_receive _
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
end
