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

  @doc "Records that `test_file` executes every line in `lines` of `file`."
  @spec put_lines(t(), Path.t(), [pos_integer()], Path.t()) :: t()
  def put_lines(index, file, lines, test_file) do
    Enum.reduce(lines, index, fn line, idx -> put(idx, file, line, test_file) end)
  end

  @doc "Whether any test covers `file:line`."
  @spec covered?(t(), Path.t(), pos_integer()) :: boolean()
  def covered?(index, file, line), do: tests_for(index, file, line) != :no_coverage

  @doc """
  Extracts the executed line numbers from a `:cover.analyse(_, :calls, :line)`
  result, i.e. the lines with a non-zero call count.
  """
  @spec covered_lines([{{module(), pos_integer()}, non_neg_integer()}]) :: [pos_integer()]
  def covered_lines(line_analysis) do
    for {{_module, line}, calls} <- line_analysis, calls > 0, do: line
  end

  @doc """
  Builds a coverage index by running each test file under `:cover` and recording
  which source lines it executes.

  For every file in `test_files`, runs `mix test <file> --cover --export-coverage`
  in a subprocess, then analyses each module in `file_to_module` and attributes
  its executed lines to that test file. Returns a `t()` index.

  Options: `:cd` (project root, default `File.cwd!/0`).
  """
  @spec collect([Path.t()], %{Path.t() => module()}, keyword()) :: t()
  def collect(test_files, file_to_module, opts \\ []) do
    cd = Keyword.get(opts, :cd, File.cwd!())
    module_to_path = invert(file_to_module)
    ensure_cover_started()

    Enum.reduce(test_files, new(), fn test_file, index ->
      case run_with_coverage(test_file, cd) do
        {:ok, coverdata} -> merge_coverage(index, test_file, coverdata, module_to_path)
        :error -> index
      end
    end)
  end

  defp invert(file_to_module) do
    for {path, module} <- file_to_module, not is_nil(module), into: %{}, do: {module, path}
  end

  defp ensure_cover_started do
    case :cover.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp run_with_coverage(test_file, cd) do
    name = "muex_cov_#{System.unique_integer([:positive])}"

    case System.cmd("mix", ["test", test_file, "--cover", "--export-coverage", name],
           cd: cd,
           env: [{"MIX_ENV", "test"}],
           stderr_to_stdout: true
         ) do
      # 0 = all passed, 1 = some failed; both still produce coverage data.
      {_out, code} when code in [0, 1] ->
        path = Path.join([cd, "cover", "#{name}.coverdata"])
        if File.exists?(path), do: {:ok, path}, else: :error

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp merge_coverage(index, test_file, coverdata, module_to_path) do
    :cover.reset()
    :cover.import(String.to_charlist(coverdata))

    Enum.reduce(module_to_path, index, fn {module, path}, idx ->
      case :cover.analyse(module, :calls, :line) do
        {:ok, line_analysis} -> put_lines(idx, path, covered_lines(line_analysis), test_file)
        _ -> idx
      end
    end)
  end
end
