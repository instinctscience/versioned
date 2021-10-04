defmodule Versioned.Migration do
  @moduledoc """
  Allows creating tables for versioned schemas.

  ## Example

      defmodule MyApp.Repo.Migrations.CreateCar do
        use Versioned.Migration

        def change do
          create_versioned_table(:cars) do
            add :name, :string
          end
        end
      end

  """
  alias Versioned.Helpers

  defmacro __using__(_) do
    quote do
      use Ecto.Migration
      import unquote(__MODULE__)
    end
  end

  @doc """
  Create a table whose data is versioned by also creating a secondary table
  with the immutable, append-only history.
  """
  defmacro create_versioned_table(name_plural, opts \\ [], do: block) do
    name_singular = Keyword.get(opts, :singular, String.trim_trailing("#{name_plural}", "s"))
    {:__block__, mid, lines} = Helpers.normalize_block(block)

    # For versions table, rewrite references to avoid database constraints:
    # If a record is deleted, we don't want version records with its foreign
    # key to be affected.
    versions_block =
      lines
      |> Enum.reduce([], &do_version_line/2)
      |> Enum.reverse()
      |> (fn lines -> {:__block__, mid, lines} end).()

    quote do
      create table(unquote(name_plural), primary_key: false) do
        add(:id, :uuid, primary_key: true)
        timestamps(type: :utc_datetime_usec)
        unquote(block)
      end

      create table(:"#{unquote(name_plural)}_versions", primary_key: false) do
        add(:id, :uuid, primary_key: true)
        add(:is_deleted, :boolean, null: false)
        add(:"#{unquote(name_singular)}_id", :uuid, null: false)
        timestamps(type: :utc_datetime_usec, updated_at: false)
        unquote(versions_block)
      end

      create(index(:"#{unquote(name_plural)}_versions", :"#{unquote(name_singular)}_id"))
    end
  end

  # Take the original migration ast and attach to the accumulator the
  # corresponding ast to use for the version table.
  @spec do_version_line(Macro.t(), Macro.t()) :: Macro.t()
  defp do_version_line({:add, a, [b, {:references, _, _} = tup]}, acc) do
    do_version_line({:add, a, [b, tup, []]}, acc)
  end

  defp do_version_line(
         {:add, m, [foreign_key, {:references, _m2, [_plural, ref_opts]}, field_opts]},
         acc
       ) do
    # Drop reference in favor if plain ole field of the same type.
    # This way, referenced records can be deleted while the referencing version
    # records remain intact.
    type = Keyword.get(ref_opts, :type, :uuid)
    line = {:add, m, [foreign_key, type, field_opts]}

    [line | acc]
  end

  defp do_version_line(line, acc) do
    [line | acc]
  end

  @doc "Add a new column to both the main table and the versions table."
  defmacro add_versioned_column(table_name, name, type, opts \\ []) do
    {singular, opts} = Keyword.pop(opts, :singular, to_string(table_name))

    quote bind_quoted: [
            table_name: table_name,
            name: name,
            opts: opts,
            type: type,
            singular: singular
          ] do
      alter table(table_name) do
        add(name, type, opts)
      end

      alter table(:"#{singular}_versions") do
        add(name, type, opts)
      end
    end
  end

  @doc """
  Rename `orig_field` column in table `table_name` to a new name.

  See `Ecto.Migration.rename/3`.

  Note that this is indeed changing the field names as well in the
  complimenting and generally immutable "versions" table.

  ## Example

      defmodule MyApp.Repo.Migrations.RenameFooToBar do
        use Versioned.Migration

        def change do
          rename_versioned_column("my_table", :foo, to: :bar)
        end
      end
  """
  defmacro rename_versioned_column(table_name, orig_field, opts) do
    quote do
      rename(table(unquote(table_name)), unquote(orig_field), unquote(opts))
      rename(table(unquote("#{table_name}_versions")), unquote(orig_field), unquote(opts))
    end
  end

  @doc """
  Modify `orig_field` column in table `table_name` and its versioned
  counterpart.

  See `Ecto.Migration.modify/3`.

  ## Example

      defmodule MyApp.Repo.Migrations.RenameFooToBar do
        use Versioned.Migration

        def change do
          modify_versioned_column("my_table", :foo, :text, null: true)
        end
      end
  """
  defmacro modify_versioned_column(table_name, column, type, opts \\ []) do
    quote do
      alter table(unquote(table_name)) do
        modify(unquote(column), unquote(type), unquote(opts))
      end

      alter table(unquote("#{table_name}_versions")) do
        modify(unquote(column), unquote(type), unquote(opts))
      end
    end
  end

  @doc """
  Removes a column from a table and its versioned counterpart.

  See `Ecto.Migration.remove/1`.

  ## Example

      defmodule MyApp.Repo.Migrations.RemoveFooToBar do
        use Versioned.Migration

        def change do
          remove_versioned_column("my_table", :foo)
        end
      end
  """
  defmacro remove_versioned_column(table_name, column) do
    quote do
      alter table(unquote(table_name)) do
        remove(unquote(column))
      end
    end
  end
end
