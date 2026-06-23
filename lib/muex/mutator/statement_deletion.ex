defmodule Muex.Mutator.StatementDeletion do
  @moduledoc """
  Mutator that removes individual statements from blocks.

  Targets `__block__` nodes with two or more statements. For each
  non-final statement, produces a mutation that deletes it from the block.
  The final statement (the return value) is left to the ReturnValue mutator.

  This is one of the highest-value mutation operators: if deleting a
  statement doesn't cause any test to fail, that statement is either
  dead code or untested side-effect logic.

  ## Module attributes are not mutated

  A `defmodule` body is itself a `__block__`, so without a guard this
  mutator would delete `@moduledoc` / `@doc` / `@spec` / `@type` /
  `@behaviour` / constant attributes. Deleting a non-executable attribute
  (docs, specs, types) has no runtime effect, so it can never be caught by
  a test — it only manufactures unkillable survivors that drag the score
  down without pointing at a real coverage gap. Deleting a *used* constant
  attribute (`@timeout 5_000`) just yields a guaranteed compile error
  (an "invalid" mutant). Neither is a meaningful test-quality signal, so
  `@`-attribute statements are skipped entirely.
  """
  @behaviour Muex.Mutator

  @impl true
  def name, do: "StatementDeletion"

  @impl true
  def description, do: "Deletes individual statements from blocks"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({:__block__, meta, statements}, context) when length(statements) >= 2 do
    last_idx = length(statements) - 1

    statements
    |> Enum.with_index()
    # Skip the last statement (that's the return value, handled by ReturnValue)
    # and skip module attributes (@moduledoc/@doc/@spec/@type/@behaviour/consts):
    # deleting a non-executable attribute can't be caught by any test, so it only
    # produces unkillable survivors. See the moduledoc.
    |> Enum.reject(fn {stmt, idx} -> idx == last_idx or module_attribute?(stmt) end)
    |> Enum.map(fn {stmt, idx} ->
      remaining = List.delete_at(statements, idx)
      mutated_ast = simplify_block(meta, remaining)
      stmt_line = get_statement_line(stmt)

      build_mutation(
        mutated_ast,
        "delete statement #{idx + 1} of #{length(statements)}",
        context,
        stmt_line
      )
    end)
  end

  def mutate(_ast, _context), do: []

  # A `@`-prefixed module attribute (@moduledoc, @doc, @spec, @type,
  # @behaviour, @enforce_keys, named constants, …). Deleting one is never a
  # useful mutation: docs/specs/types are non-executable (unkillable
  # survivors) and used constants only break compilation (invalid mutants).
  defp module_attribute?({:@, _meta, _args}), do: true
  defp module_attribute?(_), do: false

  # A block with one remaining statement collapses to that statement.
  defp simplify_block(_meta, [single]), do: single
  defp simplify_block(meta, stmts), do: {:__block__, meta, stmts}

  defp get_statement_line({_form, meta, _args}) when is_list(meta) do
    Keyword.get(meta, :line, 0)
  end

  defp get_statement_line(_), do: 0

  defp build_mutation(mutated_ast, description, context, line) do
    %{
      ast: mutated_ast,
      mutator: __MODULE__,
      description: "#{name()}: #{description}",
      location: %{file: Map.get(context, :file, "unknown"), line: line}
    }
  end
end
