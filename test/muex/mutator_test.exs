defmodule Muex.MutatorTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator

  @context %{file: "lib/example.ex"}

  defp quoted(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    ast
  end

  describe "walk/3 traversal" do
    test "stamps :original_ast onto every mutation from the matched node" do
      ast = quoted("-x")

      [mutation] = Mutator.walk(ast, [Mutator.InvertNegatives], @context)

      # InvertNegatives replaces `-x` with its operand `x`...
      assert mutation.ast == quoted("x")
      # ...and walk/3 records the node that was matched, not the mutator's guess.
      assert mutation.original_ast == ast
    end

    test "descends into nested nodes, mutating each matching one" do
      # A three-stage pipe has two `|>` nodes, so Pipe drops a stage at each.
      ast = quoted("a |> f() |> g()")

      mutations = Mutator.walk(ast, [Mutator.Pipe], @context)

      assert length(mutations) == 2
      assert Enum.all?(mutations, &Map.has_key?(&1, :original_ast))
      # Every stamped original_ast is one of the pipe nodes actually in the tree.
      assert Enum.all?(mutations, &match?({:|>, _, _}, &1.original_ast))
    end

    test "composes multiple mutators over the same node" do
      ast = quoted("x > 0")

      mutators = [Mutator.Comparison, Mutator.NegateConditionals]
      mutations = Mutator.walk(ast, mutators, @context)

      # Comparison yields `<` and `>=`; NegateConditionals yields the complement `<=`.
      produced = Enum.map(mutations, fn %{ast: {op, _, _}} -> op end)
      assert :< in produced
      assert :>= in produced
      assert :<= in produced
      assert Enum.all?(mutations, &(&1.original_ast == ast))
    end

    test "returns no mutations when nothing in the tree matches" do
      ast = quoted("String.upcase(name)")

      assert [] = Mutator.walk(ast, [Mutator.Pipe, Mutator.InvertNegatives], @context)
    end
  end
end
