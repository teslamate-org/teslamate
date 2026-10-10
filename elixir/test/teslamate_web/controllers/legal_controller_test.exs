defmodule TeslaMateWeb.LegalControllerTest do
  use TeslaMateWeb.ConnCase

  describe "notice" do
    test "serves the NOTICE of this build as plain text", %{conn: conn} do
      conn = get(conn, Routes.legal_path(conn, :notice))

      # REUSE-IgnoreStart
      assert text_response(conn, 200) =~ "SPDX-License-Identifier: AGPL-3.0-or-later"
      # REUSE-IgnoreEnd
    end
  end

  describe "license" do
    test "serves the LICENSE of this build as plain text", %{conn: conn} do
      conn = get(conn, Routes.legal_path(conn, :license))

      assert text_response(conn, 200) =~ "GNU AFFERO GENERAL PUBLIC LICENSE"
    end
  end

  describe "footer" do
    test "shows the legal notice and links NOTICE and LICENSE", %{conn: conn} do
      html = conn |> get("/settings") |> html_response(200)

      assert [legal] = html |> Floki.parse_document!() |> Floki.find("footer .legal")

      text = Floki.text(legal)
      # REUSE-IgnoreStart
      assert text =~ "© the TeslaMate contributors"
      # REUSE-IgnoreEnd
      assert text =~ "ABSOLUTELY NO WARRANTY"

      assert Floki.attribute(legal, "a", "href") == [
               Routes.legal_path(conn, :notice),
               Routes.legal_path(conn, :license)
             ]
    end
  end
end
