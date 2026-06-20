defmodule Muex.Mutator.CaseClause do
  @moduledoc """
  Elixir-specific mutator that deletes a clause from a `case` expression.

  For a `case` with two or more clauses, produces one mutation per clause that
  removes that clause from the branch list. Cases with a single clause are left
  untouched (there is nothing to delete).

  Like `StatementDeletion`, this is a high-value operator: if removing a branch
  doesn't fail any test, that branch is either unreachable or its behaviour is
  unasserted. Patterns and bodies *within* surviving clauses are still mutated
  independently by their own mutators via `walk/3`.
  """

  @behaviour Muex.Mutator

  @impl true
  def name, do: "CaseClause"

  @impl true
  def description, do: "Deletes a clause from a case expression"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate({:case, meta, [subject, [do: clauses]]}, context)
      when is_list(clauses) and length(clauses) >= 2 do
    total = length(clauses)

    clauses
    |> Enum.with_index()
    |> Enum.map(fn {_clause, index} ->
      remaining = List.delete_at(clauses, index)

      %{
        original_ast: {:case, meta, [subject, [do: clauses]]},
        ast: {:case, meta, [subject, [do: remaining]]},
        mutator: __MODULE__,
        description: "#{name()}: delete clause #{index + 1} of #{total}",
        location: %{
          file: Map.get(context, :file, "unknown"),
          line: Keyword.get(meta, :line, 0)
        }
      }
    end)
  end

  def mutate(_ast, _context), do: []
end
