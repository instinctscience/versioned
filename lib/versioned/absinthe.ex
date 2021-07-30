defmodule Versioned.Absinthe do
  @moduledoc """
  Helpers for Absinthe schemas.
  """
  alias Versioned.Helpers

  @doc """
  Declare an object, versioned compliment, and interface, based off name `name`.

  The caller should `use Absinthe.Schema.Notation` as here we return code
  which invokes its `object` macro.

  Both objects belong to an interface which encompasses the common fields.
  All common fields (except `:id` and `:inserted_at`) are included under an
  interface, named by the entity name and suffixed `_base`.

  The generated object will have the following fields:

  * `:id` - ID of the record.
  * `:version_id` - ID of the most recent record's version.
  * `:inserted_at` - Timestamp when the record was created.
  * `:updated_at` - Timestamp when the record was last updated.
  * Additionally, all fields declared in the block.

  The generated version object will have the following fields:

  * `:id` - ID of the version record.
  * `:foo_id` - If the entity was `:foo`, then this would be the id of the main
    record for which this version is based.
  * `:is_deleted` - Boolean indicating if the record was deleted as of this version.
  * `:inserted_at` - Timestamp when the version record was created.
  * Additionally, all fields declared in the block.
  """
  defmacro versioned_object(name, do: block) do
    {:__block__, _m, lines_ast} = Helpers.normalize_block(block)

    quote do
      object unquote(name) do
        field :id, non_null(:id)
        field :version_id, :id
        field :inserted_at, non_null(:datetime)
        field :updated_at, non_null(:datetime)
        unquote(drop_version_fields(block))
        interface(unquote(:"#{name}_base"))
      end

      object unquote(:"#{name}_version") do
        field :id, non_null(:id)
        field unquote(:"#{name}_id"), :id
        field :is_deleted, :boolean
        field :inserted_at, :datetime
        version_lines(unquote(lines_ast))
        interface(unquote(:"#{name}_base"))
      end

      interface unquote(:"#{name}_base") do
        unquote(block)

        resolve_type(fn
          %{version_id: _}, _ -> unquote(name)
          %{unquote(:"#{name}_id") => _}, _ -> unquote(:"#{name}_version")
          _, _ -> nil
        end)
      end
    end
  end

  # Drop `version_field` lines for the base (non-version) object.
  @spec drop_version_fields(Macro.t()) :: Macro.t()
  defp drop_version_fields({:__block__, top_m, lines}) do
    lines = Enum.reject(lines, &match?({:version_field, _, _}, &1))
    {:__block__, top_m, lines}
    |> IO.inspect(label: "dropped")
  end

  # defmacro version_field(g, x, y) do
  #   IO.inspect({g, x, y}, label: "uggg")
  # end

  @doc """
  Convert a list of ast lines into ast lines to be used for the version object.
  """
  defmacro version_lines(lines_ast) do
    lines_ast
    |> Enum.reduce([], fn
      {:version_field, m, a}, acc -> [{:field, m, a} | acc]
      other, acc -> [other | acc]
    end)
    |> Enum.reverse()
    |> IO.inspect(label: "BOOM")
  end
end
