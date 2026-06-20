defmodule MuexTest do
  use ExUnit.Case
  doctest Muex

  test "module loads successfully" do
    assert Code.ensure_loaded?(Muex)
  end

  describe "build_result/1 score" do
    test "excludes :equivalent (and :invalid) mutants from the denominator" do
      results = [
        %{result: :killed},
        %{result: :equivalent},
        %{result: :invalid}
      ]

      # Only the 1 killed mutant is scorable: 1/1 = 100%, not 1/3.
      assert {:ok, %{score_low: 100.0, score_high: 100.0}} = Muex.build_result(results)
    end

    test "is 0.0 when there are no scorable mutants" do
      assert {:ok, %{score_low: 0.0, score_high: 0.0}} =
               Muex.build_result([%{result: :equivalent}, %{result: :invalid}])
    end
  end

  describe "scope_to_changed_files/2" do
    test "passes all files through when changed is nil (no --since)" do
      files = [%{path: "lib/a.ex"}, %{path: "lib/b.ex"}]
      assert Muex.scope_to_changed_files(files, nil) == files
    end

    test "keeps only files present in the changed map" do
      files = [%{path: "lib/a.ex"}, %{path: "lib/b.ex"}]
      changed = %{"lib/a.ex" => MapSet.new([1])}

      assert Muex.scope_to_changed_files(files, changed) == [%{path: "lib/a.ex"}]
    end
  end
end
