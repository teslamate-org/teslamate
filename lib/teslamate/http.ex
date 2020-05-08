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

  def get(url, headers \\ [], opts \\ []) do
    Finch.request(__MODULE__, :get, url, headers, nil, opts)
  end

  def post(url, headers \\ [], body \\ nil, opts \\ []) do
    Finch.request(__MODULE__, :post, url, headers, body, opts)
  end
end
