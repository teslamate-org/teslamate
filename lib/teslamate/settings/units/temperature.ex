defmodule TeslaMate.Settings.Units.Temperature do
  use EctoEnum.Postgres, type: :unit_of_temperature, enums: [:C, :F]
end
