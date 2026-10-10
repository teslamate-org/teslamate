defmodule TeslaMateWeb.LegalController do
  use TeslaMateWeb, :controller

  # Embedded at compile time, so that every build serves the NOTICE and LICENSE
  # it was built from. Both live in the repository root.
  @notice_path Path.expand("../../../../NOTICE", __DIR__)
  @license_path Path.expand("../../../../LICENSE", __DIR__)
  @external_resource @notice_path
  @external_resource @license_path
  @notice File.read!(@notice_path)
  @license File.read!(@license_path)

  def notice(conn, _params), do: text(conn, @notice)

  def license(conn, _params), do: text(conn, @license)
end
