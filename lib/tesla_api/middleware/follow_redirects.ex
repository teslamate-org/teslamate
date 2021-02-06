defmodule TeslaApi.Middleware.FollowRedirects do
  @moduledoc """
  Follow 3xx redirects

  Source: https://github.com/teamon/tesla/blob/master/lib/tesla/middleware/follow_redirects.ex

  ## Example

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.FollowRedirects, max_redirects: 3, except: ["http:/www.example.com"]
  end
  ```

  ## Options

  - `:max_redirects` - limit number of redirects (default: `3`)
  - `:except` - redirect locations which should not be followd (default: `[]`)

  """

  @behaviour Tesla.Middleware

  @max_redirects 3
  @redirect_statuses [301, 302, 303, 307, 308]

  @impl Tesla.Middleware
  def call(env, next, opts \\ []) do
    max = Keyword.get([], :max_redirects, @max_redirects)
    except = opts[:except] || []

    redirect(env, next, except, max)
  end

  defp redirect(env, next, _except, left) when left == 0 do
    case Tesla.run(env, next) do
      {:ok, %{status: status} = env} when not (status in @redirect_statuses) ->
        {:ok, env}

      {:ok, _env} ->
        {:error, {__MODULE__, :too_many_redirects}}

      error ->
        error
    end
  end

  defp redirect(env, next, except, left) do
    case Tesla.run(env, next) do
      {:ok, %{status: status} = res} when status in @redirect_statuses ->
        case Tesla.get_header(res, "location") do
          nil ->
            {:ok, res}

          location ->
            if Enum.any?(except, &String.starts_with?(location, &1)) do
              {:ok, res}
            else
              prev_uri = URI.parse(env.url)
              next_uri = parse_location(location, res)

              # Copy opts and query params from the response env,
              # these are not modified in the adapters, but middlewares
              # that come after might store state there
              env = %{env | opts: res.opts}

              env
              |> filter_headers(prev_uri, next_uri)
              |> new_request(status, URI.to_string(next_uri))
              |> redirect(next, except, left - 1)
            end
        end

      other ->
        other
    end
  end

  # The 303 (See Other) redirect was added in HTTP/1.1 to indicate that the originally
  # requested resource is not available, however a related resource (or another redirect)
  # available via GET is available at the specified location.
  # https://tools.ietf.org/html/rfc7231#section-6.4.4
  defp new_request(env, 303, location), do: %{env | url: location, method: :get, query: []}

  # The 307 (Temporary Redirect) status code indicates that the target
  # resource resides temporarily under a different URI and the user agent
  # MUST NOT change the request method (...)
  # https://tools.ietf.org/html/rfc7231#section-6.4.7
  defp new_request(env, 307, location), do: %{env | url: location}

  defp new_request(env, _, location), do: %{env | url: location, query: []}

  defp parse_location("https://" <> _rest = location, _env), do: URI.parse(location)
  defp parse_location("http://" <> _rest = location, _env), do: URI.parse(location)
  defp parse_location(location, env), do: env.url |> URI.parse() |> URI.merge(location)

  # See https://github.com/teamon/tesla/issues/362
  # See https://github.com/teamon/tesla/issues/360
  @filter_headers ["authorization", "host"]
  defp filter_headers(env, prev, next) do
    if next.host != prev.host || next.port != prev.port || next.scheme != prev.scheme do
      %{env | headers: Enum.filter(env.headers, fn {k, _} -> k not in @filter_headers end)}
    else
      env
    end
  end
end
