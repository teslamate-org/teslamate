defmodule TeslaMate.HTTP do
  require Logger

  def pools do
    nominatim_proxy =
      case build_proxy_opts_from_env("NOMINATIM_PROXY") do
        {:ok, opts} -> opts
        {:none, _} -> []
        {:error, _} -> []
      end

    %{
      System.get_env("TESLA_API_HOST", "https://owner-api.teslamotors.com") => [
        size: System.get_env("TESLA_API_POOL_SIZE", "10") |> String.to_integer()
      ],
      "https://nominatim.openstreetmap.org" => [size: 3] ++ nominatim_proxy,
      "https://api.github.com" => [size: 1],
      :default => [size: System.get_env("HTTP_POOL_SIZE", "5") |> String.to_integer()]
    }
  end

  @pool_timeout System.get_env("HTTP_POOL_TIMEOUT", "10000") |> String.to_integer()

  @spec build_proxy_opts_from_env(binary) :: {:ok, keyword} | {:none, []} | {:error, []}
  defp build_proxy_opts_from_env(var) do
    url = System.get_env(var)
    Logger.info("[proxy] read #{var}=#{inspect(url)}")

    case url do
      nil ->
        Logger.info("[proxy] #{var} unset -> fallback: no proxy")
        {:none, []}

      _ ->
        uri = URI.parse(url)

        cond do
          uri.scheme != "http" ->
            Logger.warning(
              "[proxy] #{var}=#{inspect(url)} unsupported scheme=#{inspect(uri.scheme)} (only http). fallback: no proxy"
            )

            {:error, []}

          is_nil(uri.host) or uri.host == "" ->
            Logger.warning(
              "[proxy] #{var}=#{inspect(url)} invalid URI: missing host. fallback: no proxy"
            )

            {:error, []}

          not is_integer(uri.port) ->
            Logger.warning(
              "[proxy] #{var}=#{inspect(url)} invalid URI: missing/invalid port. fallback: no proxy"
            )

            {:error, []}

          true ->
            opts = [conn_opts: [proxy: {:http, uri.host, uri.port, []}]]
            Logger.info("[proxy] set http proxy host=#{uri.host} port=#{uri.port}")
            {:ok, opts}
        end
    end
  end

  def child_spec(_arg) do
    Finch.child_spec(name: __MODULE__, pools: pools())
  end

  def get(url, opts \\ []) do
    {headers, opts} =
      opts
      |> Keyword.put_new(:pool_timeout, @pool_timeout)
      |> Keyword.pop(:headers, [])

    Finch.build(:get, url, headers, nil)
    |> Finch.request(__MODULE__, opts)
  end

  def post(url, body \\ nil, opts \\ []) do
    {headers, opts} =
      opts
      |> Keyword.put_new(:pool_timeout, @pool_timeout)
      |> Keyword.pop(:headers, [])

    Finch.build(:post, url, headers, body)
    |> Finch.request(__MODULE__, opts)
  end
end
