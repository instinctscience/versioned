defmodule Versioned.Absinthe do
  @moduledoc """
  Helpers for Absinthe schemas.
  """

  @doc """
  Create a version wrapper object type, `name`, wrapping a certain object
  type, `wrapped_name`.

  The caller should `use Absinthe.Schema.Notation` as here we return code
  which invokes its `object` macro.

  The generated object will have the following fields:

  * `:id` - primary key of the version record
  * `:is_deleted` - boolean indicating if the record was deleted as of this version
  * `:inserted_at` - UTC timestamp, indicating when the version was created
  * field specified by `wrapped_name` - The object as it was in this version
  """
  defmacro version_object(name, wrapped_name, opts \\ []) do
    quote do
      object unquote(name), unquote(opts) do
        field(:id, :id)
        field(:is_deleted, :boolean)
        field(:inserted_at, :datetime)
        field(unquote(wrapped_name), unquote(wrapped_name))
      end
    end
  end

  @doc """
  Convert a version record as defined by `Versioned.Schema` into a version as
  defined by `version_object/3` which encapsulates the original record.

  ## Example

      iex> record = %{id: 2, user_id: 3, inserted_at: 9, is_deleted: false, name: "Bob"}
      iex> wrap(record, :user)
      %{id: 2, inserted_at: 9, is_deleted: false, user: %{id: 3, name: "Bob"}}
  """
  @spec wrap(map, atom) :: map
  def wrap(record, name) do
    record_id_field = :"#{name}_id"
    ver_fields = [:id, :inserted_at, :is_deleted]
    drop_from_record = [record_id_field | ver_fields]
    version = Map.take(record, ver_fields)
    id = Map.get(record, record_id_field)
    record = record |> Map.drop(drop_from_record) |> Map.put(:id, id)

    Map.put(version, name, record)
  end
end
