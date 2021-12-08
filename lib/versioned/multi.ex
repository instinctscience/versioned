defmodule Versioned.Multi do
  @moduledoc "Tools for operating on versioned records."
  # import Ecto.Query, except: [preload: 2]
  import Versioned.Helpers
  alias Ecto.Multi
  alias Ecto.{Changeset, Multi, Schema}

  @doc """
  Returns an Ecto.Multi with all steps necessary to insert a versioned record.

  If `name` is `"puppy"`, the returned parts will be:

    * `"puppy_record"` - The inserted record itself.
    * `"puppy_version"` - The inserted version record.
  """
  @spec insert(Ecto.Multi.t(), atom | String.t(), Schema.t() | Changeset.t(), keyword) ::
          Ecto.Multi.t()
  def insert(multi, name, struct_or_changeset, opts \\ []) do
    cs = Changeset.change(struct_or_changeset)
    opts = Keyword.merge(opts, change: true, inserted_at: DateTime.utc_now())
    record_field = "#{name}_record"

    multi
    |> Multi.insert(record_field, cs, opts)
    |> Multi.run("#{name}_version", fn repo, %{^record_field => record} ->
      case build_version(record, opts) do
        nil -> {:ok, nil}
        changeset -> repo.insert(changeset)
      end
    end)
  end

  @doc """
  Returns an Ecto.Multi with all steps necessary to update a versioned record.

  An Ecto.Multi is returned which first updates the record itself, inserts a new
  version into the versions table and finally deletes associations as needed.

  If `name` is `"puppy"`, the returned parts will be:

    * `"puppy_record"` - The updated record itself.
    * `"puppy_version"` - The newly inserted version record.
    * `"puppy_deletes"` - List of association version records which were
      deleted.
  """
  @spec update(Ecto.Multi.t(), atom | String.t(), Changeset.t(), keyword) :: Ecto.Multi.t()
  def update(multi, name, changeset, opts \\ []) do
    opts = Keyword.merge(opts, change: changeset, inserted_at: DateTime.utc_now())
    record_field = "#{name}_record"

    multi
    |> Multi.update(record_field, changeset, opts)
    |> Multi.run("#{name}_version", fn repo, %{^record_field => record} ->
      v = build_version(record, opts)
      if v, do: repo.insert(v), else: {:ok, nil}
    end)
    |> Multi.run("#{name}_deletes", fn repo, _changes ->
      do_update_deletes(repo, changeset, opts)
    end)
  end

  @spec do_update_deletes(Ecto.Repo.t(), Changeset.t(), keyword) ::
          {:ok, [Schema.t()]} | {:error, Changeset.t()}
  defp do_update_deletes(repo, changeset, opts) do
    Enum.reduce_while(deleted_versions(changeset, opts), {:ok, []}, fn deleted, {:ok, acc} ->
      case repo.insert(deleted) do
        {:ok, del} -> {:cont, {:ok, [del | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc """
  Returns an Ecto.Multi with all steps necessary to delete a versioned record.

  An Ecto.Multi is returned which first updates the record itself, inserts a new
  version into the versions table and finally deletes associations as needed.

  If `name` is `"puppy"`, the returned parts will be:

    * `"puppy_record"` - The updated record itself.
    * `"puppy_version"` - The newly inserted version record (is_deleted=TRUE).
  """
  @spec delete(Ecto.Multi.t(), atom | String.t(), Schema.t() | Changeset.t(), Keyword.t()) ::
          Ecto.Multi.t()
  def delete(multi, name, struct_or_changeset, opts \\ []) do
    cs = Changeset.change(struct_or_changeset)

    build_version_fn =
      &build_version(Map.fetch!(&1, "#{name}_record"), change: true, deleted: true)

    multi
    |> Multi.delete("#{name}_record", cs, opts)
    |> Multi.insert("#{name}_version", build_version_fn, opts)
  end

  @doc """
  To be invoked after `Repo.transaction/1`. If successful, the id of "_version"
  will be attached to the `:version_id` field of "_record".
  """
  @spec add_version_to_record({:ok, map} | any, String.t()) :: {:ok, map} | any
  def add_version_to_record({:ok, changes}, name) do
    record_key = "#{name}_record"

    case {Map.get(changes, record_key), Map.get(changes, "#{name}_version")} do
      {%{version_id: _}, %{id: version_id}} ->
        {:ok, put_in(changes, [record_key, :version_id], version_id)}

      _ ->
        {:ok, changes}
    end
  end

  def add_version_to_record(error, _), do: error
end
