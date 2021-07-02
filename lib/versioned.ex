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
  @spec insert(Schema.t() | Changeset.t(), keyword) ::
          {:ok, Schema.t()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}
  def insert(struct_or_changeset, opts \\ []) do
    cs = Changeset.change(struct_or_changeset)

    Multi.new()
    |> Multi.insert(:record, cs, opts)
    |> Multi.insert(:version, &build_version(&1.record), opts)
    |> repo().transaction()
    |> maybe_add_version_id_and_return_record()
  end

  @doc """
  Updates a changeset (of a versioned schema) using its primary key.

  This function uses the Ecto.Repo module, first calling `update/2` to update
  the record itself, and then `insert/1` to add a copy of the new version to
  the versions table.
  """
  @spec update(Changeset.t(), keyword) ::
          {:ok, Schema.t()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}
  def update(changeset, opts \\ []) do
    Multi.new()
    |> Multi.update(:record, changeset, opts)
    |> Multi.insert(:version, &build_version(&1.record), opts)
    |> repo().transaction()
    |> maybe_add_version_id_and_return_record()
  end

  @doc """
  Deletes a struct using its primary key and adds a deleted version.
  """
  @spec delete(struct_or_changeset :: Schema.t() | Changeset.t(), opts :: Keyword.t()) ::
          {:ok, Schema.t()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}
  def delete(struct_or_changeset, opts \\ []) do
    cs = Changeset.change(struct_or_changeset)

    Multi.new()
    |> Multi.delete(:record, cs, opts)
    |> Multi.insert(:version, &build_version(&1.record, deleted: true), opts)
    |> repo().transaction()
    |> maybe_add_version_id_and_return_record()
  end

  # If the transaction return is successful and the record has a `:version_id`
  # field, then populate it with the newly created version id.
  @spec maybe_add_version_id_and_return_record(tuple) ::
          {:ok, Schema.t()} | {:error, Changeset.t()} | {:error, String.t()}
  defp maybe_add_version_id_and_return_record(
         {:ok, %{record: %{version_id: _} = record, version: %{id: version_id}}}
       ),
       do: {:ok, %{record | version_id: version_id}}

  defp maybe_add_version_id_and_return_record({:ok, %{record: record}}), do: {:ok, record}

  defp maybe_add_version_id_and_return_record({:error, _, %Ecto.Changeset{} = changeset, _}),
    do: {:error, changeset}

  defp maybe_add_version_id_and_return_record({:error, bad_op, bad_val, _changes}) do
    {:error, "Transaction error in #{bad_op} with #{inspect(bad_val)}"}
  end

  defp maybe_add_version_id_and_return_record({:error, msg}) when is_binary(msg),
    do: {:error, "Transaction error: #{msg}"}

  defp maybe_add_version_id_and_return_record({:error, err}),
    do: {:error, "Transaction error: #{inspect(err)}"}

  defp maybe_add_version_id_and_return_record(ret), do: ret

  @doc """
  List all versions for a schema module, newest first.

  Options can include anything used by the repo's `all/2` and
  `history_query/3`.
  """
  @spec history(module, any, keyword) :: [Schema.t()]
  def history(module, id, opts \\ []) do
    repo().all(history_query(module, id, opts), opts)
  end

  @doc """
  Get a version for a schema module.

  Options can include anything used by the repo's `get/3`.
  """
  @spec get(module, any, keyword) :: Schema.t() | nil
  def get(module, id, opts \\ []) do
    repo().get(version_mod(module), id, opts)
  end

  @doc """
  Get the query to fetch all the versions for a schema, newest first.

  ## Options

  * `:limit` - Max number of records to return. Default: return all records.
  """
  @spec history_query(module, any, keyword) :: Ecto.Queryable.t()
  def history_query(module, id, opts \\ []) do
    version_mod = version_mod(module)
    fk = module.__versioned__(:entity_fk)
    query = from(version_mod, where: ^[{fk, id}], order_by: [desc: :inserted_at])

    Enum.reduce(opts, query, fn
      {:limit, limit}, query -> from(query, limit: ^limit)
      {_, _}, query -> query
    end)
  end

  @doc "Get the timestamp for the very first version of this entity."
  @spec inserted_at(struct) :: DateTime.t() | nil
  def inserted_at(%ver_mod{} = ver_struct) do
    fk = ver_mod.entity_module().__versioned__(:entity_fk)
    id = Map.get(ver_struct, fk)
    query = from(ver_mod, where: ^[{fk, id}], limit: 1, order_by: :inserted_at)
    result = repo().one(query)

    result && result.inserted_at
  end

  # Create a `version_mod` struct to insert from a new instance of the record.
  # Pass option `deleted: true` to mark as deleted.
  @spec build_version(Schema.t(), keyword) :: Changeset.t()
  defp build_version(%mod{} = struct, opts \\ []) do
    # This inserted_at is used for main record and all child records so that
    # history can be fetched reliably since children would be inserted ~1/100th
    # of a second later.
    opts = Keyword.put(opts, :inserted_at, DateTime.utc_now())

    mod
    |> Module.concat(Version)
    |> struct()
    |> Changeset.change(build_params(struct, opts))
  end

  @spec build_params(Schema.t(), keyword) :: map
  defp build_params(%mod{} = struct, opts) do
    params =
      :fields
      |> mod.__schema__()
      |> Enum.reject(&(&1 in [:id, :inserted_at, :updated_at]))
      |> Enum.filter(&(&1 in Module.concat(mod, Version).__schema__(:fields)))
      |> Map.new(&{&1, Map.get(struct, &1)})
      |> Map.put(:"#{mod.__versioned__(:source_singular)}_id", struct.id)
      |> Map.put(:is_deleted, Keyword.get(opts, :deleted, false))
      |> Map.put(:inserted_at, opts[:inserted_at])

    Enum.reduce(mod.__schema__(:associations), params, fn assoc, acc ->
      child = Map.get(struct, assoc)
      assoc_info = mod.__schema__(:association, assoc)

      case build_assoc_params(assoc_info, child, opts) do
        nil ->
          acc

        p ->
          if versioned?(assoc_info.queryable) do
            singular = assoc_info.queryable.__versioned__(:source_singular)
            Map.put(acc, :"#{singular}_versions", p)
          else
            Map.put(acc, assoc, p)
          end
      end
    end)
  end

  @spec build_assoc_params(Ecto.Association.t(), Schema.t() | [Schema.t()], keyword) :: list | nil
  defp build_assoc_params(%Ecto.Association.Has{cardinality: :many}, data, opts)
       when is_list(data) do
    Enum.map(data, &build_params(&1, opts))
  end

  defp build_assoc_params(_, %Ecto.Association.NotLoaded{}, _) do
    nil
  end

  defp build_assoc_params(ecto_assoc, %mod{}, _) do
    raise "No assoc handler while processing #{inspect(mod)}: #{inspect(ecto_assoc)}"
  end

  # Get the configured Ecto.Repo module.
  @spec repo :: module
  defp repo do
    Application.get_env(:versioned, :repo)
  end

  @doc "Get the version module from the subject module."
  @spec version_mod(module) :: module
  def version_mod(module), do: Module.concat(module, Version)

  @doc """
  True if the Ecto.Schema module is versioned.

  This means there is a corresponding Ecto.Schema module with an extra
  ".Version" on the end.
  """
  @spec versioned?(module) :: boolean
  def versioned?(mod), do: function_exported?(mod, :__versioned__, 1)

  @doc """
  Build the query to populate the `:version_id` virtual field on a versioned
  entity.

  `query` may be any existing base query for the entity which is versioned.
  `mod`, if defined, should be the entity module name itself. If not defined,
  `query` must be this module name and not any type of query.
  """
  @spec with_versions(Ecto.Queryable.t(), Ecto.Schema.t() | nil) :: Ecto.Query.t()
  def with_versions(query, mod \\ nil) do
    mod = mod || query
    ver_mod = Module.concat(mod, Version)
    singular_id = :"#{mod.__versioned__(:source_singular)}_id"

    versions =
      from ver_mod,
        distinct: ^singular_id,
        order_by: {:desc, :inserted_at}

    from q in query,
      join: v in subquery(versions),
      on: q.id == field(v, ^singular_id),
      select_merge: %{version_id: v.id}
  end

  @doc """
  Preload version associations. (They might be deleted.)
  """
  @spec preload(Ecto.Schema.t(), list) :: Ecto.Schema.t()
  def preload(%mod{inserted_at: inserted_at} = ver_struct, preloads) do
    entity = mod.entity_module()

    Enum.reduce(preloads, ver_struct, fn
      field, acc when is_atom(field) ->
        field_str = "#{field}"

        cond do
          String.ends_with?(field_str, "_version") ->
            assoc_singular = :"#{String.trim_trailing(field_str, "_version")}"
            assoc_singular_id = :"#{assoc_singular}_id"
            assoc_id = Map.get(ver_struct, assoc_singular_id)
            %{queryable: assoc_mod} = mod.__schema__(:association, assoc_singular)
            assoc_ver_mod = Module.concat(assoc_mod, Version)

            version =
              repo().one(
                from assoc_ver in assoc_ver_mod,
                  where:
                    field(assoc_ver, ^assoc_singular_id) == ^assoc_id and
                      assoc_ver.inserted_at <= ^ver_struct.inserted_at,
                  order_by: {:desc, :inserted_at},
                  limit: 1
              )

            %{acc | field => version}

          String.ends_with?(field_str, "_versions") ->
            entity_id = :"#{mod.entity_module().__versioned__(:source_singular)}_id"
            assoc_singular = :"#{String.trim_trailing(field_str, "_versions")}"
            assoc_singular_id = :"#{assoc_singular}_id"

            %{queryable: assoc_mod} = mod.__schema__(:association, field)

            versions =
              repo().all(
                from assoc_ver in assoc_mod,
                  distinct: ^assoc_singular_id,
                  # distinct: [desc: :inserted_at, asc: :id],
                  where:
                    field(assoc_ver, ^entity_id) == ^Map.get(ver_struct, entity_id) and
                      assoc_ver.inserted_at <= ^ver_struct.inserted_at,
                  order_by: {:desc, :inserted_at}
              )

            %{acc | field => versions}

          true ->
            repo().preload(acc, field)
        end
    end)
  end
end
