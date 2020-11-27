defmodule Versioned.Helpers do
  @moduledoc "Tools shared between modules, for internal use."

  @doc """
  Wrap a line of AST in a block if it isn't already wrapped.

  If block has only one line, then it's not wrapped the same way.
  Normalize input by wrapping in this case.
  """
  @spec normalize_block(Macro.t()) :: Macro.t()
  def normalize_block({x, m, _} = line) when x != :__block__,
    do: {:__block__, m, [line]}

  def normalize_block(block), do: block
end
