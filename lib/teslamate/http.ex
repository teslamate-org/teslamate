defmodule TeslaMate.HTTP do
  require Logger

  @pools %{
    System.get_env("TESLA_API_HOST", "https://owner-api.teslamotors.com") => [size: 10],
    "https://nominatim.openstreetmap.org" => [size: 3],
    "https://api.github.com" => [size: 1],
    :default => [size: 5]
  }

  @pool_timeout 10_000

  def child_spec(_arg) do
    Finch.child_spec(name: __MODULE__, pools: @pools)
  end

#  def get(url, opts \\ []) do
#    {headers, opts} =
#      opts
#      |> Keyword.put_new(:pool_timeout, @pool_timeout)
#      |> Keyword.pop(:headers, [])
#
#    verify_mode = System.get_env("TESLA_HTTP_TLS_ACCEPT_INVALID_CERTS", "verify_peer")
#    Logger.info("verify_mode =  #{verify_mode}")
#    opts = Keyword.put(opts, :transport_opts, [ssl: [verify: String.to_atom(verify_mode)]])
#    Logger.info("opts =  #{opts}")
#
#    Finch.build(:get, url, headers, nil)
#    |> Finch.request(__MODULE__, opts)
#  end

  def post(url, body \\ nil, opts \\ []) do
    {headers, opts} =
      opts
      |> Keyword.put_new(:pool_timeout, @pool_timeout)
      |> Keyword.pop(:headers, [])

    verify_mode = System.get_env("TESLA_HTTP_TLS_ACCEPT_INVALID_CERTS", "verify_peer")
    Logger.info("verify_mode =  #{verify_mode}")
    opts = Keyword.put(opts, :transport_opts, [ssl: [verify: String.to_atom(verify_mode)]])
    Logger.info("opts =  #{opts}")

    Finch.build(:post, url, headers, body)
    |> Finch.request(__MODULE__, opts)
  end
end
