defmodule TeslaApi do
  use Tesla

  adapter Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 35_000

  plug Tesla.Middleware.BaseUrl, "https://owner-api.teslamotors.com"
  plug Tesla.Middleware.Headers, [{"user-agent", "github.com/adriankumpf/teslamate"}]
  plug TeslaApi.Auth.Middleware
  plug Tesla.Middleware.JSON
end
