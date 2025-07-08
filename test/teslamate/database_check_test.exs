defmodule TeslaMate.DatabaseCheckTest do
  use ExUnit.Case, async: true

  import TeslaMate.DatabaseCheck, only: [normalize_version: 1]

  describe "normalize_version/1" do
    test "without minor and patch" do
      assert normalize_version("16") == "16.0.0"
    end

    test "with minor" do
      assert normalize_version("16.7") == "16.7.0"
    end

    test "with minor and patch" do
      assert normalize_version("16.7.1") == "16.7.1"
    end

    test "with beta-prefix" do
      assert normalize_version("17.7.3beta1") == "17.7.3-beta1"
    end

    test "with rc-prefix" do
      assert normalize_version("17.8.1rc2") == "17.8.1-rc2"
    end

    test "invalid format leads to error" do
      assert_raise RuntimeError,
                   "Invalid PostgreSQL version format: 18rc1",
                   fn -> normalize_version("18rc1") end
    end
  end
end
