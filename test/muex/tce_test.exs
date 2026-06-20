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

  describe "equivalent?/2 — safety" do
    test "is false (not provably equivalent) when one side fails to compile" do
      a = quoted("defmodule M do def f, do: 1 end")
      b = quoted("defmodule M do def f, do: undefined_var end")

      refute Tce.equivalent?(a, b)
    end
  end
end
