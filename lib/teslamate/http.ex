defmodule TeslaMate.HTTP do
  def child_spec(arg) do
    %{
      id: __MODULE__,
      start:
        {Finch, :start_link,
         [
           Keyword.merge(
             [
               name: __MODULE__,
               pools: %{
                 :default => [size: 5],
                 "https://owner-api.teslamotors.com" => [size: 10],
                 "https://nominatim.openstreetmap.org" => [size: 3],
                 "https://api.github.com" => [size: 1]
               }
             ],
             arg
           )
         ]}
    }
  end

  @pool_timeout 10_000

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
