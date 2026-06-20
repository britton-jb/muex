defmodule Muex.Equivalence do
  @moduledoc """
  Sound detection of equivalent mutants.

  An *equivalent mutant* changes the source but not its observable behaviour, so
  no test can ever kill it. Counting equivalents as survivors deflates the
  mutation score and sends developers chasing phantom "weak tests", so they must
  be dropped before running.

  Detection here is deliberately **sound**: a mutation is only reported as
  equivalent when it provably is. Missing some equivalents (false negatives) is
  acceptable — they merely cost a wasted test run. Wrongly dropping a *killable*
  mutant (a false positive) is not, since it would hide a real testing gap.

  Two layers are consulted:

    1. AST-pattern rules for arithmetic/identity cases that are equivalent by
       construction (`a + 0` vs `a - 0`, `a * 1` vs `a / 1`, `x <<< 0` vs
       `x >>> 0`).
    2. The per-mutator `Muex.Mutator.equivalent?/1` hook and the explicit
       `:equivalent` flag, for cases a mutator declares itself.

  Compiler-level equivalence (mutants that compile to identical BEAM) is handled
  separately by `Muex.Tce`.
  """

  @doc """
  Returns true when `mutation` is provably equivalent to the original code.
  """
  @spec equivalent?(map()) :: boolean()
  def equivalent?(mutation) do
    Map.get(mutation, :equivalent, false) or
      ast_pattern_equivalent?(mutation) or
      Muex.Mutator.equivalent?(mutation)
  end

  @doc """
  Rejects every equivalent mutation from `mutations`, preserving order.
  """
  @spec filter_equivalent([map()]) :: [map()]
  def filter_equivalent(mutations) do
    Enum.reject(mutations, &equivalent?/1)
  end

  defp ast_pattern_equivalent?(%{original_ast: original, ast: mutated}) do
    identity_pair?(original, mutated)
  end

  defp ast_pattern_equivalent?(_mutation), do: false

  # `a + 0` and `a - 0` both equal `a`; likewise the reverse. The identity
  # operand must be the right-hand side (`0 - a` is `-a`, not `a`).
  defp identity_pair?({op1, _, [left1, 0]}, {op2, _, [left2, 0]})
       when op1 in [:+, :-] and op2 in [:+, :-] do
    same_operand?(left1, left2)
  end

  # `a * 1` and `a / 1` both equal `a` (right-hand identity only).
  defp identity_pair?({op1, _, [left1, 1]}, {op2, _, [left2, 1]})
       when op1 in [:*, :/] and op2 in [:*, :/] do
    same_operand?(left1, left2)
  end

  # `x <<< 0` and `x >>> 0` both equal `x` (shifting by zero).
  defp identity_pair?({op1, _, [left1, 0]}, {op2, _, [left2, 0]})
       when op1 in [:<<<, :>>>] and op2 in [:<<<, :>>>] do
    same_operand?(left1, left2)
  end

  defp identity_pair?(_original, _mutated), do: false

  # Compare operands structurally, ignoring AST metadata (line numbers, etc.).
  defp same_operand?(a, b), do: Macro.to_string(a) == Macro.to_string(b)
end
