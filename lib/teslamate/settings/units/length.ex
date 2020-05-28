defmodule TeslaMate.Settings.Units.Length do
  use EctoEnum.Postgres, type: :unit_of_length, enums: [:km, :mi]
end
