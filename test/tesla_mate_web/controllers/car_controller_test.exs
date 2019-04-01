defmodule TeslaMateWeb.CarControllerTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Log
  alias TeslaMate.Log.Car

  @create_attrs %{
    efficiency: 120.5,
    eid: 42,
    model: "some model",
    vid: 42
  }
  @update_attrs %{
    efficiency: 456.7,
    eid: 43,
    model: "some updated model",
    vid: 43
  }
  @invalid_attrs %{efficiency: nil, eid: nil, model: nil, vid: nil}

  def fixture(:car) do
    {:ok, car} = Log.create_car(@create_attrs)
    car
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all car", %{conn: conn} do
      conn = get(conn, Routes.car_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "update car" do
    setup [:create_car]

    test "renders car when data is valid", %{conn: conn, car: %Car{id: id} = car} do
      conn = put(conn, Routes.car_path(conn, :update, car), car: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.car_path(conn, :show, id))

      assert %{
               "id" => id,
               "efficiency" => 456.7,
               "model" => "some updated model",
               "eid" => 42,
               "vid" => 42
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, car: car} do
      conn = put(conn, Routes.car_path(conn, :update, car), car: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  defp create_car(_) do
    car = fixture(:car)
    {:ok, car: car}
  end
end
