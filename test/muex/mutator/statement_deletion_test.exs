defmodule Muex.Mutator.StatementDeletionTest do
  use ExUnit.Case, async: true

  alias Muex.Mutator.StatementDeletion

  @context %{file: "test.ex"}

  describe "mutate/2 - __block__ with multiple statements" do
    test "two statements: produces one mutation deleting the first" do
      ast =
        {:__block__, [line: 1],
         [
           {:=, [line: 1], [{:x, [], Elixir}, 1]},
           {:+, [line: 2], [{:x, [], Elixir}, 2]}
         ]}

      mutations = StatementDeletion.mutate(ast, @context)

      assert [mutation] = mutations
      # Deleting the first statement collapses the block to the last expr
      assert mutation.ast == {:+, [line: 2], [{:x, [], Elixir}, 2]}
      assert mutation.description =~ "delete statement 1 of 2"
    end

    test "three statements: produces two mutations (first and second)" do
      stmt1 = {:=, [line: 1], [{:x, [], Elixir}, 1]}
      stmt2 = {:=, [line: 2], [{:y, [], Elixir}, 2]}
      stmt3 = {:+, [line: 3], [{:x, [], Elixir}, {:y, [], Elixir}]}

      ast = {:__block__, [line: 1], [stmt1, stmt2, stmt3]}

      mutations = StatementDeletion.mutate(ast, @context)

      assert length(mutations) == 2

      # First mutation: delete stmt1, keep stmt2 + stmt3
      assert Enum.any?(mutations, fn m ->
               m.ast == {:__block__, [line: 1], [stmt2, stmt3]} and
                 m.description =~ "delete statement 1 of 3"
             end)

      # Second mutation: delete stmt2, keep stmt1 + stmt3
      assert Enum.any?(mutations, fn m ->
               m.ast == {:__block__, [line: 1], [stmt1, stmt3]} and
                 m.description =~ "delete statement 2 of 3"
             end)
    end

    test "four statements: produces three mutations" do
      stmts = for i <- 1..4, do: {:stmt, [line: i], [i]}
      ast = {:__block__, [line: 1], stmts}

      mutations = StatementDeletion.mutate(ast, @context)

      assert length(mutations) == 3
    end

    test "never deletes the last statement" do
      stmt1 = {:call, [line: 1], [:a]}
      stmt2 = {:call, [line: 2], [:b]}
      stmt3 = {:result, [line: 3], []}

      ast = {:__block__, [line: 1], [stmt1, stmt2, stmt3]}

      mutations = StatementDeletion.mutate(ast, @context)

      # Every mutation should still contain stmt3
      assert Enum.all?(mutations, fn m ->
               case m.ast do
                 {:__block__, _, stmts} -> List.last(stmts) == stmt3
                 single -> single == stmt3
               end
             end)
    end

    test "block collapse: removing from 2-statement block produces bare expression" do
      stmt1 = {:setup, [line: 1], []}
      stmt2 = {:result, [line: 2], []}

      ast = {:__block__, [line: 1], [stmt1, stmt2]}

      [mutation] = StatementDeletion.mutate(ast, @context)

      # Should collapse to bare expression, not {:__block__, _, [stmt2]}
      assert mutation.ast == stmt2
    end
  end

  describe "mutate/2 - metadata" do
    test "includes proper metadata" do
      ast =
        {:__block__, [line: 5],
         [
           {:=, [line: 5], [{:x, [], Elixir}, 1]},
           {:x, [line: 6], Elixir}
         ]}

      context = %{file: "lib/my_module.ex"}
      [mutation] = StatementDeletion.mutate(ast, context)

      assert mutation.mutator == Muex.Mutator.StatementDeletion
      assert mutation.description =~ "StatementDeletion:"
      assert mutation.location.file == "lib/my_module.ex"
      assert mutation.location.line == 5
    end
  end

  describe "mutate/2 - module attributes are skipped" do
    test "does not delete @doc / @spec / @type / @moduledoc / constant attrs" do
      # A `defmodule` body is a __block__; without the guard each of these
      # @-attributes would become a deletion mutation. They must be skipped.
      attr = fn name, arg -> {:@, [line: 1], [{name, [line: 1], [arg]}]} end

      moduledoc = attr.(:moduledoc, "hi")
      doc = attr.(:doc, "a function")
      spec = attr.(:spec, {:foo, [line: 2], []})
      type = attr.(:type, {:t, [line: 3], []})
      const = attr.(:timeout, 5_000)
      real_stmt = {:=, [line: 6], [{:x, [], Elixir}, 1]}
      ret = {:x, [line: 7], Elixir}

      ast = {:__block__, [line: 1], [moduledoc, doc, spec, type, const, real_stmt, ret]}

      mutations = StatementDeletion.mutate(ast, @context)

      # Only the one executable, non-final statement (real_stmt) is mutated.
      assert [mutation] = mutations
      assert mutation.description =~ "delete statement 6 of 7"
      refute Enum.any?(mutations, fn m -> m.description =~ "statement 1 of" end)
    end

    test "a block of only attributes plus a return value yields no mutations" do
      ast =
        {:__block__, [line: 1],
         [
           {:@, [line: 1], [{:moduledoc, [line: 1], ["x"]}]},
           {:@, [line: 2], [{:spec, [line: 2], [{:f, [line: 2], []}]}]},
           {:def, [line: 3], [{:f, [line: 3], []}]}
         ]}

      assert [] = StatementDeletion.mutate(ast, @context)
    end
  end

  describe "mutate/2 - non-matching nodes" do
    test "single-statement block returns empty" do
      ast = {:__block__, [line: 1], [{:x, [], Elixir}]}

      assert [] = StatementDeletion.mutate(ast, @context)
    end

    test "non-block nodes return empty" do
      assert [] = StatementDeletion.mutate({:+, [line: 1], [1, 2]}, @context)
      assert [] = StatementDeletion.mutate(:foo, @context)
      assert [] = StatementDeletion.mutate(42, @context)
      assert [] = StatementDeletion.mutate("hello", @context)
    end
  end

  describe "equivalent?/1 - clause absorbed by a following catch-all" do
    # Builds the block, runs mutate/2, and returns the mutation that deletes
    # `target` (a clause AST) with original_ast attached (as the real pipeline
    # does in Muex.Mutator.walk/3).
    defp deletion_of(statements, target) do
      block = {:__block__, [line: 1], statements}

      block
      |> StatementDeletion.mutate(@context)
      |> Enum.map(&Map.put(&1, :original_ast, block))
      |> Enum.find(fn m -> m.ast == drop(statements, target) end)
    end

    defp drop(statements, target) do
      case List.delete(statements, target) do
        [single] -> single
        many -> {:__block__, [line: 1], many}
      end
    end

    test "true: deleting a specific clause an identical-bodied catch-all absorbs" do
      specific = quote do: def(handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state})
      catch_all = quote do: def(handle_info(_msg, state), do: {:noreply, state})
      trailing = quote do: :ok

      mutation = deletion_of([specific, catch_all, trailing], specific)
      assert StatementDeletion.equivalent?(mutation)
    end

    test "false: the catch-all returns a different body" do
      specific = quote do: def(handle_info({:EXIT, _p, _r}, state), do: {:noreply, state})
      catch_all = quote do: def(handle_info(_msg, state), do: {:stop, :normal, state})
      trailing = quote do: :ok

      mutation = deletion_of([specific, catch_all, trailing], specific)
      refute StatementDeletion.equivalent?(mutation)
    end

    test "false: the following clause carries a guard (not a true catch-all)" do
      specific = quote do: def(handle({:a, _x}, state), do: {:ok, state})
      guarded = quote do: def(handle(msg, state) when is_atom(msg), do: {:ok, state})
      trailing = quote do: :ok

      mutation = deletion_of([specific, guarded, trailing], specific)
      refute StatementDeletion.equivalent?(mutation)
    end

    test "false: the body reads an argument bound at a different position" do
      specific = quote do: def(f(_x, state), do: {:noreply, state})
      catch_all = quote do: def(f(state, _x), do: {:noreply, state})
      trailing = quote do: :ok

      mutation = deletion_of([specific, catch_all, trailing], specific)
      refute StatementDeletion.equivalent?(mutation)
    end

    test "false: no following clause of the same function to absorb it" do
      specific = quote do: def(handle_info({:EXIT, _p, _r}, state), do: {:noreply, state})
      other = quote do: def(unrelated(x), do: x)
      trailing = quote do: :ok

      mutation = deletion_of([specific, other, trailing], specific)
      refute StatementDeletion.equivalent?(mutation)
    end

    test "false: deleting an ordinary in-function statement (not a clause)" do
      ast =
        {:__block__, [line: 1],
         [
           {:=, [line: 1], [{:x, [], Elixir}, 1]},
           {:=, [line: 2], [{:y, [], Elixir}, 2]},
           {:+, [line: 3], [{:x, [], Elixir}, {:y, [], Elixir}]}
         ]}

      mutations =
        Enum.map(StatementDeletion.mutate(ast, @context), &Map.put(&1, :original_ast, ast))

      refute Enum.any?(mutations, &StatementDeletion.equivalent?/1)
    end
  end

  describe "name/0" do
    test "returns mutator name" do
      assert "StatementDeletion" = StatementDeletion.name()
    end
  end

  describe "description/0" do
    test "returns mutator description" do
      desc = StatementDeletion.description()
      assert is_binary(desc)
      assert desc =~ "statement"
    end
  end
end
