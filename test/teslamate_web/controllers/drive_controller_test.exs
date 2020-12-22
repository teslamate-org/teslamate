defmodule TeslaMateWeb.DriveControllerTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Log
  alias TeslaMate.Repo

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42, vin: "xxxxx"})
      |> Log.create_car()

    car
  end

  defp drive_fixture(car) do
    {:ok, drive} = Log.start_drive(car)

    Log.insert_position(drive, %{
      date: DateTime.utc_now(),
      latitude: 5.0,
      longitude: 5.0,
      elevation: 100
    })

    Log.insert_position(drive, %{
      date: DateTime.utc_now(),
      latitude: 10.0,
      longitude: 10.0,
      elevation: 200
    })

    Log.insert_position(drive, %{
      date: DateTime.utc_now() |> DateTime.add(-3600, :second),
      latitude: 0.0,
      longitude: 0.0,
      elevation: 50
    })

    drive |> Repo.preload(:positions)
  end

  describe "GET /drive/:id/gpx" do
    test "sets xml and content-disposition headers", %{conn: conn} do
      drive = drive_fixture(car_fixture())
      assert conn = get(conn, Routes.drive_path(conn, :gpx, drive.id))

      headers = Enum.into(conn.resp_headers, %{})
      assert headers["content-disposition"] == ~s(attachment; filename="#{drive.start_date}.gpx")
      assert response_content_type(conn, :xml) =~ "charset=utf-8"
    end

    test "renders gpx", %{conn: conn} do
      drive = drive_fixture(car_fixture())
      assert conn = get(conn, Routes.drive_path(conn, :gpx, drive.id))
      xml = response(conn, 200)
      assert xml =~ ~s(<gpx version="1.1")

      document = Floki.parse_document!(xml)
      xml_trackpoints = get_trackpoints(document)

      drive_trackpoints = drive_trackpoints_to_trackpoints(drive) |> Enum.sort_by(& &1.time)

      assert xml_trackpoints == drive_trackpoints

      track_name = document |> Floki.find("name") |> Floki.text()
      assert track_name == DateTime.to_iso8601(drive.start_date)
    end

    test "returns 404 on drive not found", %{conn: conn} do
      assert conn = get(conn, Routes.drive_path(conn, :gpx, "4"))
      assert conn.status == 404
    end

    defp drive_trackpoints_to_trackpoints(drive) do
      Enum.map(drive.positions, fn pos ->
        %{
          latitude: pos.latitude |> Decimal.to_string(),
          longitude: pos.longitude |> Decimal.to_string(),
          time: pos.date |> DateTime.to_iso8601(),
          elevation: pos.elevation |> Integer.to_string()
        }
      end)
    end

    defp get_trackpoints(document) do
      document
      |> Floki.find("gpx trk trkseg trkpt")
      |> Enum.map(&parse_trackpoint/1)
    end

    defp parse_trackpoint(trkpt) do
      latitude = Floki.attribute(trkpt, "lat")
      longitude = Floki.attribute(trkpt, "lon")
      time = Floki.find(trkpt, "time") |> Floki.text()
      elevation = Floki.find(trkpt, "ele") |> Floki.text()

      %{
        latitude: Enum.at(latitude, 0),
        longitude: Enum.at(longitude, 0),
        time: time,
        elevation: elevation
      }
    end
  end
end
