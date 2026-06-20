defmodule Muex.Mutator.MapSemantics do
  @moduledoc """
  Elixir-specific mutator that swaps `put`/`put_new` on `Map` and `Keyword`.

  - `Map.put` <-> `Map.put_new`
  - `Keyword.put` <-> `Keyword.put_new`

  `put` always writes; `put_new` writes only when the key is absent. They have
  the same arity and return type, so a surviving mutant means no test exercises
  the case where the key is already present — a common real-world bug.

  Only module-qualified calls on `Map`/`Keyword` are matched; the call
  arguments are preserved.
  """

  @behaviour Muex.Mutator

  @opposites %{put: :put_new, put_new: :put}
  @modules [:Map, :Keyword]

  @impl true
  def name, do: "MapSemantics"

  @impl true
  def description, do: "Swaps Map/Keyword put for put_new"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate(
        {{:., dot_meta, [{:__aliases__, alias_meta, [mod]}, fun]}, call_meta, args},
        context
      )
      when mod in @modules and is_map_key(@opposites, fun) do
    opposite = Map.fetch!(@opposites, fun)

    mutated =
      {{:., dot_meta, [{:__aliases__, alias_meta, [mod]}, opposite]}, call_meta, args}

    [
      %{
        original_ast: {{:., dot_meta, [{:__aliases__, alias_meta, [mod]}, fun]}, call_meta, args},
        ast: mutated,
        mutator: __MODULE__,
        description: "#{name()}: #{mod}.#{fun} to #{mod}.#{opposite}",
        location: %{
          file: Map.get(context, :file, "unknown"),
          line: Keyword.get(call_meta, :line, 0)
        }
      }
    ]
  end

  def mutate(_ast, _context), do: []
end
