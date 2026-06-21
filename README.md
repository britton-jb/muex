# Muex

Mutation testing library for Elixir, Erlang, and other BEAM languages.

Muex evaluates **test-suite quality** by introducing deliberate bugs (mutations) into your code and checking whether your tests catch them. A *killed* mutant means a test failed (good — your tests noticed the change); a *survived* mutant means no test noticed a real behavioural change (a gap in your tests).

It has a language-agnostic architecture with pluggable language adapters, and ships features aimed at making mutation testing practical on real projects and in CI: a broad mutator catalog, sound equivalent-mutant handling, line-precise `--since` scoping for pull requests, and coverage-guided execution.

## Features

- **18 mutators** — a PITest-style core plus Elixir-specific operators (pipes, guards, `case`/`cond`/`with` clauses, `Enum`/`Map` semantics). See [Mutators](#mutators).
- **Sound equivalent-mutant handling** — equivalent mutants (which no test can ever kill) are detected and excluded from the score, via AST rules **and** Trivial Compiler Equivalence (TCE — compares compiled BEAM). Always on; never inflates or deflates the score. See [Equivalent mutants](#equivalent-mutant-handling).
- **Incremental `--since <ref>`** — mutate only the lines changed on a branch (line-precise, via the git diff). Ideal for per-PR CI gates. See [Incremental mode](#incremental-mode---since).
- **Coverage-guided execution** — run each mutant only against the tests that cover its line, skip mutants on uncovered lines, and short-circuit on the first failure. See [Coverage-guided execution](#coverage-guided-execution).
- **Honest CI gates** — `--fail-at` with an exact (un-sampled) score via `--no-optimize`. See [Score precision & CI gates](#score-precision--ci-gates).
- Parallel execution with per-file sandboxing and configurable concurrency.
- Intelligent file filtering, optional mutation-count optimization, and JSON / HTML / terminal reports.
- Elixir + Erlang support; pluggable adapters for other languages.

## Installation

### With Igniter (recommended)

```bash
mix igniter.install muex
```

This adds the dependency and runs the installer (`mix muex.install`), which adds muex's generated artifacts (`cover/`, `muex-report.{json,html}`) to your `.gitignore`. If muex is already a dependency, just run `mix muex.install`.

### As a Mix dependency

Add `muex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:muex, "~> 0.6", only: [:dev, :test], runtime: false}
  ]
end
```

Then:

```bash
mix deps.get
mix muex
```

### As a hex archive (global use)

```bash
mix archive.install hex muex
```

Makes `mix muex` available in any project without adding it as a dependency.

### As an escript (standalone binary)

```bash
mix escript.build
sudo cp muex /usr/local/bin/
cd /path/to/your/project && muex
```

## Quick start

```bash
# Whole project (intelligent file filtering on by default)
mix muex

# A single module against its test, with an exact score
mix muex --files lib/my_module.ex --test-paths test/my_module_test.exs --no-optimize

# A pull-request gate: mutate only what changed on this branch, exact score, fail under 80%
mix muex --since main --no-optimize --fail-at 80
```

The escript (`muex`) and the mix task (`mix muex`) accept identical options.

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

Custom mutators can be registered at compile time — see [Custom adapters & mutators](#custom-adapters--mutators).

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

## CLI options

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

## Example output

```
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

The score counts only *scorable* mutants — `killed / (killed + survived + timeout)`. Invalid, equivalent, and no-coverage mutants are excluded.

### Output formats

- **Terminal** (default): colour-coded progress and summary (green killed · red survived · yellow invalid · magenta timeout · gray equivalent/no-coverage).
- **JSON**: `mix muex --format json` → `muex-report.json` (per-mutant status, location, duration; summary with all counts and the score range).
- **HTML**: `mix muex --format html` → `muex-report.html`.

## Mutation optimization

Muex can reduce the number of mutants tested to run faster. **This sampling is lossy** — it trades some score accuracy for speed — so it is best for fast local feedback, not for a gate (see [Score precision](#score-precision--ci-gates)).

| Level | Reduction | Score impact | Best for |
|---|---|---|---|
| `conservative` | 50–65% | <1% | CI/CD fast feedback |
| `balanced` (default) | 70–85% | 5–10% | Development iteration |
| `aggressive` | 85–95% | 10–15% | Rapid spot checks |

```bash
mix muex --optimize --optimize-level conservative
mix muex --optimize --min-complexity 3 --max-per-function 15
```

For details see [docs/MUTATION_OPTIMIZATION.md](docs/MUTATION_OPTIMIZATION.md). (Note: provably-equivalent mutants are dropped *outside* this optimizer and always, so an exact `--no-optimize` run is still equivalence-clean.)

## Custom adapters & mutators

Register custom language adapters and mutators in `config/config.exs` so they're available via CLI flags:

```elixir
import Config

# Usable with --language lua
config :muex, languages: %{"lua" => MyApp.Language.Lua}

# Usable with --mutators string,regex
config :muex, mutators: %{
  "string" => MyApp.Mutator.String,
  "regex"  => MyApp.Mutator.Regex
}
```

Language adapters implement the `Muex.Language` behaviour; mutators implement `Muex.Mutator`. Custom entries merge with (and can override) the built-ins.

## Supported languages

- **Elixir** — full support with ExUnit integration.
- **Erlang** — full support on the BEAM.

## Examples

See the `examples/` directory:

- **`examples/cart/`** — e-commerce cart (440 LOC, 84 tests), demonstrates optimization. See [examples/cart/README.md](examples/cart/README.md).
- `examples/shop/` — simpler cart example.
- `examples/calculator.erl` — basic Erlang example.

## Documentation

API docs: <https://hexdocs.pm/muex>.
