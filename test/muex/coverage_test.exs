defmodule Muex.CoverageTest do
  use ExUnit.Case, async: true

  alias Muex.Coverage

  describe "building and querying an index" do
    setup do
      index =
        Coverage.new()
        |> Coverage.put("lib/a.ex", 10, "test/a_test.exs")
        |> Coverage.put("lib/a.ex", 10, "test/b_test.exs")
        |> Coverage.put("lib/a.ex", 11, "test/a_test.exs")

      %{index: index}
    end

    test "tests_for returns the covering test files for a line, sorted", %{index: index} do
      assert Coverage.tests_for(index, "lib/a.ex", 10) ==
               {:covered, ["test/a_test.exs", "test/b_test.exs"]}

      assert Coverage.tests_for(index, "lib/a.ex", 11) == {:covered, ["test/a_test.exs"]}
    end

    test "tests_for returns :no_coverage for a line no test executes", %{index: index} do
      assert Coverage.tests_for(index, "lib/a.ex", 99) == :no_coverage
      assert Coverage.tests_for(index, "lib/other.ex", 10) == :no_coverage
    end

    test "put is idempotent for the same (file, line, test)", %{index: index} do
      index = Coverage.put(index, "lib/a.ex", 10, "test/a_test.exs")

      assert Coverage.tests_for(index, "lib/a.ex", 10) ==
               {:covered, ["test/a_test.exs", "test/b_test.exs"]}
    end

    test "covered?/3 reflects whether any test covers the line", %{index: index} do
      assert Coverage.covered?(index, "lib/a.ex", 10)
      refute Coverage.covered?(index, "lib/a.ex", 99)
    end
  end

  test "new/0 is empty" do
    assert Coverage.tests_for(Coverage.new(), "lib/a.ex", 1) == :no_coverage
  end
end
