defmodule TeslaMateWeb.GeoFenceView do
  use TeslaMateWeb, :view

  alias TeslaMateWeb.GeoFenceLive
  alias TeslaMate.Log.Car

  import TeslaMate.Convert, only: [m_to_ft: 1]
end
