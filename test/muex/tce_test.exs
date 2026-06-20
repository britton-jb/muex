defmodule Muex.TceTest do
  use ExUnit.Case, async: false

  alias Muex.Tce

  defp quoted(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    ast
  end

  describe "equivalent?/2 — provable compiler equivalence" do
    test "deleting a @moduledoc is equivalent (identical function bytecode)" do
      a = quoted(~S|defmodule M do
        @moduledoc "docs"
        def f(x), do: x + 1
      end|)

      b = quoted(~S|defmodule M do
        def f(x), do: x + 1
      end|)

      assert Tce.equivalent?(a, b)
    end

    test "a line-only difference is equivalent" do
      a = quoted("defmodule M do\n  def f, do: 1\nend")
      b = quoted("defmodule M do\n\n\n  def f, do: 1\nend")

      assert Tce.equivalent?(a, b)
    end

    test "deleting a @doc on a function with an unchanged body is equivalent" do
      a = quoted(~S|defmodule M do
        @doc "hi"
        def f(x), do: x * 2
      end|)

      b = quoted(~S|defmodule M do
        def f(x), do: x * 2
      end|)

      assert Tce.equivalent?(a, b)
    end
  end

  describe "equivalent?/2 — genuinely different code is kept" do
    test "a different return value is not equivalent" do
      a = quoted("defmodule M do def f, do: 1 end")
      b = quoted("defmodule M do def f, do: 2 end")

      refute Tce.equivalent?(a, b)
    end

    test "a different operator is not equivalent" do
      a = quoted("defmodule M do def f(x), do: x + 1 end")
      b = quoted("defmodule M do def f(x), do: x - 1 end")

      refute Tce.equivalent?(a, b)
    end
  end

  describe "equivalent_source?/2 — mutated source vs original AST" do
    test "true when the mutated source compiles to identical bytecode" do
      original = quoted(~S|defmodule M do
        @moduledoc "docs"
        def f(x), do: x + 1
      end|)

      mutated_source = ~S|defmodule M do
        def f(x), do: x + 1
      end|

      assert Tce.equivalent_source?(original, mutated_source)
    end

    test "false when the mutated source changes behaviour" do
      original = quoted("defmodule M do def f, do: 1 end")
      assert not Tce.equivalent_source?(original, "defmodule M do def f, do: 2 end")
    end

    test "false when the mutated source does not parse" do
      original = quoted("defmodule M do def f, do: 1 end")
      assert not Tce.equivalent_source?(original, "defmodule M do def f, do: end")
    end
  end

  describe "equivalent?/2 — safety" do
    test "is false (not provably equivalent) when one side fails to compile" do
      a = quoted("defmodule M do def f, do: 1 end")
      b = quoted("defmodule M do def f, do: undefined_var end")

      refute Tce.equivalent?(a, b)
    end

    test "refuses anything that is not a single defmodule (never compiles real modules)" do
      # A bare expression cannot be renamed to a throwaway module, so TCE bails
      # rather than risk compiling/clobbering the project's real modules.
      refute Tce.equivalent?(quoted("1 + 1"), quoted("1 + 1"))
    end
  end
end
