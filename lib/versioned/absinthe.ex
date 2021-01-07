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
end
