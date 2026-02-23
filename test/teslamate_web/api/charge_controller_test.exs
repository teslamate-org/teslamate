defmodule TeslaMateWeb.Api.ChargeControllerTest do
  use TeslaMateWeb.ApiCase

  describe "GET /api/v1/cars/:car_id/charges" do
    test "returns paginated charges", %{conn: conn} do
      car = create_test_car()

      conn =
        conn
        |> authenticate()
        |> get("/api/v1/cars/#{car.id}/charges")

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
        |> get("/api/v1/cars/#{car.id}/charges?page=3&per_page=10")

      assert %{"page" => 3, "per_page" => 10} = json_response(conn, 200)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/cars/1/charges")

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/charges/:id" do
    test "returns 404 for non-existent charge", %{conn: conn} do
      conn =
        conn
        |> authenticate()
        |> get("/api/v1/charges/99999")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/charges/1")

      assert json_response(conn, 401)
    end
  end
end
