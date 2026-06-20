defmodule Muex.Coverage do
  @moduledoc """
  A line-level coverage index: which test files execute which source lines.

  Used to run, for each mutant, only the tests that actually exercise the
  mutated line — and to skip mutants on lines no test covers (`:no_coverage`)
  rather than wasting a full test run on a mutant nothing can catch.

  The index is a plain map (`%{file => %{line => MapSet of test files}}`); build
  it with `new/0` + `put/4` and query it with `tests_for/3` / `covered?/3`.
  """

  @type t :: %{Path.t() => %{pos_integer() => MapSet.t(Path.t())}}

  @doc "Returns an empty index."
  @spec new() :: t()
  def new, do: %{}

  @doc "Records that `test_file` executes `line` of `file`."
  @spec put(t(), Path.t(), pos_integer(), Path.t()) :: t()
  def put(index, file, line, test_file) do
    Map.update(index, file, %{line => MapSet.new([test_file])}, fn lines ->
      Map.update(lines, line, MapSet.new([test_file]), &MapSet.put(&1, test_file))
    end)
  end

  @doc """
  Returns the test files covering `file:line`.

  `{:covered, sorted_test_files}` when at least one test executes the line,
  `:no_coverage` otherwise.
  """
  @spec tests_for(t(), Path.t(), pos_integer()) :: {:covered, [Path.t()]} | :no_coverage
  def tests_for(index, file, line) do
    case get_in(index, [file, line]) do
      nil -> :no_coverage
      set -> {:covered, set |> MapSet.to_list() |> Enum.sort()}
    end
  end

  @doc "Whether any test covers `file:line`."
  @spec covered?(t(), Path.t(), pos_integer()) :: boolean()
  def covered?(index, file, line), do: tests_for(index, file, line) != :no_coverage
end
