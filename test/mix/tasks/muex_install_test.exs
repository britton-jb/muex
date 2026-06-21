defmodule Mix.Tasks.Muex.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "mix muex.install" do
    test "adds muex's generated artifacts to .gitignore" do
      test_project()
      |> Igniter.compose_task("muex.install", [])
      |> assert_has_patch(".gitignore", """
      + |# muex (mutation testing) artifacts
      + |/cover/
      + |/muex-report.json
      + |/muex-report.html
      """)
    end

    test "is idempotent when the artifacts are already ignored" do
      existing = """
      /_build/

      # muex (mutation testing) artifacts
      /cover/
      /muex-report.json
      /muex-report.html
      """

      test_project(files: %{".gitignore" => existing})
      |> Igniter.compose_task("muex.install", [])
      |> assert_unchanged()
    end
  end
end
