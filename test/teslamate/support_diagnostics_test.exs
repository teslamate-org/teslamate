defmodule TeslaMate.SupportDiagnosticsTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log.ChargingProcess
  alias TeslaMate.{Log, Repo, SupportDiagnostics}

  describe "build/0" do
    test "returns a redacted allowlisted support payload" do
      {:ok, car} =
        Log.create_car(%{
          efficiency: 0.153,
          eid: 4242,
          model: "M3",
          name: "Private Vehicle Name",
          vid: 2424,
          vin: "5YJREDACTEDVIN123"
        })

      {:ok, drive} = Log.start_drive(car)

      {:ok, position} =
        Log.insert_position(drive, %{
          date: DateTime.utc_now(),
          latitude: 51.501,
          longitude: -0.141,
          battery_level: 80
        })

      %ChargingProcess{car_id: car.id, position_id: position.id}
      |> ChargingProcess.changeset(%{start_date: DateTime.utc_now()})
      |> Repo.insert!()

      payload = SupportDiagnostics.build()
      encoded = Jason.encode!(payload)

      assert payload["schemaVersion"] == 1
      assert is_binary(payload["generatedAt"])
      assert payload["redaction"]["mode"] == "allowlist"

      assert payload["database"]["status"] == "ok"
      assert payload["database"]["postgres"]["major"] >= 10
      assert payload["database"]["tableCounts"]["cars"] == 1
      assert payload["database"]["tableCounts"]["drives"] == 1
      assert payload["database"]["tableCounts"]["positions"] == 1
      assert payload["database"]["tableCounts"]["chargingProcesses"] == 1
      assert payload["openRecords"] == %{"chargingProcesses" => 1, "drives" => 1}

      assert [
               %{
                 "id" => car_id,
                 "settings" => %{
                   "enabled" => true,
                   "useStreamingApi" => true
                 }
               }
             ] = payload["cars"]

      assert car_id == car.id
      refute encoded =~ "Private Vehicle Name"
      refute encoded =~ "5YJREDACTEDVIN123"
      refute encoded =~ "51.501"
      refute encoded =~ "-0.141"
    end

    test "summarizes configuration without serializing secrets or URLs" do
      previous_mqtt_config = Application.get_env(:teslamate, :mqtt)

      Application.put_env(:teslamate, :mqtt,
        host: "mqtt.internal.example",
        username: "mqtt_user",
        password: "mqtt_password",
        tls: true
      )

      on_exit(fn ->
        if previous_mqtt_config do
          Application.put_env(:teslamate, :mqtt, previous_mqtt_config)
        else
          Application.delete_env(:teslamate, :mqtt)
        end
      end)

      settings = TeslaMate.Settings.get_global_settings!()

      {:ok, _settings} =
        TeslaMate.Settings.update_global_settings(settings, %{
          base_url: "https://teslamate.private.example",
          grafana_url: "https://grafana.private.example"
        })

      payload = SupportDiagnostics.build()
      encoded = Jason.encode!(payload)

      assert payload["settings"]["global"]["baseUrlConfigured"] == true
      assert payload["settings"]["global"]["grafanaUrlConfigured"] == true
      assert payload["runtime"]["mqtt"] == %{"configured" => true, "tls" => true}
      assert payload["runtime"]["import"]["configured"] == false

      refute encoded =~ "mqtt.internal.example"
      refute encoded =~ "mqtt_user"
      refute encoded =~ "mqtt_password"
      refute encoded =~ "teslamate.private.example"
      refute encoded =~ "grafana.private.example"
    end
  end
end
