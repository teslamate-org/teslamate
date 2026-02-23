defmodule TeslaMateWeb.Api.VehicleChannel do
  use TeslaMateWeb, :channel

  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMateWeb.Api.Views.CarJSON

  @impl true
  def join("vehicle:" <> car_id_str, _payload, socket) do
    case Integer.parse(car_id_str) do
      {car_id, ""} ->
        :ok = Vehicle.subscribe_to_summary(car_id)

        # Send initial summary
        try do
          summary = Vehicle.summary(car_id)
          send(self(), {:push_summary, summary})
        catch
          :exit, _ -> :ok
        end

        {:ok, assign(socket, :car_id, car_id)}

      _ ->
        {:error, %{reason: "invalid car_id"}}
    end
  end

  # PubSub broadcasts Summary struct directly
  @impl true
  def handle_info(%Summary{} = summary, socket) do
    push(socket, "summary", CarJSON.summary(summary))
    {:noreply, socket}
  end

  # Internal message for initial summary push
  def handle_info({:push_summary, %Summary{} = summary}, socket) do
    push(socket, "summary", CarJSON.summary(summary))
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
end
