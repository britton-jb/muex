defmodule Mix.Tasks.Muex do
  @moduledoc """
  Run mutation testing on your project.

  ## Usage

      mix muex [options]

  ## Options

    * `--files` - Directory, file, or glob pattern (default: "lib")
    * `--path` - Synonym for --files
    * `--app` - Target a specific app in an umbrella project (sets --files and --test-paths automatically)
    * `--test-paths` - Comma-separated test directories, files, or glob patterns (default: "test")
    * `--language` - Language adapter to use (default: "elixir")
    * `--mutators` - Comma-separated list of mutators (default: all)
    * `--concurrency` - Number of parallel mutations (default: number of schedulers)
    * `--timeout` - Test timeout in milliseconds (default: 10000)
    * `--fail-at` - Minimum mutation score to pass (default: 80)
    * `--format` - Output format: terminal, json, html (default: terminal)
    * `--min-score` - Minimum complexity score for files to include (default: 20)
    * `--max-mutations` - Maximum number of mutations to test (0 = unlimited, default: 0)
    * `--no-filter` - Disable intelligent file filtering
    * `--verbose` - Show detailed progress information (file analysis, optimization, etc.)
    * `--optimize` - Enable mutation optimization heuristics (default: enabled)
    * `--no-optimize` - Disable mutation optimization heuristics
    * `--no-tce` - Disable Trivial Compiler Equivalence skipping (default: enabled)
    * `--since` - Only mutate lines changed since a git ref (e.g. `--since main`),
      i.e. the lines added/modified on this branch. Ideal for PR/CI runs.
    * `--coverage-guided` - Run each mutant only against the tests that cover its
      line, and skip mutants on uncovered lines. Collects per-test coverage up
      front (one run per test file), so it trades startup cost for faster runs.

  ## Score precision and CI gates

  Provably-equivalent mutants (which no test can ever kill) are always dropped,
  regardless of optimization, so they never distort the score.

  `--optimize` additionally *samples* the remaining mutants (clustering and
  per-function caps) to run faster. This makes the reported score an
  **estimate** — the same code can report different scores at different
  optimization levels. That is fine for a quick local check, but for a hard
  `--fail-at` gate in CI you want the exact score, so run with `--no-optimize`:

      mix muex --no-optimize --fail-at 80   # exact score, suitable for a CI gate
    * `--optimize-level` - Optimization preset: conservative, balanced, aggressive (default: balanced)
    * `--min-complexity` - Minimum complexity for mutations (default: 2, with --optimize)
    * `--max-per-function` - Max mutations per function (default: 20, with --optimize)

  ## Examples

      mix muex                          # Run with intelligent filtering
      mix muex --no-filter                # Run on all files
      mix muex --files "lib/muex"          # Specific directory
      mix muex --files "lib/muex/*.ex"     # Glob pattern
      mix muex --mutators arithmetic,comparison
      mix muex --fail-at 80               # Fail below 80%
      mix muex --format json              # JSON output
      mix muex --format html              # HTML report
      mix muex --verbose                  # Detailed progress
      mix muex --optimize --optimize-level aggressive
      mix muex --app my_app               # Umbrella: specific app
      mix muex --test-paths "test/unit,test/integration"
      mix muex --files "lib/my_module.ex" --test-paths "test/my_module_test.exs"
  """

  use Mix.Task

  @shortdoc "Run mutation testing"
  @impl Mix.Task
  def run(args) do
    case Muex.Config.from_args(args) do
      {:error, reason} ->
        Mix.raise(reason)

      {:ok, config} ->
        case Muex.run(config) do
          {:error, reason} ->
            Mix.raise(reason)

          {:ok, result} ->
            case gate(result, config.fail_at) do
              :no_mutations ->
                Mix.shell().info("No mutations to test — nothing to score.")

              :pass ->
                :ok

              {:below_threshold, score_str} ->
                Mix.raise("Mutation score #{score_str} is below threshold #{config.fail_at}%")
            end
        end
    end
  end

  @doc false
  # Decides the outcome of a run against the fail-at threshold. A run with no
  # mutations (e.g. `--since` with no relevant changes) is a no-op pass, not a
  # failure. Uses the pessimistic (low) bound: if even the best-case
  # interpretation falls short, the score is too low.
  @spec gate(map(), number()) :: :no_mutations | :pass | {:below_threshold, String.t()}
  def gate(%{results: []}, _fail_at), do: :no_mutations

  def gate(%{score_low: score_low, score_high: score_high}, fail_at) do
    if score_low < fail_at do
      score_str =
        if score_low == score_high,
          do: "#{score_low}%",
          else: "#{score_low}%..#{score_high}%"

      {:below_threshold, score_str}
    else
      :pass
    end
  end
end
