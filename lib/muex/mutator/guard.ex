defmodule Muex.Mutator.Guard do
  @moduledoc """
  Elixir-specific mutator that removes a `when` guard constraint.

  - `def f(x) when <guard>` -> `def f(x) when true`

  Replaces the guard expression of a `when` clause with the literal `true`, so
  the clause matches unconditionally. Type guards (`is_integer/1`, `is_binary/1`,
  …) and custom guard expressions are otherwise invisible to the operator-level
  mutators, so a surviving mutant here means a guard's constraint is never
  exercised by the tests.

  Comparison and boolean sub-expressions *inside* a guard are still mutated
  independently by their own mutators as `walk/3` traverses into them.
  """

  @behaviour Muex.Mutator

  @impl true
  def name, do: "Guard"

  @impl true
  def description, do: "Removes a when guard by replacing it with true"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate({:when, meta, [head, guard]}, context) do
    [
      %{
        original_ast: {:when, meta, [head, guard]},
        ast: {:when, meta, [head, true]},
        mutator: __MODULE__,
        description: "#{name()}: replace guard with true",
        location: %{
          file: Map.get(context, :file, "unknown"),
          line: Keyword.get(meta, :line, 0)
        }
      }
    ]
  end

  def mutate(_ast, _context), do: []
end
