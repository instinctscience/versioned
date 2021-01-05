defmodule Versioned.Migration do
  @moduledoc """
  Allows creating tables for versioned schemas.
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
  defmacro create_versioned_table(name, opts \\ [], do: block) do
    name_singular = Keyword.get(opts, :singular, String.trim_trailing("#{name}", "s"))
    {:__block__, mid, lines} = Helpers.normalize_block(block)

    # For versions table, rewrite references to avoid database constraints:
    # If a record is deleted, we don't want version records with its foreign
    # key to be affected.
    versions_block =
      lines
      |> Enum.reduce([], fn
        {:add, m, [foreign_key, {:references, _m2, [_plural, opts]}]}, acc ->
          [{:add, m, [foreign_key, Keyword.get(opts, :type, :uuid)]} | acc]

        line, acc ->
          [line | acc]
      end)
      |> Enum.reverse()
      |> (fn lines -> {:__block__, mid, lines} end).()

    quote do
      create table(unquote(name), primary_key: false) do
        add(:id, :uuid, primary_key: true)
        timestamps(type: :utc_datetime_usec)
        unquote(block)
      end

      create table(:"#{unquote(name)}_versions", primary_key: false) do
        add(:id, :uuid, primary_key: true)
        add(:is_deleted, :boolean, null: false)
        add(:"#{unquote(name_singular)}_id", :uuid, null: false)
        timestamps(type: :utc_datetime_usec, updated_at: false)
        unquote(versions_block)
      end

      create index(:"#{unquote(name)}_versions", :"#{unquote(name_singular)}_id")
    end
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
end
