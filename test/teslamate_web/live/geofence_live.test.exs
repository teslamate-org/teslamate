defmodule TeslaMateWeb.GeoFenceLiveTest do
  use TeslaMateWeb.ConnCase

  alias TeslaMate.{Locations, Settings}
  alias TeslaMate.Locations.GeoFence

  def geofence_fixture(attrs \\ %{}) do
    {:ok, address} =
      attrs
      |> Enum.into(%{radius: 100})
      |> Locations.create_geofence()

    address
  end

  describe "Index" do
    @tag :signed_in
    test "renders all geo-fences", %{conn: conn} do
      _gf1 =
        geofence_fixture(%{name: "Post office", latitude: -25.066188, longitude: -130.100502})

      _gf2 =
        geofence_fixture(%{name: "Service Center", latitude: 52.394246, longitude: 13.542552})

      _gf3 =
        geofence_fixture(%{name: "Victory Column", latitude: 52.514521, longitude: 13.350144})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>Post office<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*100 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/

      assert html =~
               ~r/<tr>\n\s*<td><strong>Service Center<\/strong><\/td>\n\s*<td.*?>52.394246, 13.542552<\/td>\n\s*<td.*?>\n\s*100 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/

      assert html =~
               ~r/<tr>\n\s*<td><strong>Victory Column<\/strong><\/td>\n\s*<td.*?>52.514521, 13.350144<\/td>\n\s*<td.*?>\n\s*100 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/
    end

    @tag :signed_in
    test "displays radius in ft", %{conn: conn} do
      {:ok, _settings} =
        Settings.get_settings!() |> Settings.update_settings(%{unit_of_length: :mi})

      _gf1 =
        geofence_fixture(%{
          name: "Post office",
          latitude: -25.066188,
          longitude: -130.100502,
          radius: 100
        })

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>Post office<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*328 ft\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/
    end

    @tag :signed_in
    test "allows deletion of a geo-fence", %{conn: conn} do
      %GeoFence{id: id} =
        geofence_fixture(%{name: "Victory Column", latitude: 52.514521, longitude: 13.350144})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>Victory Column<\/strong><\/td>\n\s*<td.*?>52.514521, 13.350144<\/td>\n\s*<td.*?>\n\s*100 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/

      assert html =~
               ~r/a class="button.*?" href="#" phx-click="flag" phx-value="#{id}">Delete<\/a>/

      assert render_click(view, :flag, "#{id}") =~
               ~r/a class="button.*?" href="#" phx-click="delete" phx-value="#{id}">Confirm<\/a>/

      assert render_click(view, :delete, "#{id}") =~ ~r/<tbody>\n\s*<\/tbody>/
    end
  end

  describe "Edit" do
    @tag :signed_in
    test "validates changes when editing of a geo-fence", %{conn: conn} do
      %GeoFence{id: id} =
        geofence_fixture(%{name: "Post office", latitude: -25.066188, longitude: -130.100502})

      assert {:ok, view, html} = live(conn, "/geo-fences/#{id}/edit")

      assert html =~ ~r/<input .*? id="geo_fence_name" .*? value="Post office">/
      assert html =~ ~r/<input .*? id="geo_fence_latitude" .*? value="-25.066188" disabled>/
      assert html =~ ~r/<input .*? id="geo_fence_longitude" .*? value="-130.100502" disabled>/
      assert html =~ ~r/<input .*? id="geo_fence_radius" .*? value="100">/

      html = render_submit(view, :save, %{geo_fence: %{name: "", radius: ""}})

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_name" .*? value="">\s*<\/div>\n\s*<p .*?><span class="help is-danger pl-15">can&#39;t be blank<\/span><\/p>\n\s*<\/div>/

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_radius" .*? value="">\s*<\/div>(?s).*?<p .*?><span class="help is-danger pl-15">can&#39;t be blank<\/span><\/p>\n\s*<\/div>/
    end

    @tag :signed_in
    test "allows editing of a geo-fence", %{conn: conn} do
      %GeoFence{id: id} =
        geofence_fixture(%{name: "Post office", latitude: -25.066188, longitude: -130.100502})

      assert {:ok, view, html} = live(conn, "/geo-fences/#{id}/edit")

      assert html =~ ~r/<input .*? id="geo_fence_name" .*? value="Post office">/
      assert html =~ ~r/<input .*? id="geo_fence_latitude" .*? value="-25.066188" disabled>/
      assert html =~ ~r/<input .*? id="geo_fence_longitude" .*? value="-130.100502" disabled>/
      assert html =~ ~r/<input .*? id="geo_fence_radius" .*? value="100">/

      assert {:error, {:redirect, %{to: "/geo-fences"}}} =
               render_submit(view, :save, %{
                 geo_fence: %{name: "Adamstown", longitude: 0, latitude: 0, radius: 20}
               })

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>Adamstown<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*20 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/
    end

    @tag :signed_in
    test "allows editing of a geo-fence with radius being displayed in ft", %{conn: conn} do
      {:ok, _settings} =
        Settings.get_settings!() |> Settings.update_settings(%{unit_of_length: :mi})

      %GeoFence{id: id} =
        geofence_fixture(%{
          name: "Post office",
          latitude: -25.066188,
          longitude: -130.100502,
          radius: 20
        })

      assert {:ok, view, html} = live(conn, "/geo-fences/#{id}/edit")

      assert html =~ ~r/<input .*? id="geo_fence_radius" .*? value="66.0">/

      assert {:error, {:redirect, %{to: "/geo-fences"}}} =
               render_submit(view, :save, %{geo_fence: %{radius: 30}})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>Post office<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*30 ft\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/

      {:ok, _settings} =
        Settings.get_settings!() |> Settings.update_settings(%{unit_of_length: :km})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>Post office<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*9 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/
    end
  end

  describe "New" do
    @tag :signed_in
    test "validates cahnges when creating a new geo-fence", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      html =
        render_submit(view, :save, %{
          geo_fence: %{name: "", longitude: nil, latitude: nil, radius: ""}
        })

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_name" .*? value="">\s*<\/div>\n\s*<p .*?><span class="help is-danger pl-15">can&#39;t be blank<\/span><\/p>\n\s*<\/div>/

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_latitude" .*? value="">\s*<\/div>\n\s*<p .*?>\n\s*<span class="help is-danger pl-15">can&#39;t be blank<\/span>\s*<\/p>\n\s*<\/div>/

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_longitude" .*? value="">\s*<\/div>\n\s*<p .*?>\n\s*<span class="help is-danger pl-15">can&#39;t be blank<\/span>\s*<\/p>\n\s*<\/div>/

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_radius" .*? value="">\s*<\/div>(?s).*?<p .*?><span class="help is-danger pl-15">can&#39;t be blank<\/span><\/p>\n\s*<\/div>/

      html =
        render_submit(view, :save, %{
          geo_fence: %{name: "foo", longitude: "wat", latitude: "wat", radius: "40"}
        })

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_latitude" .*? value="wat">\s*<\/div>\n\s*<p .*?>\n\s*<span class="help is-danger pl-15">is invalid<\/span>\s*<\/p>\n\s*<\/div>/

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_longitude" .*? value="wat">\s*<\/div>\n\s*<p .*?>\n\s*<span class="help is-danger pl-15">is invalid<\/span>\s*<\/p>\n\s*<\/div>/
    end

    @tag :signed_in
    test "creates a new geo-fence", %{conn: conn} do
      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      # Default radius of 20m
      assert html =~ ~r/<input .*? id="geo_fence_radius" .*? value="20.0">/

      assert {:error, {:redirect, %{to: "/geo-fences"}}} =
               render_submit(view, :save, %{
                 geo_fence: %{
                   name: "post office",
                   latitude: -25.066188,
                   longitude: -130.100502,
                   radius: 25
                 }
               })

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>post office<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*25 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/
    end

    @tag :signed_in
    test "warn if a geo-fence already exists for a location", %{conn: conn} do
      %GeoFence{} =
        geofence_fixture(%{name: "Post office", latitude: -25.066188, longitude: -130.100502})

      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      html =
        render_submit(view, :save, %{
          geo_fence: %{
            name: "Post office 2",
            latitude: -25.066188,
            longitude: -130.100502,
            radius: "20"
          }
        })

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_latitude" .*? value="-25.066188">\s*<\/div>\n\s*<p .*?>\n\s*<span class="help is-danger pl-15">has already been taken<\/span>\s*<\/p>\n\s*<\/div>/

      assert html =~
               ~r/<div.*?>\n\s*<input .*? id="geo_fence_longitude" .*? value="-130.100502">\s*<\/div>\n\s*<p .*?>\n\s*<span class="help is-danger pl-15">has already been taken<\/span>\s*<\/p>\n\s*<\/div>/
    end

    @tag :signed_in
    test "allows creating of a geo-fence with radius being displayed in ft", %{conn: conn} do
      {:ok, _settings} =
        Settings.get_settings!() |> Settings.update_settings(%{unit_of_length: :mi})

      assert {:ok, view, html} = live(conn, "/geo-fences/new")

      assert {:error, {:redirect, %{to: "/geo-fences"}}} =
               render_submit(view, :save, %{
                 geo_fence: %{
                   name: "post office",
                   latitude: -25.066188,
                   longitude: -130.100502,
                   radius: 50
                 }
               })

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>post office<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*50 ft\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/

      {:ok, _settings} =
        Settings.get_settings!() |> Settings.update_settings(%{unit_of_length: :km})

      assert {:ok, view, html} = live(conn, "/geo-fences")

      assert html =~
               ~r/<tr>\n\s*<td><strong>post office<\/strong><\/td>\n\s*<td.*?>-25.066188, -130.100502<\/td>\n\s*<td.*?>\n\s*15 m\n\s*<\/td>\n\s*<td.*?>(?s).*<\/td>\n\s*<\/tr>/
    end
  end
end
