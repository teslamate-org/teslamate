defmodule TeslaMate.Log.Functions do
  import Ecto.Query, warn: false

  defmacro duration_min(a, b) do
    quote do
      fragment(
        "(EXTRACT(EPOCH FROM (?::timestamp - ?::timestamp)) / 60)::integer",
        unquote(a),
        unquote(b)
      )
    end
  end
end
