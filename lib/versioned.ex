defmodule Versioned do
  @moduledoc "Tools for operating on versioned records."
  import Ecto.Query
  alias Ecto.{Changeset, Multi, Schema}

  @doc """
  Inserts a versioned struct defined via Ecto.Schema or a changeset.

  This function calls to the Ecto.Repo module twice -- once to insert the
  record itself, and once to insert a copy as the first version in the
  versions table.
  """
  @spec insert(Schema.t() | Changeset.t(), keyword) :: {:ok, Schema.t()} | {:error, Changeset.t()}
  def insert(struct_or_changeset, opts \\ []) do
    repo = Application.get_env(:versioned, :repo)
    cs = Changeset.change(struct_or_changeset)
    mod = cs.data.__struct__
    version_mod = Module.concat(mod, Version)

    Multi.new()
    |> Multi.insert(:record, cs, opts)
    |> Multi.insert(:version, &build_version(version_mod, &1.record), opts)
    |> repo.transaction()
    |> handle_transaction(return: :record)
  end

  @doc """
  Updates a changeset (of a versioned schema) using its primary key.

  This function uses the Ecto.Repo module, first calling `update/2` to update
  the record itself, and then `insert/1` to add a copy of the new version to
  the versions table.
  """
  @spec update(Changeset.t(), keyword) :: {:ok, Schema.t()} | {:error, Changeset.t()}
  def update(changeset, opts \\ []) do
    repo = Application.get_env(:versioned, :repo)
    version_mod = Module.concat(changeset.data.__struct__, Version)

    Multi.new()
    |> Multi.update(:record, changeset, opts)
    |> Multi.insert(:version, &build_version(version_mod, &1.record), opts)
    |> repo.transaction()
    |> handle_transaction(return: :record)
  end

  @doc """
  Deletes a struct using its primary key and adds a deleted version.
  """
  @spec delete(struct_or_changeset :: Schema.t() | Changeset.t(), opts :: Keyword.t()) ::
          {:ok, Schema.t()} | {:error, Changeset.t()}
  def delete(struct_or_changeset, opts \\ []) do
    repo = Application.get_env(:versioned, :repo)
    cs = Changeset.change(struct_or_changeset)
    version_mod = Module.concat(cs.data.__struct__, Version)

    Multi.new()
    |> Multi.delete(:record, cs, opts)
    |> Multi.insert(:version, &build_version(version_mod, &1.record, deleted: true), opts)
    |> repo.transaction()
    |> handle_transaction(return: :record)
  end

  @doc "List all versions for a schema module, newest first."
  @spec history(module, any, keyword) :: [Schema.t()]
  def history(module, id, opts \\ []) do
    repo = Application.get_env(:versioned, :repo)
    repo.all(history_query(module, id), opts)
  end

  @doc "Get the query to fetch all the versions for a schema, newest first."
  @spec history_query(module, any) :: Ecto.Queryable.t()
  def history_query(module, id) do
    version_mod = Module.concat(module, Version)
    fk = :"#{module.__versioned__(:source_singular)}_id"
    from(version_mod, where: ^[{fk, id}], order_by: [desc: :inserted_at])
  end

  # Create a `version_mod` struct to insert from a new instance of the record.
  # Pass option `deleted: true` to mark as deleted.
  @spec build_version(module, Schema.t(), keyword) :: Changeset.t()
  defp build_version(version_mod, %mod{} = struct, opts \\ []) do
    params =
      :fields
      |> mod.__schema__()
      |> Enum.reject(&(&1 in [:id, :inserted_at, :updated_at]))
      |> Map.new(&{&1, Map.get(struct, &1)})
      |> Map.put(:"#{mod.__versioned__(:source_singular)}_id", struct.id)
      |> Map.put(:is_deleted, Keyword.get(opts, :deleted, false))

    Changeset.change(struct(version_mod), params)
  end

  # Handle the result of a `Repo.transaction` call.
  @spec handle_transaction(tuple, keyword) ::
          {:ok, any} | {:error, Changeset.t(), String.t(), atom()}
  defp handle_transaction(val, opts)

  defp handle_transaction({:ok, map}, opts) do
    case Keyword.fetch(opts, :return) do
      {:ok, key} -> {:ok, Map.get(map, key)}
      :error -> {:ok, map}
    end
  end

  defp handle_transaction({:error, _, %Ecto.Changeset{} = changeset, _}, _),
    do: {:error, changeset}

  defp handle_transaction({:error, bad_op, bad_val, _changes}, _) do
    {:error, "Transaction error in #{bad_op} with #{inspect(bad_val)}"}
  end

  defp handle_transaction({:error, msg}, _) when is_binary(msg),
    do: {:error, "Transaction error: #{msg}"}

  defp handle_transaction({:error, err}, _),
    do: {:error, "Transaction error: #{inspect(err)}"}
end
