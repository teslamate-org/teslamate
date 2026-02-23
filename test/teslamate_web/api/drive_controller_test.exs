defmodule TeslaMateWeb.Api.DriveControllerTest do
  use TeslaMateWeb.ApiCase

  describe "GET /api/v1/cars/:car_id/drives" do
    test "returns paginated drives", %{conn: conn} do
      car = create_test_car()

      conn =
        conn
        |> authenticate()
        |> get("/api/v1/cars/#{car.id}/drives")

      assert %{
               "data" => [],
               "page" => 1,
               "per_page" => 20,
               "total" => 0
             } = json_response(conn, 200)
    end

    test "accepts pagination params", %{conn: conn} do
      car = create_test_car()

      conn =
        conn
        |> authenticate()
        |> get("/api/v1/cars/#{car.id}/drives?page=2&per_page=5")

      assert %{"page" => 2, "per_page" => 5} = json_response(conn, 200)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/cars/1/drives")

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/drives/:id" do
    test "returns 404 for non-existent drive", %{conn: conn} do
      conn =
        conn
        |> authenticate()
        |> get("/api/v1/drives/99999")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/drives/1")

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/drives/:id/gpx" do
    test "returns 404 for non-existent drive", %{conn: conn} do
      conn =
        conn
        |> authenticate()
        |> get("/api/v1/drives/99999/gpx")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/drives/1/gpx")

      assert json_response(conn, 401)
    end
  end
end
