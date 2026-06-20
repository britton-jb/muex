defmodule Muex.MutatorTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator

  # Uses an existing mutator module purely as a name source (name/0 -> "Comparison").
  @mutator Muex.Mutator.Comparison

  describe "build_mutation/5" do
    test "builds a mutation map with a name-prefixed description" do
      mutation =
        Mutator.build_mutation(@mutator, {:x, [], nil}, "a to b", %{file: "lib/m.ex"}, 7)

      assert mutation.ast == {:x, [], nil}
      assert mutation.mutator == @mutator
      assert mutation.description == "Comparison: a to b"
      assert mutation.location == %{file: "lib/m.ex", line: 7}
    end

    test "defaults the file to \"unknown\" when context has none" do
      mutation = Mutator.build_mutation(@mutator, :mutated, "d", %{}, 0)
      assert mutation.location.file == "unknown"
    end

    # original_ast is intentionally NOT set here: Muex.Mutator.walk/3 stamps it
    # onto every mutation from the matched node, so mutators must not duplicate it.
    test "does not set :original_ast (walk/3 owns that field)" do
      mutation = Mutator.build_mutation(@mutator, :mutated, "d", %{}, 1)
      refute Map.has_key?(mutation, :original_ast)
    end
  end
end
