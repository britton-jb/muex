defmodule Muex.Tce do
  @moduledoc """
  Trivial Compiler Equivalence (TCE) for mutants.

  Two pieces of source are *compiler-equivalent* when they compile to the same
  BEAM code. Such a mutant can never be killed — no test can distinguish it from
  the original — so it is an equivalent mutant and should be dropped.

  This catches cases the AST-pattern rules in `Muex.Equivalence` cannot, e.g.
  deleting a `@moduledoc`/`@doc` or any change that the compiler erases, where
  the resulting function bytecode is byte-for-byte identical.

  The comparison is **sound**: each module is compiled and disassembled, line
  annotations and the (throwaway) module name are stripped, and the remaining
  instruction streams are compared. Equivalence is reported only on an exact
  match; anything that fails to compile is treated as *not* provably equivalent
  so a real mutant is never hidden.
  """

  @doc """
  Returns true when the two quoted modules compile to identical BEAM code.

  Returns false if they differ or if either fails to compile.
  """
  @spec equivalent?(Macro.t(), Macro.t()) :: boolean()
  def equivalent?(module_ast_a, module_ast_b) do
    case {fingerprint(module_ast_a), fingerprint(module_ast_b)} do
      {{:ok, a}, {:ok, b}} -> a == b
      _ -> false
    end
  end

  # Compile under a unique throwaway module name, disassemble, and strip line
  # annotations so only the behavioural instruction stream remains.
  @probe_placeholder :__muex_tce_probe__

  defp fingerprint(module_ast) do
    with {:ok, binary, module} <- compile_binary(module_ast) do
      {:beam_file, _module, _exports, _attrs, _compile_info, code} = :beam_disasm.file(binary)
      # Strip line annotations and rewrite the throwaway module name to a
      # constant, so two modules differing only in name/lines fingerprint alike.
      {:ok, code |> strip_lines() |> normalize_module(module)}
    end
  end

  defp compile_binary(module_ast) do
    renamed = rename_module(module_ast, probe_alias())

    # with_diagnostics captures compiler warnings/errors instead of printing
    # them, keeping mutant compile failures off the console.
    {result, _diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          case Code.compile_quoted(renamed) do
            [{module, binary} | _] ->
              purge(module)
              {:ok, binary, module}

            _ ->
              :error
          end
        rescue
          _ -> :error
        catch
          _, _ -> :error
        end
      end)

    result
  end

  defp probe_alias do
    segment = String.to_atom("MuexTceProbe#{System.unique_integer([:positive])}")
    {:__aliases__, [], [segment]}
  end

  defp rename_module({:defmodule, meta, [_alias, body]}, probe_alias) do
    {:defmodule, meta, [probe_alias, body]}
  end

  defp rename_module(other, _probe_alias), do: other

  defp purge(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp strip_lines(list) when is_list(list) do
    list
    |> Enum.reject(&match?({:line, _}, &1))
    |> Enum.map(&strip_lines/1)
  end

  defp strip_lines(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> strip_lines() |> List.to_tuple()
  end

  defp strip_lines(other), do: other

  defp normalize_module(term, module) when is_list(term) do
    Enum.map(term, &normalize_module(&1, module))
  end

  defp normalize_module(module, module), do: @probe_placeholder

  defp normalize_module(tuple, module) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> normalize_module(module) |> List.to_tuple()
  end

  defp normalize_module(other, _module), do: other
end
