defmodule TeslaMate.HTTP do
  @pools %{
    System.get_env("TESLA_API_HOST", "https://owner-api.teslamotors.com") => [
      size: System.get_env("TESLA_API_POOL_SIZE", "10") |> String.to_integer()
    ],
    "https://nominatim.openstreetmap.org" => [size: 3],
    "https://api.github.com" => [size: 1],
    :default => [size: System.get_env("HTTP_POOL_SIZE", "5") |> String.to_integer()]
  }

  @pool_timeout System.get_env("HTTP_POOL_TIMEOUT", "10000") |> String.to_integer()

  def child_spec(_arg) do
    Finch.child_spec(name: __MODULE__, pools: @pools)
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
