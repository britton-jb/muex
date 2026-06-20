defmodule Muex.Mutator.ExtendedMath do
  @moduledoc """
  Mutator for integer division/remainder and bitwise operators that the
  `Arithmetic` mutator (`+`, `-`, `*`, `/`) does not cover.

  Swaps each operator for a related one with different behaviour:

  - `rem` <-> `div`
  - `band` <-> `bor`  (and the operator forms `&&&` <-> `|||`)
  - `bsl` <-> `bsr`   (and the operator forms `<<<` <-> `>>>`)

  Only binary (two-operand) forms are mutated. Module-qualified calls such as
  `Bitwise.band/2` are left alone; the imported operator/function forms are the
  common case.
  """

  @behaviour Muex.Mutator

  @swaps %{
    rem: :div,
    div: :rem,
    band: :bor,
    bor: :band,
    bsl: :bsr,
    bsr: :bsl,
    &&&: :|||,
    |||: :&&&,
    <<<: :>>>,
    >>>: :<<<
  }

  @impl true
  def name, do: "ExtendedMath"

  @impl true
  def description, do: "Mutates integer division/remainder and bitwise operators"

  @impl true
  def supported_languages, do: [Muex.Language.Elixir, Muex.Language.Erlang]

  @impl true
  def mutate({op, meta, [_left, _right] = args}, context) when is_map_key(@swaps, op) do
    swapped = Map.fetch!(@swaps, op)

    [
      %{
        original_ast: {op, meta, args},
        ast: {swapped, meta, args},
        mutator: __MODULE__,
        description: "#{name()}: #{op} to #{swapped}",
        location: %{
          file: Map.get(context, :file, "unknown"),
          line: Keyword.get(meta, :line, 0)
        }
      }
    ]
  end

  def mutate(_ast, _context), do: []
end
