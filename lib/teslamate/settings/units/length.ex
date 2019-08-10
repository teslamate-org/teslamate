defmodule TeslaMate.Settings.Units.Length do
  use EctoEnum.Postgres, type: :length, enums: [:km, :mi]
end
