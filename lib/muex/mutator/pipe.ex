defmodule Muex.Mutator.Pipe do
  @moduledoc """
  Elixir-specific mutator that drops a stage from a pipe chain.

  - `x |> f()` -> `x`

  Each `|>` node yields one mutation that replaces the whole pipe with its
  left-hand side, dropping the right-hand stage. Because `walk/3` visits every
  node, a multi-stage chain (`a |> f |> g`) has each stage dropped in turn as
  the traversal reaches each `|>` node.

  A surviving mutant means a piped transformation has no test asserting on its
  effect.
  """

  @behaviour Muex.Mutator

  @impl true
  def name, do: "Pipe"

  @impl true
  def description, do: "Drops a stage from a pipe chain (x |> f becomes x)"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate({:|>, meta, [left, right]}, context) do
    [
      %{
        original_ast: {:|>, meta, [left, right]},
        ast: left,
        mutator: __MODULE__,
        description: "#{name()}: drop pipe stage",
        location: %{
          file: Map.get(context, :file, "unknown"),
          line: Keyword.get(meta, :line, 0)
        }
      }
    ]
  end

  def mutate(_ast, _context), do: []
end
