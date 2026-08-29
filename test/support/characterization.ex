defmodule TeslaMate.Characterization do
  @moduledoc """
  Characterization harness (#5652): replays a recorded sequence of Tesla API
  payloads through the regular `Vehicle` boundary and captures what leaves the
  system — persisted rows and published MQTT messages. No mock call assertions;
  the golden file is the observed outer behaviour.

  ## Fixture format (`test/fixtures/characterization/<name>.json`)

      {
        "description": "...",
        "car": {"eid": 42, "vid": 1000, "vin": "...", "model": "3", "efficiency": 0.153},
        "settings": {"use_streaming_api": false, "suspend_after_idle_min": 999999},
        "events": [
          {"vehicle": {<raw Tesla API JSON, decoded by TeslaApi.Vehicle.result/1>}},
          {"error": "vehicle_unavailable"}
        ]
      }

  Events are served in order by `ApiMock`; the last event repeats for any
  further fetch, so every fixture must end in a repeat-neutral terminal state
  (parked online, asleep or offline — never mid-drive, never charging).

  The replay end is event-driven, never a wait: after the last event has been
  served, the harness waits for exactly one more serve of the repeating
  terminal event. The state machine starting that next cycle proves the
  previous cycle — including all of its persistence and publishing effects —
  has completed. Scenarios whose outcome depends on timers that fire after
  the last event are not expressible yet; the mechanism for awaiting a
  declared outcome is decided in the conversion PRs, where such scenarios
  first appear.

  The expected outer behaviour lives next to the fixture as
  `<name>.expected.json` and is written by running with
  `CHARACTERIZATION_RECORD=1`. Recording replays the fixture twice and masks
  every value that differs between the two runs as `"<volatile>"` (wall-clock
  driven values); comparison accepts any value where the golden says
  `"<volatile>"`. MQTT payloads are compared per topic with consecutive
  duplicates collapsed, because cross-topic publish order is concurrent by
  design (`Task.async_stream(ordered: false)`).

  Goldens contain only canonical representations: payloads that are JSON
  objects or arrays are stored decoded and compared structurally (the key
  order of an encoded map is not portable across runtimes), and golden files
  are written with sorted keys — a recorded file is byte-identical no matter
  which machine recorded it.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised: 1, stop_supervised: 1]

  alias TeslaMate.Mqtt.PubSub.VehicleSubscriber
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.{Log, Repo}

  @fixtures_dir Path.expand("../fixtures/characterization", __DIR__)
  @volatile "<volatile>"

  @db_tables ~w(cars car_settings states positions drives charging_processes charges updates
                addresses geofences)

  @singular %{
    "cars" => "car",
    "car_settings" => "car_setting",
    "states" => "state",
    "positions" => "position",
    "drives" => "drive",
    "charging_processes" => "charging_process",
    "charges" => "charge",
    "updates" => "update",
    "addresses" => "address",
    "geofences" => "geofence"
  }

  # Wall-clock columns with second granularity: a double-run diff can miss
  # them when both runs fall into the same second, so they are always masked.
  @always_volatile_columns ~w(inserted_at updated_at)

  # MQTT topics whose payload is wall-clock derived (state change timestamps).
  @always_volatile_topics ~w(since)

  def fixtures_dir, do: @fixtures_dir

  # Presence alone is not consent: CHARACTERIZATION_RECORD=0 must compare,
  # not silently record and report green.
  defp record?, do: System.get_env("CHARACTERIZATION_RECORD") in ~w(1 true)

  def fixture_files do
    @fixtures_dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, ".expected.json"))
    |> Enum.sort()
  end

  def run(fixture_path) do
    input = fixture_path |> File.read!() |> Jason.decode!()
    expected_path = String.replace_suffix(fixture_path, ".json", ".expected.json")

    if record?() do
      first = replay(input, :record_1)
      reset_db()
      second = replay(input, :record_2)
      golden = mask_volatile(first, second)

      for {section, name} <- [{"database", "table"}, {"mqtt", "topic"}],
          {key, value} <- golden[section],
          value == @volatile do
        raise "#{name} #{key} differs structurally between the two record runs — " <>
                "the fixture is not repeat-neutral (see moduledoc); refusing to record " <>
                "a fully masked golden for #{Path.basename(fixture_path)}"
      end

      File.write!(expected_path, Jason.encode!(canonical_order(golden), pretty: true) <> "\n")
      IO.puts("recorded #{Path.basename(expected_path)}")
    else
      assert File.exists?(expected_path),
             "missing golden #{Path.basename(expected_path)} — " <>
               "record it with CHARACTERIZATION_RECORD=1 mix test"

      expected = expected_path |> File.read!() |> Jason.decode!()
      actual = replay(input, :compare)
      assert_equivalent(expected, actual, Path.basename(fixture_path))
    end
  end

  ## Replay

  defp replay(input, run_id) do
    car = create_car(input)
    events = build_events(input)
    collector = self()
    total = length(events)

    wrapped =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {result, index} ->
        fn ->
          send(collector, {:api_event_served, index})
          result
        end
      end)

    api = :"characterization_api_#{run_id}"
    settings = :"characterization_settings_#{run_id}"
    vehicles = :"characterization_vehicles_#{run_id}"
    locations = :"characterization_locations_#{run_id}"
    publisher = :"characterization_publisher_#{run_id}"
    vehicle = :"characterization_vehicle_#{run_id}"

    children = [
      {ApiMock, name: api, events: wrapped, pid: collector},
      {SettingsMock, name: settings, pid: collector},
      {VehiclesMock, name: vehicles, pid: collector},
      {LocationsMock, name: locations, pid: collector},
      {MqttPublisherMock, name: publisher, pid: collector}
    ]

    for child <- children do
      {:ok, _} = start_supervised(with_run_id(child, run_id))
    end

    {:ok, subscriber} =
      start_supervised(
        {VehicleSubscriber,
         car_id: car.id, deps_publisher: {MqttPublisherMock, publisher}, discovery: false}
      )

    vehicle_spec =
      with_run_id(
        {Vehicle,
         name: vehicle,
         car: car,
         deps_api: {ApiMock, api},
         deps_settings: {SettingsMock, settings},
         deps_vehicles: {VehiclesMock, vehicles},
         deps_locations: {LocationsMock, locations}},
        run_id
      )

    {:ok, _} = start_supervised(vehicle_spec)

    assert_receive {:api_event_served, ^total}, 5_000

    # Causal barrier, not a wait: the terminal event repeats, so its next
    # serve proves the state machine finished the previous cycle — including
    # every persistence and publishing effect — and started the next one.
    assert_receive {:api_event_served, ^total}, 5_000

    :ok = stop_supervised(vehicle_spec.id)
    :sys.get_state(subscriber)
    :ok = stop_supervised(:"#{VehicleSubscriber}#{car.id}")

    mqtt = drain_mqtt(%{}, car)
    flush_notifications()

    %{"database" => dump_db(car), "mqtt" => mqtt}
  end

  defp with_run_id({module, _opts} = child, run_id) do
    Supervisor.child_spec(child, id: {module, run_id})
  end

  defp create_car(input) do
    car_attrs =
      input
      |> Map.fetch!("car")
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    {:ok, car} = Log.create_car(car_attrs)

    settings_attrs =
      input
      |> Map.get("settings", %{})
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    car = Repo.preload(car, :settings)

    {:ok, settings} =
      car.settings
      |> Ecto.Changeset.change(settings_attrs)
      |> Repo.update()

    %{car | settings: settings}
  end

  defp build_events(%{"events" => [_ | _] = events}) do
    Enum.map(events, fn
      %{"vehicle" => raw} -> {:ok, TeslaApi.Vehicle.result(raw)}
      %{"error" => reason} -> {:error, String.to_existing_atom(reason)}
    end)
  end

  ## Capture

  defp drain_mqtt(acc, car) do
    receive do
      {MqttPublisherMock, {:publish, topic, payload, _opts}} ->
        topic =
          topic
          |> String.replace("/cars/#{car.id}", "/cars/$car")
          |> String.replace("teslamate_#{car.id}", "teslamate_$car")

        payload = canonical_payload(to_string(payload))
        acc = Map.update(acc, topic, [payload], &[payload | &1])
        drain_mqtt(acc, car)
    after
      0 ->
        Map.new(acc, fn {topic, values} ->
          values = Enum.reverse(values)

          if Path.basename(topic) in @always_volatile_topics do
            {topic, Enum.map(values, fn _ -> @volatile end)}
          else
            {topic, Enum.dedup(values)}
          end
        end)
    end
  end

  # A payload that is a JSON object or array is stored decoded: the key order
  # of an encoded map is not a portable representation (it differs between
  # runtimes), so goldens hold the structure, never the byte sequence. Scalar
  # payloads ("80", "true", plain strings) stay untouched.
  defp canonical_payload("{" <> _ = payload), do: decode_or_keep(payload)
  defp canonical_payload("[" <> _ = payload), do: decode_or_keep(payload)
  defp canonical_payload(payload), do: payload

  defp decode_or_keep(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> decoded
      {:error, _} -> payload
    end
  end

  defp flush_notifications do
    receive do
      {mock, _} when mock in [ApiMock, SettingsMock, VehiclesMock, LocationsMock] ->
        flush_notifications()

      {:api_event_served, _} ->
        flush_notifications()

      {:"$websockex_cast", _} ->
        flush_notifications()
    after
      0 -> :ok
    end
  end

  defp dump_db(car) do
    raw =
      Map.new(@db_tables, fn table ->
        %{columns: columns, rows: rows} = Repo.query!("SELECT * FROM #{table} ORDER BY id")
        {table, Enum.map(rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)}
      end)

    id_map = build_id_map(raw)

    Map.new(raw, fn {table, rows} ->
      {table, Enum.map(rows, &canonicalize_row(&1, table, id_map, car.id))}
    end)
  end

  defp build_id_map(raw) do
    for {table, rows} <- raw, {row, index} <- Enum.with_index(rows, 1), into: %{} do
      {{table, row["id"]}, "#{Map.fetch!(@singular, table)}_#{index}"}
    end
  end

  @fk_tables %{
    "settings_id" => "car_settings",
    "drive_id" => "drives",
    "charging_process_id" => "charging_processes",
    "position_id" => "positions",
    "start_position_id" => "positions",
    "end_position_id" => "positions",
    "start_address_id" => "addresses",
    "end_address_id" => "addresses",
    "address_id" => "addresses",
    "start_geofence_id" => "geofences",
    "end_geofence_id" => "geofences",
    "geofence_id" => "geofences"
  }

  defp canonicalize_row(row, table, id_map, car_id) do
    Map.new(row, fn
      {"id", id} when table == "cars" ->
        {"id", if(id == car_id, do: "$car", else: Map.fetch!(id_map, {table, id}))}

      {"id", id} ->
        {"id", Map.fetch!(id_map, {table, id})}

      {"car_id", id} ->
        {"car_id", if(id == car_id, do: "$car", else: id)}

      {column, _value} when column in @always_volatile_columns ->
        {column, @volatile}

      {column, value} when is_map_key(@fk_tables, column) ->
        case value do
          nil -> {column, nil}
          id -> {column, Map.fetch!(id_map, {Map.fetch!(@fk_tables, column), id})}
        end

      {column, value} ->
        {column, to_jsonable(value)}
    end)
  end

  defp to_jsonable(%Decimal{} = d), do: Decimal.to_string(d)
  defp to_jsonable(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_jsonable(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp to_jsonable(value), do: value

  defp reset_db do
    Repo.query!("TRUNCATE cars, car_settings, addresses, geofences CASCADE")
  end

  # Golden files are written with sorted keys throughout, so a recorded file
  # is byte-identical regardless of the machine that recorded it.
  defp canonical_order(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical_order(value)} end)
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Jason.OrderedObject.new()
  end

  defp canonical_order(list) when is_list(list), do: Enum.map(list, &canonical_order/1)
  defp canonical_order(value), do: value

  ## Golden: record & compare

  defp mask_volatile(first, second) when is_map(first) and is_map(second) do
    keys = Enum.uniq(Map.keys(first) ++ Map.keys(second))

    Map.new(keys, fn key ->
      {key, mask_volatile(Map.get(first, key, :__missing__), Map.get(second, key, :__missing__))}
    end)
  end

  defp mask_volatile(first, second) when is_list(first) and is_list(second) do
    if length(first) == length(second) do
      Enum.zip_with(first, second, &mask_volatile/2)
    else
      @volatile
    end
  end

  defp mask_volatile(value, value), do: value
  defp mask_volatile(_first, _second), do: @volatile

  defp assert_equivalent(expected, actual, name) do
    case diff(expected, actual, []) do
      nil ->
        :ok

      {path, exp, act} ->
        flunk("""
        characterization mismatch in #{name}
        first divergence at #{Enum.join(Enum.reverse(path), ".")}
        expected: #{inspect(exp)}
        actual:   #{inspect(act)}
        """)
    end
  end

  defp diff(@volatile, _actual, _path), do: nil

  defp diff(expected, actual, path) when is_map(expected) and is_map(actual) do
    keys = Enum.uniq(Map.keys(expected) ++ Map.keys(actual))

    Enum.find_value(keys, fn key ->
      diff(Map.get(expected, key, :__missing__), Map.get(actual, key, :__missing__), [key | path])
    end)
  end

  defp diff(expected, actual, path) when is_list(expected) and is_list(actual) do
    expected
    |> pad_zip(actual)
    |> Enum.with_index()
    |> Enum.find_value(fn {{exp, act}, index} -> diff(exp, act, ["[#{index}]" | path]) end)
  end

  defp diff(value, value, _path), do: nil
  defp diff(expected, actual, path), do: {path, expected, actual}

  defp pad_zip(left, right) do
    count = max(length(left), length(right))
    pad = fn list -> list ++ List.duplicate(:__missing__, count - length(list)) end
    Enum.zip(pad.(left), pad.(right))
  end
end
