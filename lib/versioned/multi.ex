defmodule Versioned.Multi do
  @moduledoc "Tools for operating on versioned records."
  import Versioned.Helpers
  alias Ecto.Multi
  alias Ecto.{Changeset, Multi}

  defdelegate new, to: Ecto.Multi

  @typep t :: Multi.t()
  @typep changes :: map
  @typep cs :: Changeset.t()
  @typep name :: Multi.name()
  @typep repo :: Ecto.Repo.t()
  @typep schema :: Ecto.Schema.t()

  @doc """
  Returns an Ecto.Multi with all steps necessary to insert a versioned record.

  If `name` is `"puppy"`, the returned parts will be:

    * `"puppy_record"` - The inserted record itself.
    * `"puppy_version"` - The inserted version record.
  """
  @spec insert(t, name, cs | schema | (changes -> cs | schema), keyword) :: t
  def insert(multi, name, changeset_or_struct_fun, opts \\ []) do
    opts = Keyword.merge(opts, change: true, inserted_at: DateTime.utc_now())
    record_field = "#{name}_record"

    multi
    |> Multi.insert(record_field, changeset_or_struct_fun, opts)
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
    * `"puppy_record_full"` - Internal use only. A tuple with the updated
      record and opts including the changeset.
  """
  @spec update(t, name, cs | (changes -> cs), keyword) :: t
  def update(multi, name, changeset_or_fun, opts \\ []) do
    record_field = "#{name}_record"
    record_field_full = "#{record_field}_full"
    opts = Keyword.merge(opts, inserted_at: DateTime.utc_now())

    multi
    |> Multi.run(record_field_full, fn repo, changes ->
      cs = with f when is_function(f) <- changeset_or_fun, do: f.(changes)
      opts = fn -> Keyword.put(opts, :change, cs) end
      with {:ok, updated} <- repo.update(cs), do: {:ok, {updated, opts.()}}
    end)
    |> Multi.run("#{name}_version", fn repo, %{^record_field_full => {rec, o}} ->
      v = build_version(rec, o)
      if v, do: repo.insert(v), else: {:ok, nil}
    end)
    |> Multi.run("#{name}_deletes", fn repo, %{^record_field_full => {_, o}} ->
      do_update_deletes(repo, o)
    end)
    # Attach the updated record itself, directly.
    |> Multi.run(record_field, fn _, %{^record_field_full => {rec, _}} ->
      {:ok, rec}
    end)
  end

  @spec do_update_deletes(repo, keyword) :: {:ok, [schema]} | {:error, cs}
  defp do_update_deletes(repo, opts) do
    opts[:change]
    |> deleted_versions(opts)
    |> Enum.reduce_while({:ok, []}, fn deleted, {:ok, acc} ->
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
  @spec delete(t, name, schema | cs | (changes -> cs | schema), keyword) :: t
  def delete(multi, name, changeset_or_struct_fun, opts \\ []) do
    do_delete = fn repo, changes ->
      thing = with x when is_function(x) <- changeset_or_struct_fun, do: x.(changes)
      repo.delete(thing, opts)
    end

    build_version = &build_version(Map.fetch!(&1, "#{name}_record"), change: true, deleted: true)

    multi
    |> Multi.run("#{name}_record", do_delete)
    |> Multi.insert("#{name}_version", build_version, opts)
  end

  @doc """
  To be invoked after `Repo.transaction/1`. If successful, the id of "_version"
  will be attached to the `:version_id` field of "_record".
  """
  @spec add_version_to_record({:ok, changes} | any, name) :: {:ok, changes} | any
  def add_version_to_record({:ok, changes}, name) do
    record_key = "#{name}_record"

    case {Map.get(changes, record_key), Map.get(changes, "#{name}_version")} do
      {%{version_id: _}, %{id: version_id}} ->
        {:ok, put_in(changes, [record_key, :version_id], version_id)}

      _ ->
        {:ok, changes}
    end
  end

  def add_version_to_record(value, _), do: value
end
