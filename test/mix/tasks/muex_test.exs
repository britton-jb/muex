defmodule Mix.Tasks.MuexTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Muex

  describe "gate/2" do
    test "a run with no mutations is a no-op pass (nothing to assess)" do
      assert Muex.gate(%{results: [], score_low: 0.0, score_high: 0.0}, 80) == :no_mutations
    end

    test "passes when the (pessimistic) score meets the threshold" do
      assert Muex.gate(%{results: [%{}], score_low: 90.0, score_high: 90.0}, 80) == :pass
      assert Muex.gate(%{results: [%{}], score_low: 80.0, score_high: 80.0}, 80) == :pass
    end

    test "fails below threshold, reporting the low bound" do
      assert Muex.gate(%{results: [%{}], score_low: 50.0, score_high: 50.0}, 80) ==
               {:below_threshold, "50.0%"}
    end

    test "renders a range when the score bounds differ" do
      assert Muex.gate(%{results: [%{}], score_low: 70.0, score_high: 90.0}, 80) ==
               {:below_threshold, "70.0%..90.0%"}
    end
  end
end
