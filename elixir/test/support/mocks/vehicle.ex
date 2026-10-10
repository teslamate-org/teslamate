defmodule VehicleMock do
  alias TeslaMate.Vehicles.Vehicle

  def child_spec(arg) do
    arg = Keyword.put(arg, :deps_api, {ApiMock, :api_vehicle})

    %{
      id: :"#{VehicleMock}_#{Keyword.fetch!(arg, :car).id}",
      start: {Vehicle, :start_link, [arg]}
    }
  end
end
