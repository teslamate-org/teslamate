defmodule TeslaMate.Settings.Range do
  use EctoEnum.Postgres, type: :range, enums: [:ideal, :rated]
end
