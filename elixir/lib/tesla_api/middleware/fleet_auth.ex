defmodule TeslaApi.Middleware.FleetAuth do
  @moduledoc """
  Fleet mode authentication.

  When the `TOKEN` env var is set, every request is routed through a proxy that
  handles the real Tesla authentication. TeslaMate only needs to authenticate to
  that proxy, with a single bearer token, so we override the `Authorization`
  header with `Bearer <TOKEN>` (replacing the per-account access token set by
  `TeslaApi.Middleware.TokenAuth`).

  Passing the token as a header instead of a query/path component keeps it out of
  the request URLs that `Tesla.Middleware.Logger` writes on every call.

  When `TOKEN` is unset (owner mode), this middleware is a no-op.
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(%Tesla.Env{} = env, next, _opts) do
    env =
      case token() do
        nil -> env
        token -> Tesla.put_header(env, "Authorization", "Bearer " <> token)
      end

    Tesla.run(env, next)
  end

  @doc """
  The fleet proxy token from the `TOKEN` env var, or `nil` in owner mode.

  For backward compatibility the legacy `?token=...` (or `token=...`) form is
  accepted and normalized to the raw token value.
  """
  def token do
    case System.get_env("TOKEN", "") |> String.trim() do
      "" -> nil
      raw -> normalize(raw)
    end
  end

  defp normalize("?token=" <> token), do: token
  defp normalize("token=" <> token), do: token
  defp normalize(token), do: token
end
