defmodule TeslaMate.Vehicles.Vehicle.ReadModel do
  @moduledoc """
  What the summary shows, kept apart from the vehicle's last API response,
  which the state machine decides on and the database records.

  Polls and stream frames observe the car independently and arrive in any
  order. Each frame field shows its newest observation: the timestamp of
  the source that carries it decides — the frame's time, or the poll's
  `drive_state`, `charge_state` or `vehicle_state` timestamp. If a timestamp
  is missing or both are equal, the later arrival wins. `nil` is an
  observation like any value; only the odometer never decreases and never
  disappears. The display name is the one of the current vehicle response,
  with or without vehicle data. All other fields come from the base: the
  last accepted poll, or the values restored from the history before the
  first poll.

  Restored values are shown until the first observation of their field
  replaces them, whatever it is — the odometer too.

  The geofence and the terrain elevation are derived from the shown
  position; the caller looks them up (`position/1`, `put_geofence/2`,
  `put_terrain_elevation/2`). The shown elevation depends on the setup:
  with streaming the newest one a frame reports, without it the terrain
  elevation.

  A field in `fields/0` shows a value only once a source reported it;
  `shown/2` holds exactly those fields, and `polled?/1` tells whether the
  base fields are observations.
  """

  alias TeslaApi.Stream
  alias TeslaApi.Vehicle
  alias TeslaApi.Vehicle.State.{Charge, Drive, VehicleState}

  @type timestamp :: integer() | nil
  @type t :: %__MODULE__{
          base: %Vehicle{} | nil,
          polled?: boolean(),
          shown: %{atom() => {term(), timestamp()}},
          restored_odometer?: boolean(),
          terrain_position: {term(), term()} | nil
        }

  # restored_odometer?: the shown odometer is the restored one, which the
  # first observed odometer replaces even when it is lower.
  # terrain_position: the position the terrain elevation belongs to.
  defstruct base: nil,
            polled?: false,
            shown: %{},
            restored_odometer?: false,
            terrain_position: nil

  @drive_fields ~w(latitude longitude heading power speed shift_state)a
  @fields [:display_name] ++ @drive_fields ++ ~w(battery_level odometer elevation geofence)a

  def new, do: %__MODULE__{}

  @doc "The summary fields this model shows; all others come from the base."
  def fields, do: @fields

  @doc """
  Starts from the values restored from the history: the restored vehicle is
  the base, and every restored frame field with a value is shown, undated.
  """
  def restore(%Vehicle{} = vehicle) do
    restored =
      [
        drive_values(vehicle.drive_state),
        [battery_level: get(vehicle.charge_state, :battery_level)],
        [odometer: get(vehicle.vehicle_state, :odometer)]
      ]
      |> Enum.concat()
      |> Enum.reject(fn {_field, value} -> is_nil(value) end)
      |> Map.new(fn {field, value} -> {field, {value, nil}} end)

    %__MODULE__{
      base: vehicle,
      shown: restored,
      restored_odometer?: Map.has_key?(restored, :odometer)
    }
  end

  @doc "The display name of a vehicle response, with or without vehicle data."
  def observe_response(%__MODULE__{} = model, %Vehicle{display_name: display_name}),
    do: observe(model, :display_name, display_name, nil)

  @doc "An accepted poll becomes the base; its frame fields are observations."
  def observe_poll(%__MODULE__{} = model, %Vehicle{} = vehicle) do
    %__MODULE__{model | base: vehicle, polled?: true}
    |> observe_response(vehicle)
    |> observe_all(drive_values(vehicle.drive_state), get(vehicle.drive_state, :timestamp))
    |> observe_sub_state(:battery_level, vehicle.charge_state)
    |> observe_odometer(
      get(vehicle.vehicle_state, :odometer),
      get(vehicle.vehicle_state, :timestamp)
    )
  end

  @doc "A frame observes its fields at its time."
  def observe_frame(%__MODULE__{} = model, %Stream.Data{} = frame) do
    time = DateTime.to_unix(frame.time, :millisecond)

    fields = [
      latitude: frame.est_lat,
      longitude: frame.est_lng,
      heading: frame.est_heading,
      power: frame.power,
      speed: frame.speed,
      shift_state: frame.shift_state,
      battery_level: frame.soc,
      elevation: frame.elevation
    ]

    model
    |> observe_all(fields, time)
    |> observe_odometer(frame.odometer, time)
  end

  @doc "The shown position, or `:unobserved` before any source reported one."
  def position(%__MODULE__{shown: %{latitude: {lat, _}, longitude: {lng, _}}}), do: {lat, lng}
  def position(%__MODULE__{}), do: :unobserved

  @doc "The geofence of the shown position."
  def put_geofence(%__MODULE__{} = model, geofence), do: put_derived(model, :geofence, geofence)

  @doc "The terrain elevation at a position — the shown one when looked up."
  def put_terrain_elevation(%__MODULE__{} = model, elevation, position) do
    %__MODULE__{put_derived(model, :terrain_elevation, elevation) | terrain_position: position}
  end

  @doc "Whether the terrain elevation belongs to the shown position."
  def terrain_current?(%__MODULE__{} = model), do: model.terrain_position == position(model)

  def base(%__MODULE__{base: base}), do: base
  def polled?(%__MODULE__{polled?: polled?}), do: polled?

  @doc """
  The shown frame fields and derived values, as reported (raw units). The
  elevation is the frame's with streaming and the terrain's without it.
  """
  def shown(%__MODULE__{shown: shown}, streaming?) do
    shown
    |> Map.new(fn {field, {value, _timestamp}} -> {field, value} end)
    |> select_elevation(streaming?)
  end

  ## Private

  defp select_elevation(fields, true), do: Map.delete(fields, :terrain_elevation)

  defp select_elevation(fields, false) do
    case Map.pop(fields, :terrain_elevation, :unobserved) do
      {:unobserved, fields} -> Map.delete(fields, :elevation)
      {terrain, fields} -> Map.put(fields, :elevation, terrain)
    end
  end

  defp observe_all(model, fields, timestamp) do
    Enum.reduce(fields, model, fn {field, value}, model ->
      observe(model, field, value, timestamp)
    end)
  end

  defp observe_sub_state(model, _field, nil), do: model

  defp observe_sub_state(model, field, sub_state),
    do: observe(model, field, Map.fetch!(sub_state, field), sub_state.timestamp)

  defp observe(%__MODULE__{} = model, field, value, timestamp) do
    if older?(model, field, timestamp) do
      model
    else
      %__MODULE__{model | shown: Map.put(model.shown, field, {value, timestamp})}
    end
  end

  # Only an observed odometer is compared: the first observation replaces a
  # restored one.
  defp observe_odometer(model, nil, _timestamp), do: model

  defp observe_odometer(%__MODULE__{restored_odometer?: true} = model, odometer, timestamp) do
    %__MODULE__{observe(model, :odometer, odometer, timestamp) | restored_odometer?: false}
  end

  defp observe_odometer(%__MODULE__{} = model, odometer, timestamp) do
    case model.shown do
      %{odometer: {shown, _}} when odometer < shown -> model
      %{} -> observe(model, :odometer, odometer, timestamp)
    end
  end

  # A missing timestamp never counts as newer: then the later arrival — the
  # new observation — wins.
  defp older?(model, field, timestamp) do
    case model.shown do
      %{^field => {_value, shown}} when is_number(shown) and is_number(timestamp) ->
        timestamp < shown

      %{} ->
        false
    end
  end

  defp put_derived(%__MODULE__{} = model, field, value),
    do: %__MODULE__{model | shown: Map.put(model.shown, field, {value, nil})}

  defp drive_values(nil), do: []
  defp drive_values(%Drive{} = drive), do: Enum.map(@drive_fields, &{&1, Map.fetch!(drive, &1)})

  defp get(nil, _key), do: nil
  defp get(%Drive{} = drive, key), do: Map.fetch!(drive, key)
  defp get(%Charge{} = charge, key), do: Map.fetch!(charge, key)
  defp get(%VehicleState{} = vehicle_state, key), do: Map.fetch!(vehicle_state, key)
end
