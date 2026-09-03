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
        "geofences": [{"name": "Home", "latitude": 52.5, "longitude": 13.35, "radius": 100}],
        "await": {"state": "offline", "drives_closed": 1},
        "expect_restart": true,
        "events": [
          {"vehicle": {<raw Tesla API JSON, decoded by TeslaApi.Vehicle.result/1>}},
          {"snapshot": true, "vehicle": {...}},
          {"error": "vehicle_unavailable"},
          {"stream": "<data:update wire CSV value, decoded by TeslaApi.Stream.decode_frame!/1>"},
          {"stream_control": "inactive"},
          {"call": "suspend_logging"},
          {"clock": 1704067500000}
        ]
      }

  A `snapshot` event serves both the state probe (`get_vehicle`) and the
  subsequent data fetch (`get_vehicle_with_state`) with the same payload,
  mirroring how one observed API response covers both endpoints; the pair
  counts as one serve toward the causal barrier.

  A `stream` event is a `data:update` frame in its wire form — the
  comma-separated value string — decoded by the production decoder
  (`TeslaApi.Stream.decode_frame!/1`). `stream_control` injects a stream
  status event; allowed are `"inactive"` and `"vehicle_offline"` — the
  reconnecting controls (`too_many_disconnects`, `tokens_expired`) are
  rejected because their vehicle handler calls back into the API
  synchronously, which would deadlock against the delivery sync below.

  Stream events are delivered at the serve boundary: when the next API
  fetch arrives, `ApiMock` pushes the pending events through the receiver
  the vehicle registered when connecting the stream, syncs on the vehicle
  (`:sys.get_state/1` — the fetch task is parked inside the mock call while
  the vehicle is free), and only then serves the API event. The
  interleaving of the events list is deterministic, without a wall-clock
  wait. A scenario cannot end in a stream or call event: the terminal must
  be an API event, because the causal barrier repeats it — and not in an
  error event either, whose unavailable counter keeps running under
  repeats. The barrier also refuses a terminal reached through the probe
  and strict fetch of a single cycle: both serves would come from one
  fetch and prove nothing.

  A `call` event performs a user action on the vehicle; allowed is
  `"suspend_logging"` — the whitelist grows with the conversion PRs whose
  scenarios first need an action. The suspend handler fetches vehicle data
  synchronously while handling the call, so `ApiMock` delivers the call
  through a proxy task and answers that strict fetch from the event queue:
  the scenario declares the strict-fetch response as the API event directly
  after the call, and its serve counts like any other (index, barrier,
  vacuity). The reply of every delivered call is outer behaviour — what the
  UI would get back — and is captured in the golden's `calls` section in
  delivery order (`{"suspend_logging": "ok"}` or
  `{"suspend_logging": {"error": "user_present"}}`); a rejection is pinned,
  never a harness error. The section exists only when the scenario declares
  call events. A dying proxy and a call that never completes raise with
  named errors. A replay must not end in `:suspended` — the
  state only survives at test speed because the suspend poll interval
  shrinks to milliseconds, so a golden would freeze a transitional state
  whose real duration is minutes — and raises after the awaited outcomes.

  `expect_restart: true` declares a scenario that pins a crash-and-restart:
  the vehicle runs `restart: :permanent` for this replay and the harness
  asserts, before teardown, that the vehicle actually went down. It requires
  a convergence outcome in `await`. Without the declaration an unexpected
  crash stays a red test (`restart: :temporary`).

  Events are served in order by `ApiMock`; the last event repeats for any
  further fetch. The replay end is event-driven, never a wait: after the last
  event has been served, the harness waits for exactly one more serve of the
  repeating terminal event — the state machine starting that next cycle proves
  the previous cycle, including all of its persistence and publishing effects,
  has completed.

  Scenarios whose outcome fires after the last event — timer-driven results
  (drive timeout, offline charge inference), but also state transitions that
  route through `:start` and complete one fetch cycle later — declare that
  outcome in `await`, a conjunction of facts: `"state"` (the current state —
  the open states row — has this state), `"drives_closed"` (exactly n closed
  drives) and `"positions"` (exactly n position rows — names the convergence
  point of a crash-and-restart scenario, whose restart effects finish after
  the causal barrier). Further fact kinds are added by the conversion PRs
  whose scenarios first need them. The facts are re-checked on every further cycle
  of the state machine; when all of them hold, one more serve of the terminal
  event proves the outcome cycle itself completed before capture.

  `geofences` (optional) are created in the database before the replay;
  geofence detection runs against the real `TeslaMate.Locations`.

  ## Clock

  The vehicle runs on the replay's clock (`TeslaMate.Characterization.Clock`
  through `deps_clock`), never on wall-clock time: `utc_now/0` strictly
  increases with every API serve — by at least one millisecond, or to the
  payload's `drive_state.timestamp` (the field the vehicle dates rows with)
  when that lies further ahead — advanced at the serve boundary before the
  vehicle processes the payload, so the vehicle's view and the clock agree
  causally. A serve without a payload time (asleep, offline, errors) still
  ticks: in production time always passes between two fetches, and a state
  row starting and ending at the same instant would swallow a `since`
  transition. Stream frames advance the clock to their `time` by `max`, so
  older payloads and backdated stale frames never move it back. The replay
  starts at the scenario's smallest payload time.
  Distance is real (`diff_seconds/2` in seconds: three idle minutes are
  three minutes of payload time), intervals stay collapsed to milliseconds
  like the test clock, so polls stay fast.

  A `{"clock": <epoch ms>}` event lets time pass without a payload — a
  drive timeout during radio silence, an idle suspend. It is delivered at
  the serve boundary in list order like stream and call events, carries no
  serve index, may not step backwards and cannot be the terminal. Every
  time the vehicle derives from its clock is therefore deterministic and
  pinned as a value; only Log's own timestamps (`inserted_at`,
  `updated_at`) and the `since` topic stay masked.

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
    * A declared crash names its check: with `expect_restart` the initial
      vehicle process is monitored and the replay fails before teardown
      unless it actually went down; a declaration without an `await`
      convergence outcome raises (`replay/2`, `expect_restart?/1`).
    * Stream deliveries never touch the terminal execution counter: serve
      indices are assigned to API events only (`index_events/1`), so the
      causal barrier and the vacuity probe stay anchored to the terminal
      API event.
    * Stream misuse raises with named errors: an event before the stream is
      connected (`ApiMock.deliver_stream/2`), an unsupported control
      (`stream_control!/1`), a scenario ending in a stream or call event
      (`build_events/1`).
    * Call events count nothing twice: the strict fetch inside the call
      handler is served through the regular exec path
      (`ApiMock.await_call_outcome/2`); an unsupported call raises
      (`call_event!/1`); every reply — acceptance or rejection — is
      captured in the golden's `calls` section (`ApiMock.calls/1`,
      `replay/2`), while a dying or never-completing call raises instead
      of hanging (`ApiMock.await_call_outcome/3`).
    * The barrier proves two processed fetch cycles: a terminal whose two
      serves are a probe followed by a strict fetch raises
      (`two_call_cycle?/2`, `replay/2`). The pair is treated as one cycle;
      the reachable error-fallback probe is the one two-fetch shape this
      over-approximates — its result is discarded as incomplete, so the
      terminal is equally unprocessed at capture, it fails loudly, and the
      remedy is the same settling event. A scenario cannot end in an error
      event, which is never repeat-neutral (`build_events/1`).
    * A replay that ends in `:suspended` raises after the awaited outcomes,
      and a barrier starved by the suspend poll interval names the state
      instead of timing out opaquely (`replay/2`, `await_serve/4`).
    * An awaited outcome that never materialises fails within a real deadline,
      reporting every declared fact with its actual value — it can never
      silently shorten the golden (`wait_outcomes/4`).
    * An await must guard something: recording refuses an await already fully
      satisfied at the barrier — evaluated race-free at the second serve of
      the terminal event, where the blocked fetch task freezes the state
      machine (`replay/2`).
    * After the awaited facts hold, one further serve of the terminal event
      proves the outcome cycle completed — the termination itself is the
      check (`wait_outcomes/4`).
    * `"state"` uses current-state semantics: the open states row must carry
      the declared state, not any historical row (`outcome_met?/2`).
    * The clock strictly increases with every serve: each API serve moves
      it by at least one millisecond or to the payload's time
      (`Clock.serve/1`), a clock event before any time the scenario has
      already reached raises statically (`check_clock_monotonic!/1`), a
      scenario cannot end in a clock event (`build_events/1`); the
      double-run diff proves the clock value at capture is deterministic.

  ## Limits — explicitly unenforced

    * Effect-neutrality is checked at record time and probabilistically (two
      coinciding runs); compare time relies on the recorded window.
    * Cross-topic MQTT publish order is concurrent by design
      (`Task.async_stream(ordered: false)`); goldens hold per-topic ordered
      sequences with consecutive duplicates collapsed.
    * With an active stream the vehicle's suspend settings are hardcoded to
      {3, 10} minutes and scenario suspend guards are dead. On the replay
      clock that window is payload time, not a wall-clock race: a parked
      streaming vehicle suspends exactly when its payloads are three minutes
      apart, and stays online otherwise.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised: 1, stop_supervised: 1]

  alias TeslaMate.Mqtt.PubSub.VehicleSubscriber
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.Characterization.Clock
  alias TeslaMate.{Locations, Log, Repo}

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

  # Machinery-test seam: the vacuity refusal is exercised against a synthetic
  # pair outside the fixture trees, so the record path must be reachable
  # without the mode environment.
  @doc false
  def record_pair(%Pair{} = pair), do: record(pair)

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
    create_geofences(input)
    events = build_events(input)
    {indexed, total} = index_events(events)
    Clock.reset(initial_clock(input))
    await = Map.get(input, "await", %{})
    expect_restart? = expect_restart?(input)
    collector = self()
    vacuity = :counters.new(1, [])

    # The serve boundary is the race-free probe point for vacuity: the vehicle
    # runs exactly one fetch task at a time, so while the terminal closure's
    # second execution (the causal barrier) runs inside ApiMock, the database
    # is causally frozen — all declared events processed, no repeat effects
    # yet. The facts are sampled there; the verdict is raised later at the
    # collector — never in the closure, a raise in handle_call would tear
    # down the vehicle's fetch task.
    wrap = fn result, index ->
      fn action ->
        Clock.serve(payload_time(result))
        send(collector, {:api_event_served, index, action})

        if index == total do
          :counters.add(vacuity, 1, 1)

          if :counters.get(vacuity, 1) == 2 and await != %{} do
            send(collector, {:awaits_vacuous?, Enum.all?(await, &outcome_met?(&1, car))})
          end
        end

        result
      end
    end

    # The :snapshot tag stays outside the closure: ApiMock recognises it on
    # the event itself and serves probe and data fetch from one execution.
    # Stream deliveries pass through unwrapped — they carry no serve index.
    wrapped =
      Enum.flat_map(indexed, fn
        {:clock_delivery, ms} ->
          [{:clock_delivery, fn -> Clock.set!(ms) end}]

        {:stream_delivery, %TeslaApi.Stream.Data{time: %DateTime{} = time} = frame} ->
          ms = DateTime.to_unix(time, :millisecond)
          [{:clock_delivery, fn -> Clock.advance(ms) end}, {:stream_delivery, frame}]

        {tag, _} = delivery when tag in [:stream_delivery, :call_delivery] ->
          [delivery]

        {:api, index, {:snapshot, result}} ->
          [{:snapshot, wrap.(result, index)}]

        {:api, index, result} ->
          [wrap.(result, index)]
      end)

    # Registered names are unique per replay, never reused across tests:
    # identity is structural, so a terminating straggler of a previous test
    # can never overlap the next one under a valid name.
    instance = :"#{run_id}_#{System.unique_integer([:positive])}"

    api = :"characterization_api_#{instance}"
    settings = :"characterization_settings_#{instance}"
    vehicles = :"characterization_vehicles_#{instance}"
    publisher = :"characterization_publisher_#{instance}"
    vehicle = :"characterization_vehicle_#{instance}"

    children = [
      {ApiMock, name: api, events: wrapped, pid: collector, vehicle: vehicle},
      {SettingsMock, name: settings, pid: collector},
      {VehiclesMock, name: vehicles, pid: collector},
      {MqttPublisherMock, name: publisher, pid: collector}
    ]

    for child <- children do
      {:ok, _} = start_supervised(with_run_id(child, instance))
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
       deps_locations: Locations,
       deps_clock: Clock}
      |> Supervisor.child_spec(
        id: {Vehicle, instance},
        restart: if(expect_restart?, do: :permanent, else: :temporary)
      )

    {:ok, vehicle_pid} = start_supervised(vehicle_spec)
    crash_monitor = if expect_restart?, do: Process.monitor(vehicle_pid)

    first = await_serve(total, vehicle, "initial serve", input["description"])

    # Causal barrier, not a wait: the terminal event repeats, so its next
    # serve proves the state machine finished the previous cycle — including
    # every persistence and publishing effect — and started the next one.
    second = await_serve(total, vehicle, "causal barrier", input["description"])

    if two_call_cycle?(first, second) do
      raise "the terminal event was reached through a two-call cycle — both barrier " <>
              "serves came from the probe and strict fetch of one fetch, which proves " <>
              "nothing; add a settling API event (#{input["description"]})"
    end

    if run_id != :compare and await != %{} do
      assert_receive {:awaits_vacuous?, vacuous?}, 5_000

      if vacuous? do
        raise "await #{inspect(await)} is already fully satisfied at the barrier — " <>
                "it guards nothing; drop it or extend the scenario (#{input["description"]})"
      end
    end

    await_outcomes(await, car, input["description"])

    # A replay must not end in :suspended: the state only exists because the
    # test env shrinks the suspend poll interval to milliseconds — a golden
    # captured there would freeze a transitional state whose real duration
    # is minutes. Resume or sleep the scenario instead.
    case vehicle_state(vehicle) do
      {:suspended, _} ->
        raise "the replay ends in :suspended — resume or sleep the scenario instead " <>
                "(#{input["description"]})"

      _ ->
        :ok
    end

    if expect_restart? do
      # Asserted before teardown, so a shutdown DOWN cannot satisfy it.
      assert_receive {:DOWN, ^crash_monitor, :process, _pid, _reason},
                     5_000,
                     "expect_restart is declared but the vehicle never went down — " <>
                       "drop the declaration (#{input["description"]})"
    end

    :ok = stop_supervised(vehicle_spec.id)
    :sys.get_state(subscriber)
    :ok = stop_supervised(:"#{VehicleSubscriber}#{car.id}")

    mqtt = drain_mqtt(%{}, car)
    flush_notifications()

    capture = %{"database" => dump_db(car), "mqtt" => mqtt}

    # The calls section exists only for scenarios that declare call events:
    # the diff unions the keys of both sides, so an always-present section
    # would break every golden recorded without one.
    if Enum.any?(events, &match?({:call_delivery, _}, &1)) do
      Map.put(capture, "calls", Enum.map(ApiMock.calls(api), &canonical_call/1))
    else
      capture
    end
  end

  defp canonical_call({call, :ok}), do: %{Atom.to_string(call) => "ok"}

  defp canonical_call({call, {:error, reason}}),
    do: %{Atom.to_string(call) => %{"error" => Atom.to_string(reason)}}

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

  defp build_events(%{"events" => [_ | _] = raw_events}) do
    events =
      Enum.map(raw_events, fn
        %{"snapshot" => true, "vehicle" => raw} ->
          {:snapshot, {:ok, TeslaApi.Vehicle.result(raw)}}

        %{"vehicle" => raw} ->
          {:ok, TeslaApi.Vehicle.result(raw)}

        %{"error" => reason} ->
          {:error, String.to_existing_atom(reason)}

        %{"stream" => value} when is_binary(value) ->
          {:stream_delivery, TeslaApi.Stream.decode_frame!(value)}

        %{"stream" => other} ->
          raise ArgumentError,
                ~s("stream" takes the data:update wire CSV value string, got #{inspect(other)})

        %{"stream_control" => control} ->
          {:stream_delivery, stream_control!(control)}

        %{"call" => call} ->
          {:call_delivery, call_event!(call)}

        %{"clock" => ms} when is_integer(ms) ->
          {:clock_delivery, ms}

        %{"clock" => other} ->
          raise ArgumentError, ~s("clock" takes an epoch in milliseconds, got #{inspect(other)})
      end)

    check_clock_monotonic!(events)

    case List.last(events) do
      {tag, _} when tag in [:stream_delivery, :call_delivery, :clock_delivery] ->
        raise "a scenario cannot end in a stream, call or clock event — the terminal must " <>
                "be an API event, because the causal barrier repeats it"

      {:error, _} ->
        raise "a scenario cannot end in an error event — the unavailable counter keeps " <>
                "running under repeats, so an error terminal is never repeat-neutral"

      _ ->
        events
    end
  end

  # A probe followed by a strict fetch is treated as one fetch cycle. In the
  # unreachable-assumption fetch it is one; in the reachable path the probe
  # can be the vehicle_unavailable fallback ending cycle N and the strict
  # fetch cycle N+1 — two fetches, but the fallback's result is discarded as
  # incomplete, so the terminal is equally unprocessed at capture and the
  # remedy is the same settling event. Every other pair spans two processed
  # cycles (a snapshot executes once per cycle, a strict fetch that got
  # asleep or offline is followed by the next cycle's probe, a call's strict
  # fetch by the next poll).
  @doc false
  def two_call_cycle?(:get_vehicle, :get_vehicle_with_state), do: true
  def two_call_cycle?(_first, _second), do: false

  # A clock event may not lie before any time the replay has already seen
  # in list order — payload times or earlier clock events. Checked here,
  # statically, because a raise inside the mock's serve would tear down the
  # vehicle's fetch task and surface as an opaque barrier timeout.
  defp check_clock_monotonic!(events) do
    Enum.reduce(events, nil, fn
      {:clock_delivery, ms}, latest when is_integer(latest) and ms < latest ->
        raise "clock event #{ms} lies before the replay's time #{latest} at that point of " <>
                "the scenario — the clock only moves forward"

      {:clock_delivery, ms}, _latest ->
        ms

      {:stream_delivery, %TeslaApi.Stream.Data{time: %DateTime{} = time}}, latest ->
        max_time(latest, DateTime.to_unix(time, :millisecond))

      {:ok, %TeslaApi.Vehicle{drive_state: %{timestamp: ts}}}, latest when is_integer(ts) ->
        max_time(latest, ts)

      {:snapshot, {:ok, %TeslaApi.Vehicle{drive_state: %{timestamp: ts}}}}, latest
      when is_integer(ts) ->
        max_time(latest, ts)

      _event, latest ->
        latest
    end)

    :ok
  end

  defp max_time(nil, ms), do: ms
  defp max_time(latest, ms), do: max(latest, ms)

  # User-action calls are staged like await facts: the whitelist grows with
  # the conversion PRs whose scenarios first need an action.
  defp call_event!("suspend_logging"), do: :suspend_logging

  defp call_event!(other) do
    raise ArgumentError,
          ~s(unsupported call #{inspect(other)} — allowed: "suspend_logging")
  end

  # Only control events whose vehicle handler never calls back into the API
  # synchronously are allowed: too_many_disconnects and tokens_expired
  # trigger an immediate synchronous reconnect (a call into deps.api), which
  # would deadlock against the serve boundary's get_state sync.
  defp stream_control!("inactive"), do: :inactive
  defp stream_control!("vehicle_offline"), do: :vehicle_offline

  defp stream_control!(other) do
    raise ArgumentError,
          "unsupported stream_control #{inspect(other)} — allowed: \"inactive\", " <>
            "\"vehicle_offline\"; the reconnecting controls (too_many_disconnects, " <>
            "tokens_expired) would deadlock against the serve boundary's get_state sync"
  end

  # Serve indices are assigned to API events only: stream deliveries never
  # execute a serve closure, so they cannot touch the terminal execution
  # counter that anchors the causal barrier and the vacuity probe.
  @doc false
  def index_events(events) do
    Enum.map_reduce(events, 0, fn
      {tag, _} = delivery, count
      when tag in [:stream_delivery, :call_delivery, :clock_delivery] ->
        {delivery, count}

      result, count ->
        {{:api, count + 1, result}, count + 1}
    end)
  end

  # A scenario that pins a crash-and-restart declares it; the declaration
  # inverts the crash contract and must name its convergence point.
  @doc false
  def expect_restart?(input) do
    case Map.get(input, "expect_restart", false) do
      false ->
        false

      true ->
        if Map.get(input, "await", %{}) == %{} do
          raise "expect_restart requires a declared convergence outcome in await " <>
                  "(#{input["description"]})"
        end

        true

      other ->
        raise ArgumentError,
              "expect_restart must be true or absent, got #{inspect(other)} " <>
                "(#{input["description"]})"
    end
  end

  defp create_geofences(input) do
    for geofence <- Map.get(input, "geofences", []) do
      attrs = atomize_keys!(geofence, ~s(geofence #{inspect(geofence["name"])}))

      case Locations.create_geofence(attrs) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          raise "fixture geofence #{inspect(geofence["name"])} rejected: #{inspect(changeset.errors)}"
      end
    end
  end

  # The replay starts at the scenario's smallest payload time; a scenario
  # without any payload timestamp (asleep/offline only) starts at the epoch.
  defp initial_clock(input) do
    case collect_timestamps(input["events"]) do
      [] -> Clock.epoch()
      timestamps -> Enum.min(timestamps)
    end
  end

  # The field the vehicle dates rows with; nil for payloads without one.
  defp payload_time({:ok, %TeslaApi.Vehicle{drive_state: %{timestamp: ts}}}) when is_integer(ts),
    do: ts

  defp payload_time(_result), do: nil

  defp collect_timestamps(%{} = map) do
    Enum.flat_map(map, fn
      {"timestamp", ts} when is_integer(ts) -> [ts]
      {_key, value} -> collect_timestamps(value)
    end)
  end

  defp collect_timestamps(list) when is_list(list),
    do: Enum.flat_map(list, &collect_timestamps/1)

  defp collect_timestamps(_value), do: []

  ## Awaited outcomes

  @await_deadline_ms 10_000

  defp await_serve(total, vehicle, phase, description) do
    receive do
      {:api_event_served, ^total, action} -> action
    after
      5_000 ->
        case vehicle_state(vehicle) do
          {:suspended, _} ->
            raise "the replay is stuck in :suspended (#{phase}) — the suspend poll " <>
                    "interval starves the terminal; resume or sleep the scenario " <>
                    "(#{description})"

          other ->
            flunk(
              "the terminal event was not served (#{phase}; vehicle state: " <>
                "#{inspect(other)}) — #{description}"
            )
        end
    end
  end

  defp vehicle_state(vehicle) do
    {state, _data} = :sys.get_state(vehicle)
    state
  catch
    :exit, _ -> :no_longer_running
  end

  defp await_outcomes(await, _car, _name) when await == %{}, do: :ok

  defp await_outcomes(await, car, name) do
    deadline = System.monotonic_time(:millisecond) + @await_deadline_ms
    wait_outcomes(await, car, name, deadline)
  end

  defp wait_outcomes(await, car, name, deadline) do
    cond do
      outcomes_met?(await, car) ->
        # Termination barrier: the outcome cycle's own effects (its commit
        # precedes its broadcast) are proven complete by one further serve.
        assert_receive {:api_event_served, _, _}, 5_000
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("""
        awaited outcome never happened — #{name}
        #{actuals_report(await, car)}
        """)

      true ->
        receive do
          {:api_event_served, _, _} -> wait_outcomes(await, car, name, deadline)
        after
          1_000 -> wait_outcomes(await, car, name, deadline)
        end
    end
  end

  defp outcomes_met?(await, car), do: Enum.all?(await, &outcome_met?(&1, car))

  defp outcome_met?({"state", state}, car),
    do: count_rows("states", "end_date IS NULL AND state::text = $2", [car.id, state]) > 0

  defp outcome_met?({"drives_closed", n}, car),
    do: count_rows("drives", "end_date IS NOT NULL", [car.id]) == n

  defp outcome_met?({"positions", n}, car),
    do: count_rows("positions", "TRUE", [car.id]) == n

  defp count_rows(table, condition, params) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM #{table} WHERE car_id = $1 AND #{condition}", params)

    count
  end

  defp actuals_report(await, car) do
    Enum.map_join(await, "\n", fn {fact, expected} ->
      "  #{fact}: expected #{inspect(expected)}, actual #{inspect(actual_value(fact, car))}"
    end)
  end

  defp actual_value("state", car) do
    %{rows: rows} =
      Repo.query!(
        "SELECT state::text FROM states WHERE car_id = $1 AND end_date IS NULL",
        [car.id]
      )

    case rows do
      [[state]] -> state
      [] -> nil
    end
  end

  defp actual_value("drives_closed", car) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM drives WHERE car_id = $1 AND end_date IS NOT NULL", [
        car.id
      ])

    count
  end

  defp actual_value("positions", car), do: count_rows("positions", "TRUE", [car.id])

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
      {mock, _} when mock in [ApiMock, SettingsMock, VehiclesMock] ->
        flush_notifications()

      {:api_event_served, _, _} ->
        flush_notifications()

      {:awaits_vacuous?, _} ->
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
