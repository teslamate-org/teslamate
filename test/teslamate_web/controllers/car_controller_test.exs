defmodule TeslaMateWeb.CarControllerTest do
  use TeslaMateWeb.ConnCase

  # alias TeslaMate.Log
  # alias TeslaMate.Log.Car

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "supsend" do
  end

  describe "resume" do
  end

  # describe "index" do
  #   test "lists all car", %{conn: conn} do
  #     conn = get(conn, Routes.car_path(conn, :index))
  #     assert json_response(conn, 200)["data"] == []
  #   end
  # end

  # describe "update car" do
  #   setup [:create_car]

  #   test "renders car when data is valid", %{conn: conn, car: %Car{id: id} = car} do
  #     conn = put(conn, Routes.car_path(conn, :update, car), car: @update_attrs)
  #     assert %{"id" => ^id} = json_response(conn, 200)["data"]

  #     conn = get(conn, Routes.car_path(conn, :show, id))

  #     assert %{
  #              "id" => id,
  #              "efficiency" => 456.7,
  #              "model" => "some updated model",
  #              "eid" => 42,
  #              "vid" => 42
  #            } = json_response(conn, 200)["data"]
  #   end

  #   test "renders errors when data is invalid", %{conn: conn, car: car} do
  #     conn = put(conn, Routes.car_path(conn, :update, car), car: @invalid_attrs)
  #     assert json_response(conn, 422)["errors"] != %{}
  #   end
  # end
end
