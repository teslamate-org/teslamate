defmodule TeslaMate.Version.RevisionTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Version.Revision

  @moduletag :tmp_dir

  @commit "0123456789abcdef0123456789abcdef01234567"

  # A fake git that answers rev-parse and status with the given results.
  defp git(rev_parse, status \\ {"", 0}) do
    fn
      ["rev-parse", "--verify", "HEAD"] -> rev_parse
      ["status", "--porcelain"] -> status
    end
  end

  defp unused_git, do: fn args -> flunk("git #{inspect(args)} must not run") end

  defp repo(%{tmp_dir: root}, git_entry) do
    case git_entry do
      :dir -> File.mkdir!(Path.join(root, ".git"))
      :file -> File.write!(Path.join(root, ".git"), "gitdir: /elsewhere/.git/worktrees/x\n")
      :none -> :ok
    end

    root
  end

  describe "from TESLAMATE_REVISION" do
    test "shortens the commit hash and keeps -dirty", ctx do
      root = repo(ctx, :dir)

      assert Revision.resolve(@commit, root, unused_git()) == "0123456"
      assert Revision.resolve(@commit <> "-dirty", root, unused_git()) == "0123456-dirty"
    end

    test "fails the build on anything but a full commit hash", ctx do
      root = repo(ctx, :none)

      for value <- [
            "",
            " ",
            "unknown",
            "0123456",
            "0123456-dirty",
            "-dirty",
            String.upcase(@commit),
            @commit <> "\n",
            " " <> @commit,
            @commit <> "0",
            @commit <> "-modified",
            @commit <> "-dirty-dirty",
            String.duplicate("0", 64)
          ] do
        assert_raise RuntimeError, ~r/^TESLAMATE_REVISION: expected a full commit hash/, fn ->
          Revision.resolve(value, root, unused_git())
        end
      end
    end
  end

  describe "from git" do
    test "shortens the commit of a clean working tree", ctx do
      assert Revision.resolve(nil, repo(ctx, :dir), git({@commit <> "\n", 0})) == "0123456"
    end

    test "reads a git worktree, whose .git is a file", ctx do
      assert Revision.resolve(nil, repo(ctx, :file), git({@commit <> "\n", 0})) == "0123456"
    end

    test "marks uncommitted changes and untracked files as dirty", ctx do
      root = repo(ctx, :dir)

      for status <- [" M lib/teslamate.ex\n", "?? lib/new.ex\n"] do
        assert Revision.resolve(nil, root, git({@commit, 0}, {status, 0})) == "0123456-dirty"
      end
    end

    # Also guards against reporting the commit of an enclosing repository,
    # such as a source tarball unpacked inside another checkout.
    test "is unknown without a .git entry", ctx do
      assert Revision.resolve(nil, repo(ctx, :none), unused_git()) == "unknown"
    end

    test "is unknown without git", ctx do
      assert Revision.resolve(nil, repo(ctx, :dir), nil) == "unknown"
    end

    test "fails the build if git fails", ctx do
      root = repo(ctx, :dir)

      assert_raise RuntimeError, ~r/^git rev-parse --verify HEAD exited with 128: fatal/, fn ->
        Revision.resolve(nil, root, git({"fatal: detected dubious ownership\n", 128}))
      end

      assert_raise RuntimeError, ~r/^git status --porcelain exited with 128: fatal/, fn ->
        Revision.resolve(nil, root, git({@commit, 0}, {"fatal: index file corrupt\n", 128}))
      end
    end

    test "fails the build if git prints no commit hash", ctx do
      assert_raise RuntimeError, ~r/^git: expected a full commit hash/, fn ->
        Revision.resolve(nil, repo(ctx, :dir), git({"HEAD\n", 0}))
      end
    end
  end
end
