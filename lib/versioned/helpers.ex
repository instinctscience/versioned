defmodule Versioned.Helpers do
  @moduledoc "Tools shared between modules, for internal use."

  @doc """
  Wrap a line of AST in a block if it isn't already wrapped.
  """
  @spec normalize_block(Macro.t()) :: Macro.t()
  def normalize_block({x, m, _} = line) when x != :__block__,
    do: {:__block__, m, [line]}

  def normalize_block(block), do: block
end
