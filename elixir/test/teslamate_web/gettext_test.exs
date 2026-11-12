defmodule TeslaMateWeb.GettextTest do
  use ExUnit.Case, async: true

  test "Korean software update messages preserve the reported percentage" do
    Gettext.with_locale(TeslaMateWeb.Gettext, "ko", fn ->
      for percent <- [0, 60, 100] do
        assert Gettext.dgettext(TeslaMateWeb.Gettext, "default", "Downloading %{percent}%", %{
                 percent: percent
               }) == "다운로드 중 #{percent}%"

        assert Gettext.dgettext(TeslaMateWeb.Gettext, "default", "Installing %{percent}%", %{
                 percent: percent
               }) == "설치 중 #{percent}%"
      end
    end)
  end
end
