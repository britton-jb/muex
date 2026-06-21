# Muex

Mutation testing library for Elixir, Erlang, and other BEAM languages.

Muex evaluates **test-suite quality** by introducing deliberate bugs (mutations) into your code and verifying that your tests catch them. A *killed* mutant means a test failed (good — your tests noticed the change); a *survived* mutant means no test noticed a real behavioural change (a gap in your tests). It provides a language-agnostic architecture with dependency injection, making it easy to extend support to new languages.

## Features

- Language-agnostic architecture with pluggable language adapters
- Built-in support for Elixir and Erlang
- **18 mutators** — a PITest-style core plus Elixir-specific operators (pipes, guards, `case`/`cond`/`with` clauses, `Enum`/`Map` semantics). See [Mutators](#mutators).
- **Sound equivalent-mutant handling** — equivalent mutants (which no test can ever kill) are detected and excluded from the score via AST rules **and** Trivial Compiler Equivalence (TCE — compares compiled BEAM). Always on; never inflates or deflates the score. See [Equivalent-mutant handling](#equivalent-mutant-handling).
- **Incremental `--since <ref>`** — mutate only the lines changed on a branch (line-precise, via the git diff). Ideal for per-PR CI gates. See [Incremental mode](#incremental-mode---since).
- **Coverage-guided execution** — run each mutant only against the tests that cover its line, skip mutants on uncovered lines, and short-circuit on the first failure. See [Coverage-guided execution](#coverage-guided-execution).
- **Honest CI gates** — `--fail-at` with an exact (un-sampled) score via `--no-optimize`. See [Score precision & CI gates](#score-precision--ci-gates).
- Intelligent file filtering to focus on business logic:
  - Analyzes code complexity and characteristics
  - Automatically excludes framework code (behaviours, protocols, supervisors)
  - Skips low-complexity files (Mix tasks, reporters, configurations)
  - Prioritizes files with testable logic (conditionals, arithmetic, pattern matching)
- Parallel mutation execution with configurable concurrency and per-file sandboxing
- Optional mutation-count optimization heuristics (50-70% reduction)
- Colored terminal output with mutation scores, plus JSON and HTML reports
- Integration with ExUnit; hot module swapping for efficient testing

## Installation

Muex can be installed in several ways.

### With Igniter (recommended)

```bash
mix igniter.install muex
```

This adds the dependency and runs the installer (`mix muex.install`), which adds muex's generated artifacts (`cover/`, `muex-report.{json,html}`) to your `.gitignore`. If muex is already a dependency, just run `mix muex.install`.

### As a Mix dependency (good for CI/CD)

Add `muex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:muex, "~> 0.6", only: [:dev, :test], runtime: false}
  ]
end
```

Then run:

```bash
mix deps.get
mix muex
```

### As a hex archive (good for global use)

Install globally to use across all your projects:

```bash
mix archive.install hex muex
```

This makes `mix muex` available in any Elixir project without adding it as a dependency.

### As an escript (standalone binary)

For standalone usage or distribution:

```bash
# From the muex repository
mix escript.build

# Install system-wide
sudo cp muex /usr/local/bin/

# Use in any project
cd /path/to/your/project
muex
```

For detailed installation instructions and a comparison of these methods, see [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Usage

Run mutation testing on your project:

```bash
# Using the mix task (dependency or hex archive)
mix muex

# Using the escript (standalone binary)
muex
```

Both commands accept the same options and produce identical results.

By default, Muex intelligently filters files to focus on business logic and skip framework code. This dramatically reduces the number of mutations tested.

### File Filtering Options

```bash
# Use intelligent filtering (default)
mix muex

# Show which files are included/excluded
mix muex --verbose

# Adjust minimum complexity score (default: 20)
mix muex --min-score 30

# Disable filtering to test all files
mix muex --no-filter

# Limit total mutations tested
mix muex --max-mutations 500
```

### File Selection

```bash
# Run on a specific directory
mix muex --files "lib/myapp"

# Run on a specific file
mix muex --files "lib/my_module.ex"

# Run on files matching a glob pattern (single level)
mix muex --files "lib/muex/*.ex"

# Run on files matching a recursive glob pattern
mix muex --files "lib/**/compiler*.ex"
mix muex --files "lib/{muex,mix}/**/*.ex"

# Pair specific files with specific tests
mix muex --files "lib/my_module.ex" --test-paths "test/my_module_test.exs"
```

### Other Options

```bash
# Use specific mutators
mix muex --mutators arithmetic,comparison,boolean

# Set concurrency and timeout
mix muex --concurrency 4 --timeout 10000

# Fail if the mutation score is below a threshold
mix muex --fail-at 80

# Enable mutation optimization (balanced preset)
mix muex --optimize

# Use conservative optimization (best balance)
mix muex --optimize --optimize-level conservative

# Use aggressive optimization (fastest)
mix muex --optimize --optimize-level aggressive

# Custom optimization settings
mix muex --optimize --min-complexity 3 --max-per-function 15
```

### Scoping and coverage

```bash
# Mutate only the lines changed on this branch relative to main (PR gate)
mix muex --since main --no-optimize --fail-at 80

# Run each mutant only against the tests that cover its line
mix muex --coverage-guided

# Disable the trivial-compiler-equivalence pass (AST equivalence rules remain)
mix muex --no-tce
```

See [Incremental mode](#incremental-mode---since), [Coverage-guided execution](#coverage-guided-execution), and [Equivalent-mutant handling](#equivalent-mutant-handling) for details.

## Mutators

Muex ships **18** mutators. Select a subset with `--mutators name1,name2` (names are the snake-cased module names, e.g. `enum_semantics`).

### Core (operator / value / structural)

| Mutator | What it does |
|---|---|
| `Arithmetic` | `+`/`-`, `*`/`/` swaps, plus identity removal |
| `ExtendedMath` | `rem`/`div` and bitwise (`band`/`bor`, `bsl`/`bsr`, `&&&`/`\|\|\|`, `<<<`/`>>>`) |
| `Comparison` | `==`, `!=`, `>`, `<`, `>=`, `<=`, `===`, `!==` |
| `NegateConditionals` | relational → logical complement (`<` → `>=`, …) |
| `InvertNegatives` | `-x` → `x` |
| `Boolean` | `and`/`or`, `&&`/`\|\|`, `not`, `true`/`false` |
| `Literal` | numbers (±1), strings, lists, atoms |
| `ReturnValue` | replace a function's return with a type-appropriate zero value |
| `FunctionCall` | remove calls, swap arguments |
| `Conditional` | invert `if`, remove branches, `unless` → `if` |
| `StatementDeletion` | delete a non-final statement from a block |

### Elixir-specific

| Mutator | What it does |
|---|---|
| `Pipe` | drop a stage from a `\|>` chain |
| `Guard` | remove a `when` guard (replace with `true`) |
| `CaseClause` | delete a clause from a `case` |
| `CondClause` | delete a clause from a `cond` |
| `WithClause` | delete a `<-` clause from a `with` |
| `EnumSemantics` | swap `Enum` functions for their opposite (`filter`/`reject`, `all?`/`any?`, `min`/`max`, `take`/`drop`, `map`/`each`) |
| `MapSemantics` | `Map`/`Keyword` `put` ↔ `put_new` |

Custom mutators can be registered at compile time — see [Compile-Time Configuration](#compile-time-configuration).

## Equivalent-mutant handling

An *equivalent mutant* changes the source but not its observable behaviour (e.g. `a + 0` → `a - 0`, or deleting a `@moduledoc`). No test can ever kill it, so counting it as a survivor would deflate your score and send you chasing phantom "weak tests". Muex detects and excludes equivalents — **always on**, independent of optimization — via two layers:

1. **AST-pattern rules** for arithmetic/identity cases (`a + 0`/`a - 0`, `a * 1`/`a / 1`, `x <<< 0`/`x >>> 0`).
2. **Trivial Compiler Equivalence (TCE)** — compiles the original and the mutant and compares their BEAM instructions; if identical, the mutant is provably equivalent. This catches what AST rules can't (e.g. doc/attribute deletions, compiler-canonicalized commutative swaps like `x * 2` ↔ `2 * x`).

Detection is **sound**: a mutant is only called equivalent when it provably is, so a killable mutant is never hidden. Equivalents are reported separately and excluded from the score denominator. Disable the TCE pass with `--no-tce` (the AST rules remain).

## Incremental mode (`--since`)

Scope a run to exactly the lines a branch changed — line-precise, parsed from the git diff:

```bash
# Mutate only lines added/modified on this branch relative to main
mix muex --since main --no-optimize --fail-at 80
```

`--since <ref>` diffs `<ref>...HEAD` (merge-base / PR semantics), restricts the file set to changed files, and filters mutations to those on changed lines. A run with no relevant changes is a **no-op pass** (nothing to score), not a failure — so a PR that doesn't touch `lib/` won't fail the gate.

## Coverage-guided execution

```bash
mix muex --coverage-guided
```

Collects per-test-file line coverage once up front (one `mix test --cover` run per test file), then for each mutant:

- runs **only** the tests that execute the mutated line;
- skips mutants on executable lines that **no** test covers, reporting them as `no_coverage` (excluded from the score) instead of wasting a run;
- short-circuits on the first failing test (a mutant is killed by any failure).

Lines with no coverage data (e.g. a `def`/`defmodule` header) fall back to the default selection and run normally, so a killable mutant is never wrongly skipped. There is an up-front cost (one coverage run per test file), so it is **off by default** — best for larger suites where the per-mutant savings dominate.

## Score precision & CI gates

`--fail-at N` exits non-zero when the mutation score is below `N` (using the pessimistic bound), making muex usable as a quality gate.

Two things keep the score honest:

- **Equivalent and no-coverage mutants are always excluded** from the denominator (they say nothing about test quality), regardless of flags.
- **`--optimize` *samples* mutants** (clustering, per-function caps) to run faster — which makes the reported score an **estimate** that varies with the optimization level. That's fine for a quick local check, but for a hard gate run with `--no-optimize` to get the exact score:

```bash
mix muex --no-optimize --fail-at 80   # exact score, suitable for a CI gate
```

## CLI options reference

| Option | Description |
|---|---|
| `--files` / `--path` | Directory, file, or glob (default: `lib`). Supports `lib/**/*.ex`, `lib/{a,b}/**/*.ex` |
| `--test-paths` | Comma-separated test dirs/files/globs (default: `test`) |
| `--app` | Target a specific app in an umbrella |
| `--since <ref>` | Only mutate lines changed since `<ref>` |
| `--coverage-guided` | Run only covering tests; skip uncovered-line mutants |
| `--mutators` | Comma-separated mutators (default: all) |
| `--language` | Language adapter (default: `elixir`) |
| `--concurrency` | Parallel workers (default: schedulers online) |
| `--timeout` | Per-mutant test timeout, ms (default: 10000) |
| `--fail-at` | Minimum passing score (default: 80) |
| `--format` | `terminal` (default), `json`, `html` |
| `--no-tce` | Disable the TCE equivalence pass |
| `--optimize` / `--no-optimize` | Enable/disable mutation-count sampling (default: enabled) |
| `--optimize-level` | `conservative` \| `balanced` \| `aggressive` |
| `--min-complexity`, `--max-per-function` | Optimizer tuning |
| `--no-filter` | Disable intelligent file filtering |
| `--min-score` | Minimum file complexity to include (default: 20) |
| `--max-mutations` | Cap total mutations (0 = unlimited) |
| `--verbose` | Show file analysis and progress |

## Mutation Optimization

Muex includes heuristics to reduce the number of mutants tested while keeping mutation testing effective. This can reduce testing time by 50-70%. **This sampling is lossy** — it trades some score accuracy for speed — so it is best for fast feedback, not for a precise gate (see [Score precision](#score-precision--ci-gates)). Note that provably-equivalent mutants are dropped *outside* this optimizer and always, so an exact `--no-optimize` run is still equivalence-clean.

### When to Use Optimization

- **CI/CD pipelines**: use conservative mode for fast feedback with <1% score impact
- **Development iteration**: use balanced mode for rapid checks
- **Pre-release validation / gates**: disable optimization (`--no-optimize`) for an exact, complete score

### Optimization Levels

**Conservative** (recommended for fast CI feedback):
- 50-65% reduction in mutations
- <1% impact on mutation score
- Focuses on high-complexity code; preserves boundary-condition mutations

```bash
mix muex --optimize --optimize-level conservative
```

**Balanced** (default, good for development):
- 70-85% reduction in mutations
- 5-10% impact on mutation score
- Focuses on the highest-impact mutations

```bash
mix muex --optimize
```

**Aggressive** (rapid spot checks only):
- 85-95% reduction in mutations
- 10-15% impact on mutation score
- Very fast but may miss edge cases

```bash
mix muex --optimize --optimize-level aggressive
```

### How It Works

The optimizer uses several strategies:

1. **Code Complexity Scoring**: skips mutations in trivial code (getters, simple guards)
2. **Impact Scoring**: prioritizes mutations by risk level
3. **Mutation Clustering**: groups similar mutations and samples representatives
4. **Per-Function Limits**: caps mutations per function to prevent explosion
5. **Boundary Prioritization**: always preserves critical comparison mutations
6. **Pattern-Based Filtering**: removes known low-value mutations

(Equivalent-mutant detection is handled separately and always — see [Equivalent-mutant handling](#equivalent-mutant-handling) — not as part of this optional optimizer.)

For detailed information, see [docs/MUTATION_OPTIMIZATION.md](docs/MUTATION_OPTIMIZATION.md).

### Example: Cart Project

Real-world results from the shopping-cart example (`examples/cart/`, 440 LOC, 84 tests):

| Mode | Mutations | Time | Score | Best For |
|------|-----------|------|-------|----------|
| Baseline (`--no-optimize`) | 886 | ~3 min | 99.77% | Final validation / gates |
| Conservative | 308 | ~1 min | 99.35% | CI/CD |
| Balanced | 28 | ~10 sec | 89.29% | Development |

See [examples/cart/OPTIMIZATION_RESULTS.md](examples/cart/OPTIMIZATION_RESULTS.md) for the complete analysis.

## Compile-Time Configuration

Custom language adapters and mutators can be registered in your `config/config.exs` so they are available via the CLI flags:

```elixir
# config/config.exs
import Config

# Register a custom language adapter (usable with --language lua)
config :muex, languages: %{"lua" => MyApp.Language.Lua}

# Register custom mutators (usable with --mutators string,regex)
config :muex, mutators: %{
  "string" => MyApp.Mutator.String,
  "regex"  => MyApp.Mutator.Regex
}
```

Language adapter modules must implement the `Muex.Language` behaviour and mutator modules must implement the `Muex.Mutator` behaviour. Custom entries are merged with the built-in ones at compile time; entries with the same key override the built-in default.

## Supported Languages

- **Elixir**: full support with ExUnit integration
- **Erlang**: full support with native BEAM integration

Both languages benefit from hot module swapping for efficient mutation testing.

## Example Output

```
Loading files from lib...
Found 24 file(s)
Analyzing files for mutation testing suitability...
Selected 8 file(s) for mutation testing
Skipped 16 file(s) (low complexity or framework code)
Generating mutations...
Testing 342 mutation(s)
Analyzing test dependencies...
Running tests...

Mutation Testing Results
==================================================
Total mutants: 342
Killed: 287 (caught by tests)
Survived: 12 (not caught by tests)
Invalid: 9 (compilation errors)
Timeout: 0
Equivalent: 26 (provably unkillable, skipped)
No coverage: 8 (no test exercises the line, skipped)
==================================================
Mutation Score: 95.99%
```

The score counts only *scorable* mutants — `killed / (killed + survived + timeout)`. Invalid, equivalent, and no-coverage mutants are excluded from the denominator.

With the `--verbose` flag, Muex also shows the file-analysis decisions:

```
Loading files from lib...
Found 24 file(s)
Analyzing files for mutation testing suitability...
  ✗ lib/mix/tasks/muex.ex (Mix task)
  ✗ lib/muex/application.ex (Application/Supervisor)
  ✓ lib/muex/compiler.ex (score: 91)
  ✓ lib/muex/runner.ex (score: 83)
  ✗ lib/muex/language.ex (Behaviour definition)
  ...
```

## Output Formats

### Terminal (Default)

Colored terminal output with progress indicators and a summary:

- Green for killed mutations (tests caught the bug)
- Red for survived mutations (tests missed the bug)
- Yellow for invalid mutations (compilation errors)
- Magenta for timeouts
- Gray for equivalent and no-coverage mutants (skipped)
- Color-coded mutation score (green ≥80%, yellow ≥60%, red <60%)

### JSON Format

Structured JSON for CI/CD integration — per-mutant status, location, and duration, plus a summary with all counts and the score range:

```bash
mix muex --format json
# Outputs: muex-report.json
```

### HTML Format

Interactive HTML report with color-coded results:

```bash
mix muex --format html
# Outputs: muex-report.html
```

## Examples

See the `examples/` directory for example projects:

- **`examples/cart/`** — real-world e-commerce shopping cart (recommended)
  - 440 LOC with complex business logic
  - 84 comprehensive tests
  - 99.77% baseline mutation score
  - Demonstrates optimization heuristics
  - See [examples/cart/README.md](examples/cart/README.md)
- `examples/calculator/` — basic Erlang example

**Note**: the examples demonstrate the mutation testing concept. For production use, add Muex to your project's `mix.exs` as a dependency.

## Documentation

Documentation can be found at <https://hexdocs.pm/muex>.
