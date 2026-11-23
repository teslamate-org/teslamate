defmodule TeslaMate.Version.Revision do
  @moduledoc """
  The commit a build was made from, as shown next to the version.

  This is the only place that produces its format: the short hash
  (`abcd123`), `abcd123-dirty` for a build with uncommitted changes, or
  `unknown` when no commit is available. Every build path hands in the full
  hash, so the hash is shortened here and nowhere else.

  The commit comes from the first of:

    1. The `TESLAMATE_REVISION` environment variable, for builds without a git
       checkout (Docker, Nix, CI). It must hold a full lowercase commit hash,
       optionally followed by `-dirty`. Any other value, the empty string
       included, fails the build.
    2. git, if the repository root has a `.git` entry (a directory, or a file
       in a git worktree) and git is installed. Any output of `git status`
       makes the build dirty, untracked files included: Mix compiles those as
       well. If git fails or prints no commit hash, the build fails.
    3. `unknown` otherwise.
  """

  @env "TESLAMATE_REVISION"
  @short_length 7
  @valid ~r/\A[0-9a-f]{40}(-dirty)?\z/

  @typedoc "Runs git with the given arguments, as `System.cmd/3` does."
  @type git :: ([String.t()] -> {Collectable.t(), non_neg_integer()})

  @doc "The revision of the repository at `root`, from the sources above."
  @spec current(Path.t()) :: String.t()
  def current(root) do
    git =
      case System.find_executable("git") do
        nil -> nil
        path -> &System.cmd(path, ["-C", root, "--no-optional-locks" | &1])
      end

    resolve(System.get_env(@env), root, git)
  end

  @doc """
  The revision from the given `TESLAMATE_REVISION` value, or else from `git`
  in the repository at `root`. `git` is `nil` when git is not installed.
  """
  @spec resolve(String.t() | nil, Path.t(), git() | nil) :: String.t()
  def resolve(value, _root, _git) when is_binary(value), do: parse!(value, @env)

  def resolve(nil, root, git) do
    if git != nil and File.exists?(Path.join(root, ".git")) do
      commit = run!(git, ["rev-parse", "--verify", "HEAD"])
      dirty? = run!(git, ["status", "--porcelain"]) != ""

      parse!(if(dirty?, do: commit <> "-dirty", else: commit), "git")
    else
      "unknown"
    end
  end

  defp run!(git, args) do
    case git.(args) do
      {output, 0} ->
        String.trim(output)

      # git writes its error to stderr, which System.cmd/3 passes through to
      # the build output; stdout may still say something.
      {output, status} ->
        raise String.trim_trailing(
                "git #{Enum.join(args, " ")} exited with #{status}: #{String.trim(output)}",
                ": "
              )
    end
  end

  defp parse!(value, source) do
    if value =~ @valid do
      binary_part(value, 0, @short_length) <> binary_part(value, 40, byte_size(value) - 40)
    else
      raise "#{source}: expected a full commit hash, optionally followed by -dirty, " <>
              "found #{inspect(value)}"
    end
  end
end
