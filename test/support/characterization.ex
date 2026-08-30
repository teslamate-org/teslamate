defmodule TeslaMate.Characterization do
  @moduledoc """
  Characterization harness (#5652): replays a recorded sequence of Tesla API
  payloads through the regular `Vehicle` boundary and captures what leaves the
  system — persisted rows and published MQTT messages. No mock call assertions;
  the golden file is the observed outer behaviour.

  ## Layout

      test/fixtures/characterization/
      ├── scenarios/<name>.json   # behaviour scenarios (content)
      ├── goldens/<name>.json     # their approved expectations
      └── selftest/
          ├── scenarios/<name>.json   # harness self-tests (machinery evidence)
          └── goldens/<name>.json

  Place is class: a file's directory decides whether it is a scenario or a
  golden; pairing is the shared basename across the two directories of a tree.
  Self-test goldens are machinery evidence, not behaviour contracts — they
  exist so the harness is verified inside the PR that ships it.

  ## Scenario format

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
  further fetch. The replay end is event-driven, never a wait: after the last
  event has been served, the harness waits for exactly one more serve of the
  repeating terminal event — the state machine starting that next cycle proves
  the previous cycle, including all of its persistence and publishing effects,
  has completed. Timer-driven outcomes are not expressible yet; the mechanism
  for awaiting a declared outcome is decided in the conversion PRs, where such
  scenarios first appear.

  ## Recording

  `CHARACTERIZATION_RECORD` accepts these forms — bare values are the closed
  set of modes; identifiers always carry the `only:` prefix and are
  tree-scoped (`only:<name>` for content, `only:selftest/<name>` for
  machinery evidence), so neither a scenario named `all.json` nor a basename
  shared across the trees can collide:

    * `1` / `true` — record scenarios that have no golden yet; existing
      goldens are compared — a record run never reports green for something
      it did not check
    * `all` — re-record every golden (declared replacement of approved files)
    * `only:<name>` / `only:selftest/<name>` — re-record exactly that golden

  A checked-in golden is an approved artifact: no tool step replaces it
  outside the operator's declared intent.

  State × mode, complete:

  | pairing state           | compare (off)             | `1`/`true`             | `all`     | `only:` match / others  |
  |-------------------------|---------------------------|------------------------|-----------|-------------------------|
  | scenario + golden       | compare                   | compare                | re-record | re-record / compare     |
  | scenario without golden | fail with the record hint | record                 | record    | record / fail with hint |
  | golden without scenario | orphan suite test fails in every mode                                                    |
  | `only:` without a match | suite test fails: the declared target must exist, or nothing would be recorded silently |
  | both directories empty  | never empty-green: the self-test scenarios always run                                    |

  ## Invariants — each names its check

    * Scenario without golden: comparison fails with the record instruction;
      never green (`run/1`).
    * Golden without scenario: the orphan suite test fails and lists it — a
      dead expectation must not rest silently (`orphans/0`).
    * The suite is never empty-green: the self-test scenarios always run.
    * Unknown `CHARACTERIZATION_RECORD` values raise instead of silently
      selecting a mode (`record_mode/1`).
    * Effect-neutrality under terminal repetition — enforced at record time by
      the double-run diff: recording replays twice and refuses any golden in
      which a whole table or topic collapses to ``"<volatile>"``.
    * Values that differ between the two record runs (wall-clock derived) are
      masked as ``"<volatile>"``; comparison accepts masked positions only.
    * Goldens contain only canonical representations: JSON object/array
      payloads are stored decoded and compared structurally (encoded map key
      order is not portable across runtimes); golden files are written with
      sorted keys, byte-identical no matter which machine records them.
    * The vehicle runs `restart: :temporary`: an unexpected crash fails the
      replay instead of being retried invisibly by the supervisor.

  ## Limits — explicitly unenforced

    * Effect-neutrality is checked at record time and probabilistically (two
      coinciding runs); compare time relies on the recorded window.
    * Cross-topic MQTT publish order is concurrent by design
      (`Task.async_stream(ordered: false)`); goldens hold per-topic ordered
      sequences with consecutive duplicates collapsed.
    * The end-of-replay barrier counts API serves, not fetch cycles; states
      whose handling makes two API calls per cycle are not expressible as
      terminals yet.
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

  ## Discovery: place is class, pairing is the shared basename

  defmodule Pair do
    @moduledoc false
    defstruct [:name, :scenario_path, :golden_path, :golden_exists?, :selftest?]
  end

  def pairs do
    content_pairs() ++ selftest_pairs()
  end

  def orphans do
    orphaned_goldens(scenarios_dir(), goldens_dir()) ++
      orphaned_goldens(selftest_scenarios_dir(), selftest_goldens_dir())
  end

  defp content_pairs, do: tree_pairs(scenarios_dir(), goldens_dir(), false)
  defp selftest_pairs, do: tree_pairs(selftest_scenarios_dir(), selftest_goldens_dir(), true)

  defp tree_pairs(scenarios_dir, goldens_dir, selftest?) do
    scenarios_dir
    |> list_json()
    |> Enum.map(fn name ->
      golden = Path.join(goldens_dir, name)

      %Pair{
        name: Path.basename(name, ".json"),
        scenario_path: Path.join(scenarios_dir, name),
        golden_path: golden,
        golden_exists?: File.exists?(golden),
        selftest?: selftest?
      }
    end)
  end

  defp orphaned_goldens(scenarios_dir, goldens_dir) do
    scenarios = list_json(scenarios_dir)

    goldens_dir
    |> list_json()
    |> Enum.reject(&(&1 in scenarios))
    |> Enum.map(&Path.join(goldens_dir, &1))
  end

  defp list_json(dir),
    do: dir |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort()

  defp scenarios_dir, do: Path.join(@fixtures_dir, "scenarios")
  defp goldens_dir, do: Path.join(@fixtures_dir, "goldens")
  defp selftest_scenarios_dir, do: Path.join([@fixtures_dir, "selftest", "scenarios"])
  defp selftest_goldens_dir, do: Path.join([@fixtures_dir, "selftest", "goldens"])

  ## Record mode: bare values are modes, identifiers carry the only: prefix

  def record_mode(nil), do: :off
  def record_mode(""), do: :off
  def record_mode("0"), do: :off
  def record_mode("false"), do: :off
  def record_mode(value) when value in ~w(1 true), do: :missing
  def record_mode("all"), do: :all

  # only: is tree-scoped: the same basename may exist as content scenario and
  # as self-test, so the identifier carries the tree — bare for content,
  # selftest/ prefixed for machinery evidence.
  def record_mode("only:selftest/" <> name) when name != "", do: {:only, {:selftest, name}}
  def record_mode("only:selftest/"), do: raise_record_mode("only:selftest/")
  def record_mode("only:" <> name) when name != "", do: {:only, {:content, name}}

  def record_mode(other), do: raise_record_mode(other)

  defp raise_record_mode(other) do
    raise ArgumentError,
          "unknown CHARACTERIZATION_RECORD value #{inspect(other)} — use 1/true " <>
            "(record missing), all (re-record everything), only:<name> or only:selftest/<name>"
  end

  def run(%Pair{} = pair) do
    # Existence is re-derived at run time: pairs are enumerated at test
    # definition, but a record run may have created the golden since.
    pair = %Pair{pair | golden_exists?: File.exists?(pair.golden_path)}
    mode = record_mode(System.get_env("CHARACTERIZATION_RECORD"))

    case mode do
      :off ->
        compare(pair)

      :missing ->
        if pair.golden_exists?,
          do: compare(pair),
          else: record(pair)

      :all ->
        record(pair)

      {:only, {:selftest, name}} ->
        if pair.selftest? and name == pair.name, do: record(pair), else: compare(pair)

      {:only, {:content, name}} ->
        if not pair.selftest? and name == pair.name, do: record(pair), else: compare(pair)
    end
  end

  defp record(%Pair{} = pair) do
    input = read_scenario(pair)

    first = replay(input, :record_1)
    reset_db()
    second = replay(input, :record_2)
    golden = mask_volatile(first, second)

    for {section, kind} <- [{"database", "table"}, {"mqtt", "topic"}],
        {key, value} <- golden[section],
        value == @volatile do
      raise "#{kind} #{key} differs structurally between the two record runs — " <>
              "the scenario is not repeat-neutral (see moduledoc); refusing to record " <>
              "a fully masked golden for #{pair.name}"
    end

    File.mkdir_p!(Path.dirname(pair.golden_path))
    File.write!(pair.golden_path, Jason.encode!(canonical_order(golden), pretty: true) <> "\n")
    IO.puts("recorded #{pair.name}")
  end

  defp compare(%Pair{} = pair) do
    assert pair.golden_exists?,
           "missing golden for #{pair.name} — " <>
             "record it with CHARACTERIZATION_RECORD=#{only_target(pair)} mix test"

    expected = pair.golden_path |> File.read!() |> Jason.decode!()
    actual = replay(read_scenario(pair), :compare)
    assert_equivalent(expected, actual, pair.name)
  end

  def only_target(%Pair{selftest?: true, name: name}), do: "only:selftest/#{name}"
  def only_target(%Pair{name: name}), do: "only:#{name}"

  # Suite-level check for the declared-intent invariant: a well-formed
  # only: value whose target does not exist would compare everything, record
  # nothing and report nothing — the declared intent would fizzle silently.
  def only_target_error do
    case record_mode(System.get_env("CHARACTERIZATION_RECORD")) do
      {:only, {tree, name}} ->
        exists? =
          Enum.any?(pairs(), fn pair ->
            pair.name == name and pair.selftest? == (tree == :selftest)
          end)

        unless exists? do
          "CHARACTERIZATION_RECORD targets #{tree_label(tree)}#{name}, " <>
            "but no such scenario exists — nothing would be recorded"
        end

      _ ->
        nil
    end
  end

  defp tree_label(:selftest), do: "selftest/"
  defp tree_label(:content), do: ""

  defp read_scenario(%Pair{scenario_path: path}), do: path |> File.read!() |> Jason.decode!()

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
      {Vehicle,
       name: vehicle,
       car: car,
       deps_api: {ApiMock, api},
       deps_settings: {SettingsMock, settings},
       deps_vehicles: {VehiclesMock, vehicles},
       deps_locations: {LocationsMock, locations}}
      |> Supervisor.child_spec(id: {Vehicle, run_id}, restart: :temporary)

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
    car_attrs = atomize_keys!(Map.fetch!(input, "car"), ~s(fixture section "car"))

    car =
      case Log.create_car(car_attrs) do
        {:ok, car} -> car
        {:error, changeset} -> raise "fixture car rejected: #{inspect(changeset.errors)}"
      end

    settings_attrs =
      atomize_keys!(Map.get(input, "settings", %{}), ~s(fixture section "settings"))

    car = Repo.preload(car, :settings)

    settings =
      case car.settings |> Ecto.Changeset.change(settings_attrs) |> Repo.update() do
        {:ok, settings} -> settings
        {:error, changeset} -> raise "fixture settings rejected: #{inspect(changeset.errors)}"
      end

    %{car | settings: settings}
  end

  defp atomize_keys!(map, context) do
    Map.new(map, fn {key, value} -> {atom!(key, context), value} end)
  end

  defp atom!(key, context) do
    String.to_existing_atom(key)
  rescue
    ArgumentError ->
      raise ArgumentError, "unknown key #{inspect(key)} in #{context}"
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
  def canonical_payload("{" <> _ = payload), do: decode_or_keep(payload)
  def canonical_payload("[" <> _ = payload), do: decode_or_keep(payload)
  def canonical_payload(payload), do: payload

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
  def canonical_order(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical_order(value)} end)
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Jason.OrderedObject.new()
  end

  def canonical_order(list) when is_list(list), do: Enum.map(list, &canonical_order/1)
  def canonical_order(value), do: value

  ## Golden: masking & comparison

  def mask_volatile(first, second) when is_map(first) and is_map(second) do
    keys = Enum.uniq(Map.keys(first) ++ Map.keys(second))

    Map.new(keys, fn key ->
      {key, mask_volatile(Map.get(first, key, :__missing__), Map.get(second, key, :__missing__))}
    end)
  end

  def mask_volatile(first, second) when is_list(first) and is_list(second) do
    if length(first) == length(second) do
      Enum.zip_with(first, second, &mask_volatile/2)
    else
      @volatile
    end
  end

  def mask_volatile(value, value), do: value
  def mask_volatile(_first, _second), do: @volatile

  defp assert_equivalent(expected, actual, name) do
    case diff(expected, actual) do
      nil ->
        :ok

      {path, exp, act} ->
        flunk("""
        characterization mismatch in #{name}
        first divergence at #{Enum.join(path, ".")}
        expected: #{inspect(exp)}
        actual:   #{inspect(act)}
        """)
    end
  end

  def diff(expected, actual) do
    case diff(expected, actual, []) do
      nil -> nil
      {path, exp, act} -> {Enum.reverse(path), exp, act}
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
