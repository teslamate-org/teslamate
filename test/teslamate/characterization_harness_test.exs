defmodule TeslaMate.CharacterizationHarnessTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Characterization

  describe "record_mode/1" do
    test "absent, empty, 0 and false mean off" do
      for value <- [nil, "", "0", "false"] do
        assert Characterization.record_mode(value) == :off
      end
    end

    test "1 and true record missing goldens" do
      assert Characterization.record_mode("1") == :missing
      assert Characterization.record_mode("true") == :missing
    end

    test "all re-records everything" do
      assert Characterization.record_mode("all") == :all
    end

    test "only:<name> targets one golden, tree-scoped — identifiers cannot collide with modes" do
      assert Characterization.record_mode("only:drive") == {:only, {:content, "drive"}}
      assert Characterization.record_mode("only:all") == {:only, {:content, "all"}}

      assert Characterization.record_mode("only:selftest/pipeline") ==
               {:only, {:selftest, "pipeline"}}
    end

    test "unknown values raise instead of silently selecting a mode" do
      assert_raise ArgumentError, fn -> Characterization.record_mode("yes") end
      assert_raise ArgumentError, fn -> Characterization.record_mode("only:") end
      assert_raise ArgumentError, fn -> Characterization.record_mode("only:selftest/") end
    end
  end

  describe "canonical_payload/1" do
    test "scalar payloads stay untouched strings" do
      assert Characterization.canonical_payload("80") == "80"
      assert Characterization.canonical_payload("true") == "true"
      assert Characterization.canonical_payload("online") == "online"
    end

    test "JSON objects and arrays are stored decoded" do
      assert Characterization.canonical_payload(~s({"b":1,"a":2})) == %{"a" => 2, "b" => 1}
      assert Characterization.canonical_payload("[1,2]") == [1, 2]
    end

    test "invalid JSON that merely looks structural is kept verbatim" do
      assert Characterization.canonical_payload("{not json") == "{not json"
    end
  end

  describe "canonical_order/1" do
    test "encodes with sorted keys at every depth" do
      encoded =
        %{"b" => 1, "a" => %{"d" => [%{"z" => 1, "y" => 2}], "c" => 2}}
        |> Characterization.canonical_order()
        |> Jason.encode!()

      assert encoded == ~s({"a":{"c":2,"d":[{"y":2,"z":1}]},"b":1})
    end
  end

  describe "mask_volatile/2" do
    test "identical values survive" do
      assert Characterization.mask_volatile(%{"a" => 1}, %{"a" => 1}) == %{"a" => 1}
    end

    test "differing values are masked" do
      assert Characterization.mask_volatile(%{"a" => 1}, %{"a" => 2}) == %{"a" => "<volatile>"}
    end

    test "keys are taken from both runs — a one-sided key is masked, not dropped" do
      assert Characterization.mask_volatile(%{"a" => 1}, %{"b" => 1}) ==
               %{"a" => "<volatile>", "b" => "<volatile>"}
    end

    test "lists of equal length mask element-wise, unequal length collapses" do
      assert Characterization.mask_volatile([1, 2], [1, 3]) == [1, "<volatile>"]
      assert Characterization.mask_volatile([1], [1, 2]) == "<volatile>"
    end
  end

  describe "diff/2" do
    test "equal structures diff to nil" do
      assert Characterization.diff(%{"a" => [1, %{"b" => 2}]}, %{"a" => [1, %{"b" => 2}]}) == nil
    end

    test "reports the path to the first divergence" do
      assert {["a", "[1]", "b"], 2, 3} =
               Characterization.diff(%{"a" => [1, %{"b" => 2}]}, %{"a" => [1, %{"b" => 3}]})
    end

    test "a masked position accepts any actual value" do
      assert Characterization.diff(%{"a" => "<volatile>"}, %{"a" => 42}) == nil
    end

    test "a key missing on either side is a divergence" do
      assert {["a"], 1, :__missing__} = Characterization.diff(%{"a" => 1}, %{})
      assert {["a"], :__missing__, 1} = Characterization.diff(%{}, %{"a" => 1})
    end
  end
end
