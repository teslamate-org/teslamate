defmodule TeslaMateWeb.Api.CarControllerTest do
  use TeslaMateWeb.ApiCase

  describe "GET /api/v1/cars" do
    test "returns empty list when no cars exist", %{conn: conn} do
      conn =
        conn
        |> authenticate()
        |> get("/api/v1/cars")

      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns list of cars", %{conn: conn} do
      create_test_car(%{name: "Model S", vin: "VIN00000000000001"})
      create_test_car(%{name: "Model 3", vin: "VIN00000000000002", eid: 1002, vid: 2002})

      conn =
        conn
        |> authenticate()
        |> get("/api/v1/cars")

      assert %{"data" => cars} = json_response(conn, 200)
      assert length(cars) == 2
      assert Enum.any?(cars, &(&1["name"] == "Model S"))
      assert Enum.any?(cars, &(&1["name"] == "Model 3"))
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/cars")

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/cars/:id" do
    test "returns car with settings", %{conn: conn} do
      car = create_test_car(%{name: "My Tesla"})

      conn =
        conn
        |> authenticate()
        |> get("/api/v1/cars/#{car.id}")

      assert %{"data" => car_data} = json_response(conn, 200)
      assert car_data["name"] == "My Tesla"
      assert car_data["id"] == car.id
      assert Map.has_key?(car_data, "settings")
    end

    test "returns 404 for non-existent car", %{conn: conn} do
      conn =
        conn
        |> authenticate()
        |> get("/api/v1/cars/99999")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/cars/1")

      assert json_response(conn, 401)
    end
  end
end
