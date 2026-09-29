defmodule TeslaMate.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../config/runtime.exs", __DIR__)

  setup do
    socket_dir = System.get_env("DATABASE_SOCKET_DIR")
    ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)

    # runtime.exs defines the Util module, which reading it again redefines
    Code.put_compiler_option(:ignore_module_conflict, true)

    on_exit(fn ->
      Code.put_compiler_option(:ignore_module_conflict, ignore_module_conflict)

      case socket_dir do
        nil -> System.delete_env("DATABASE_SOCKET_DIR")
        dir -> System.put_env("DATABASE_SOCKET_DIR", dir)
      end
    end)
  end

  describe "DATABASE_SOCKET_DIR" do
    test "connects through the socket in the given directory" do
      System.put_env("DATABASE_SOCKET_DIR", "/run/postgresql")

      config = Config.Reader.read!(@runtime_config, env: :test)

      assert config[:teslamate][TeslaMate.Repo][:socket_dir] == "/run/postgresql"
    end

    test "rejects an empty value" do
      System.put_env("DATABASE_SOCKET_DIR", "")

      assert_raise RuntimeError, ~r/DATABASE_SOCKET_DIR must not be empty/, fn ->
        Config.Reader.read!(@runtime_config, env: :test)
      end
    end
  end
end
