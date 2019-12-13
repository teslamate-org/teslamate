defmodule TeslaApi.Vehicle do
  alias __MODULE__.State.{Charge, Climate, Drive, VehicleConfig, VehicleState}
  alias TeslaApi.Auth

  defstruct id: nil,
            vehicle_id: nil,
            vin: nil,
            tokens: [],
            state: "unknown",
            option_codes: [],
            in_service: false,
            display_name: nil,
            color: nil,
            calendar_enabled: nil,
            backseat_token: nil,
            backseat_token_updated_at: nil,
            api_version: nil,
            charge_state: nil,
            climate_state: nil,
            drive_state: nil,
            gui_settings: nil,
            vehicle_config: nil,
            vehicle_state: nil

  def list(%Auth{token: token}) do
    TeslaApi.get("/api/1/vehicles", token, transform: &vehicle/1)
  end

  def get(%Auth{token: token}, id) do
    TeslaApi.get("/api/1/vehicles/#{id}", token, transform: &vehicle/1)
  end

  def get_with_state(%Auth{token: token}, id) do
    TeslaApi.get("/api/1/vehicles/#{id}/vehicle_data", token, transform: &vehicle/1)
  end

  defp vehicle(v) do
    %__MODULE__{
      id: v["id"],
      vehicle_id: v["vehicle_id"],
      vin: v["vin"],
      tokens: v["tokens"],
      state: v["state"] || "unknown",
      option_codes: String.split(v["option_codes"] || "", ","),
      in_service: v["in_service"],
      display_name: v["display_name"],
      color: v["color"],
      calendar_enabled: v["calendar_enabled"],
      backseat_token: v["backseat_token"],
      backseat_token_updated_at: v["backseat_token_updated_at"],
      api_version: v["api_version"],
      charge_state: if(v["charge_state"], do: Charge.result(v["charge_state"])),
      climate_state: if(v["climate_state"], do: Climate.result(v["climate_state"])),
      drive_state: if(v["drive_state"], do: Drive.result(v["drive_state"])),
      vehicle_config: if(v["vehicle_config"], do: VehicleConfig.result(v["vehicle_config"])),
      vehicle_state: if(v["vehicle_state"], do: VehicleState.result(v["vehicle_state"]))
    }
  end
end
