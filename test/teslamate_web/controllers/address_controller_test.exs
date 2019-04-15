defmodule TeslaMateWeb.AddressControllerTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.Addresses
  alias TeslaMate.Addresses.Address

  @create_attrs %{
    city: "some city",
    county: "some county",
    country: "some country",
    display_name: "some display_name",
    house_number: "some house_number",
    latitude: 120.5,
    longitude: 120.5,
    name: "some name",
    neighbourhood: "some neighbourhood",
    place_id: 42,
    postcode: "some postcode",
    raw: %{},
    road: "some road",
    state: "some state",
    state_district: "some state_district"
  }
  @update_attrs %{
    city: "some updated city",
    county: "some updated county",
    country: "some updated country",
    display_name: "some updated display_name",
    house_number: "some updated house_number",
    latitude: 456.7,
    longitude: 456.7,
    name: "some updated name",
    neighbourhood: "some updated neighbourhood",
    place_id: 43,
    postcode: "some updated postcode",
    raw: %{},
    road: "some updated road",
    state: "some updated state",
    state_district: "some updated state_district"
  }
  @invalid_attrs %{
    city: nil,
    county: nil,
    country: nil,
    display_name: nil,
    house_number: nil,
    latitude: nil,
    longitude: nil,
    name: nil,
    neighbourhood: nil,
    place_id: nil,
    postcode: nil,
    raw: nil,
    road: nil,
    state: nil,
    state_district: nil
  }

  def fixture(:address) do
    {:ok, address} = Addresses.create_address(@create_attrs)
    address
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all addresses", %{conn: conn} do
      conn = get(conn, Routes.address_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create address" do
    test "renders address when data is valid", %{conn: conn} do
      conn = post(conn, Routes.address_path(conn, :create), address: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.address_path(conn, :show, id))

      assert %{
               "id" => id,
               "city" => "some city",
               "county" => "some county",
               "country" => "some country",
               "display_name" => "some display_name",
               "house_number" => "some house_number",
               "latitude" => 120.5,
               "longitude" => 120.5,
               "name" => "some name",
               "neighbourhood" => "some neighbourhood",
               "place_id" => 42,
               "postcode" => "some postcode",
               "raw" => %{},
               "road" => "some road",
               "state" => "some state",
               "state_district" => "some state_district"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.address_path(conn, :create), address: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update address" do
    setup [:create_address]

    test "renders address when data is valid", %{conn: conn, address: %Address{id: id} = address} do
      conn = put(conn, Routes.address_path(conn, :update, address), address: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.address_path(conn, :show, id))

      assert %{
               "id" => id,
               "city" => "some updated city",
               "county" => "some updated county",
               "country" => "some updated country",
               "display_name" => "some updated display_name",
               "house_number" => "some updated house_number",
               "latitude" => 456.7,
               "longitude" => 456.7,
               "name" => "some updated name",
               "neighbourhood" => "some updated neighbourhood",
               "place_id" => 43,
               "postcode" => "some updated postcode",
               "raw" => %{},
               "road" => "some updated road",
               "state" => "some updated state",
               "state_district" => "some updated state_district"
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, address: address} do
      conn = put(conn, Routes.address_path(conn, :update, address), address: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete address" do
    setup [:create_address]

    test "deletes chosen address", %{conn: conn, address: address} do
      conn = delete(conn, Routes.address_path(conn, :delete, address))
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, Routes.address_path(conn, :show, address))
      end
    end
  end

  defp create_address(_) do
    address = fixture(:address)
    {:ok, address: address}
  end
end
