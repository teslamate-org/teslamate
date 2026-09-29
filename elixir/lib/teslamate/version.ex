defmodule TeslaMate.Version do
  @moduledoc """
  The version this build was compiled with, from the repository `VERSION` file.

  Read it through `version/0`. A module that copies
  `Mix.Project.config()[:version]` into its own attribute keeps that string
  until its source changes, so a `VERSION` bump leaves the old one in place.
  """

  # VERSION lives outside this file. Without this, Mix will not rebuild the
  # module when the version changes.
  @external_resource Path.expand("../../../VERSION", __DIR__)
  @version Mix.Project.config()[:version]

  @spec version() :: String.t()
  def version, do: @version
end
