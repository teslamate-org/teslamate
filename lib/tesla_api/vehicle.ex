defmodule TeslaApi.Vehicle do
  alias __MODULE__.State.{Charge, Climate, Drive, VehicleConfig, VehicleState}
  alias TeslaApi.{Auth, Error}

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

  def list(%Auth{} = auth) do
    endpoint_url =
      case Auth.region(auth) do
        :chinese -> "https://owner-api.vn.cloud.tesla.cn"
        _global -> "https://owner-api.teslamotors.com"
      end

    TeslaApi.get(endpoint_url <> "/api/1/vehicles", opts: [access_token: auth.token])
    |> handle_response(transform: &result/1)
  end

  def get(%Auth{} = auth, id) do
    endpoint_url =
      case Auth.region(auth) do
        :chinese -> "https://owner-api.vn.cloud.tesla.cn"
        _global -> "https://owner-api.teslamotors.com"
      end

    TeslaApi.get(endpoint_url <> "/api/1/vehicles/#{id}", opts: [access_token: auth.token])
    |> handle_response(transform: &result/1)
  end

  def get_with_state(%Auth{} = auth, id) do
    endpoint_url =
      case Auth.region(auth) do
        :chinese -> "https://owner-api.vn.cloud.tesla.cn"
        _global -> "https://owner-api.teslamotors.com"
      end

    TeslaApi.get(endpoint_url <> "/api/1/vehicles/#{id}/vehicle_data",
      opts: [access_token: auth.token]
    )
    |> handle_response(transform: &result/1)
  end

  def result(v) do
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

  defp handle_response({:ok, %Tesla.Env{} = env}, opts) do
    case env do
      %Tesla.Env{status: status, body: %{"response" => res}} when status in 200..299 ->
        transform = Keyword.get(opts, :transform, & &1)
        {:ok, if(is_list(res), do: Enum.map(res, transform), else: transform.(res))}

      %Tesla.Env{status: 401} = env ->
        {:error, %Error{reason: :unauthorized, env: env}}

      %Tesla.Env{status: 404, body: %{"error" => "not_found"}} = env ->
        {:error, %Error{reason: :vehicle_not_found, env: env}}

      %Tesla.Env{status: 405, body: %{"error" => "vehicle is currently in service"}} = env ->
        {:error, %Error{reason: :vehicle_in_service, env: env}}

      %Tesla.Env{status: 408, body: %{"error" => "vehicle unavailable:" <> _}} = env ->
        {:error, %Error{reason: :vehicle_unavailable, env: env}}

      %Tesla.Env{status: 504} = env ->
        {:error, %Error{reason: :timeout, env: env}}

      %Tesla.Env{status: status, body: %{"error" => msg}} = env when status >= 500 ->
        {:error, %Error{reason: :unknown, message: msg, env: env}}

      %Tesla.Env{body: body} = env ->
        {:error, %Error{reason: :unknown, message: inspect(body), env: env}}
    end
  end

  defp handle_response({:error, reason}, _opts) when is_atom(reason) do
    {:error, %Error{reason: reason}}
  end

  defp handle_response({:error, reason}, _opts) do
    {:error, %Error{reason: :unknown, message: reason}}
  end
end
