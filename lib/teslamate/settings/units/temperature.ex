defmodule TeslaMate.Settings.Units.Temperature do
  use EctoEnum.Postgres, type: :temperature, enums: [:C, :F]
end
