defmodule Muex.Mutator.EnumSemantics do
  @moduledoc """
  Elixir-specific mutator that swaps `Enum` functions for their semantic
  opposite.

  - `Enum.filter` <-> `Enum.reject`
  - `Enum.all?`   <-> `Enum.any?`
  - `Enum.min`    <-> `Enum.max`
  - `Enum.take`   <-> `Enum.drop`
  - `Enum.map`    <-> `Enum.each`

  These swaps change observable behaviour (the filtered set, the boolean
  result, the selected element, the returned collection) while remaining
  type-compatible, so a surviving mutant points at a test that does not pin
  down which `Enum` operation the code actually relies on.

  Only the function name is rewritten; the call arguments are preserved.
  """

  @behaviour Muex.Mutator

  @opposites %{
    filter: :reject,
    reject: :filter,
    all?: :any?,
    any?: :all?,
    min: :max,
    max: :min,
    take: :drop,
    drop: :take,
    map: :each,
    each: :map
  }

  @impl true
  def name, do: "EnumSemantics"

  @impl true
  def description, do: "Swaps Enum functions for their semantic opposite"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir]

  @impl true
  def mutate(
        {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, fun]}, call_meta, args},
        context
      )
      when is_map_key(@opposites, fun) do
    opposite = Map.fetch!(@opposites, fun)

    mutated =
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, opposite]}, call_meta, args}

    [
      %{
        original_ast:
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, fun]}, call_meta, args},
        ast: mutated,
        mutator: __MODULE__,
        description: "#{name()}: Enum.#{fun} to Enum.#{opposite}",
        location: %{
          file: Map.get(context, :file, "unknown"),
          line: Keyword.get(call_meta, :line, 0)
        }
      }
    ]
  end

  def mutate(_ast, _context), do: []
end
