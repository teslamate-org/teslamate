defmodule TeslaMate.Log.State.State do
  use EctoEnum.Postgres, type: :states_status, enums: [:online, :offline, :asleep]
end
