defmodule TeslaMate.Version do
  @moduledoc """
  The version this build was compiled with, from the repository `VERSION` file,
  and the commit it was built from (see `TeslaMate.Version.Revision`).

  Read them through the functions here. A module that copies
  `Mix.Project.config()[:version]` into its own attribute keeps that string
  until its source changes, so a `VERSION` bump leaves the old one in place.
  """

  alias TeslaMate.Version.Revision

  # VERSION lives outside this file. Without this, Mix will not rebuild the
  # module when the version changes.
  @external_resource Path.expand("../../../VERSION", __DIR__)
  @version Mix.Project.config()[:version]

  @root Path.expand("../../..", __DIR__)
  @revision Revision.current(@root)

  @doc "The version, for comparing and for machines (SemVer)."
  @spec version() :: String.t()
  def version, do: @version

  @doc "The commit this build was made from, such as `abcd123`."
  @spec revision() :: String.t()
  def revision, do: @revision

  @doc "The version and the commit, for people, such as `4.5.0 (abcd123)`."
  @spec describe() :: String.t()
  def describe, do: "#{@version} (#{@revision})"

  # A commit, a rebase or an edit changes the revision without touching this
  # file. Mix asks this before each compile and rebuilds the module if true.
  @doc false
  def __mix_recompile__?, do: Revision.current(@root) != @revision
end
