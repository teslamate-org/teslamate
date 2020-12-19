defmodule TeslaApi.Auth.Middleware do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(%Tesla.Env{} = env, next, _opts) do
    env =
      case env.opts[:access_token] do
        nil -> env
        token -> Tesla.put_header(env, "Authorization", "Bearer " <> token)
      end

    Tesla.run(env, next)
  end
end
