defmodule Versioned.Migration do
  @moduledoc """
  Allows creating tables for tracking change histories.
  """

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
    name_singular = Keyword.get(opts, :singular, String.trim_trailing(to_string(name), "s"))

    quote do
      create table(unquote(name), primary_key: false) do
        add(:id, :uuid, primary_key: true)
        add(:is_deleted, :boolean, null: false)
        timestamps(type: :utc_datetime_usec)
        unquote(block)
      end

      create table(:"#{unquote(name_singular)}_versions", primary_key: false) do
        add(:id, :uuid, primary_key: true)
        add(:is_deleted, :boolean, null: false)
        add(:"#{unquote(name_singular)}_id", :uuid, null: false)
        timestamps(type: :utc_datetime_usec, updated_at: false)
        unquote(block)
      end
    end
  end

  @doc "Add a new column to both the main table and the versions table."
  defmacro add_versioned_column(table_name, name, type, opts \\ []) do
    singular = Keyword.get(opts, :singular, String.trim_trailing(to_string(table_name), "s"))

    quote bind_quoted: [table_name: table_name, name: name, type: type, singular: singular] do
      alter table(table_name) do
        add(name, type)
      end

      alter table(:"#{singular}_versions") do
        add(name, type)
      end
    end
  end
end
