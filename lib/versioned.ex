defmodule Versioned do
  @moduledoc "Tools for operating on versioned records."
  import Ecto.Query, except: [preload: 2]
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
    opts = Keyword.put(opts, :inserted_at, DateTime.utc_now())

    Multi.new()
    |> Multi.insert(:record, cs, opts)
    |> Multi.run(:version, fn repo, %{record: record} ->
      case build_version(record, opts) do
        nil -> {:ok, nil}
        changeset -> repo.insert(changeset)
      end
    end)
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
    opts = Keyword.put(opts, :inserted_at, DateTime.utc_now())

    Multi.new()
    |> Multi.update(:record, changeset, opts)
    |> Multi.insert(:version, &build_version(&1.record, opts), opts)
    |> Multi.run(:deleted, fn repo, _changes ->
      deleted_records =
        for deleted <- deleted_records(changeset, opts) do
          repo.insert!(deleted)
        end

      {:ok, deleted_records}
    end)
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

  History will be found based on a module name and id or pass in a struct.

  Options can include anything used by the repo's `all/2` and
  `history_query/3`.
  """
  @spec history(module | Ecto.Schema.t(), any, keyword) :: [Schema.t()]
  def history(module_or_struct, id_or_opts \\ [], opts \\ [])

  def history(%mod{id: id}, id_or_opts, _) do
    history(mod, id, id_or_opts)
  end

  def history(module_or_struct, id_or_opts, opts) do
    module_or_struct
    |> history_query(id_or_opts, opts)
    |> repo().all(opts)
    |> preload(opts[:preload] || [])
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
  @spec build_version(Schema.t(), keyword) :: Changeset.t() | nil
  defp build_version(%mod{} = struct, opts) do
    with params when params != nil <- build_params(struct, opts) do
      mod
      |> Module.concat(Version)
      |> struct()
      |> Changeset.change(params)
    end
  end

  @spec build_params(Schema.t(), keyword) :: map | nil
  defp build_params(%mod{} = struct, opts) do
    with params when params != nil <- maybe_build_version_params(struct, opts) do
      Enum.reduce(mod.__schema__(:associations), params, fn assoc, acc ->
        child = Map.get(struct, assoc)
        assoc_info = mod.__schema__(:association, assoc)

        case build_assoc_params(assoc_info, child, opts) do
          nil ->
            acc

          p ->
            if versioned?(assoc_info.queryable) do
              key = assoc_info.owner.__versioned__(:has_many_field, assoc)
              Map.put(acc, key, p)
            else
              Map.put(acc, assoc, p)
            end
        end
      end)
    end
  end

  # If the struct is versioned, build parameters for the corresponding version
  # record to insert. nil otherwise.
  @spec maybe_build_version_params(Schema.t(), keyword) :: map | nil
  defp maybe_build_version_params(%mod{} = struct, opts) do
    if versioned?(mod) do
      :fields
      |> mod.__schema__()
      |> Enum.reject(&(&1 in [:id, :inserted_at, :updated_at]))
      |> Enum.filter(&(&1 in Module.concat(mod, Version).__schema__(:fields)))
      |> Map.new(&{&1, Map.get(struct, &1)})
      |> Map.put(:"#{mod.__versioned__(:source_singular)}_id", struct.id)
      |> Map.put(:is_deleted, Keyword.get(opts, :deleted, false))
      |> Map.put(:inserted_at, opts[:inserted_at])
    else
      nil
    end
  end

  @spec build_assoc_params(Ecto.Association.t(), Schema.t() | [Schema.t()], keyword) :: list | nil
  defp build_assoc_params(%Ecto.Association.Has{cardinality: :many}, data, opts)
       when is_list(data) do
    Enum.reduce(data, [], fn record, acc ->
      case build_params(record, opts) do
        nil -> acc
        params -> [params | acc]
      end
    end)
  end

  defp build_assoc_params(_, %Ecto.Association.NotLoaded{}, _) do
    nil
  end

  defp build_assoc_params(ecto_assoc, %mod{}, _) do
    raise "No assoc handler while processing #{inspect(mod)}: #{inspect(ecto_assoc)}"
  end

  # Recursively crawl changeset and compile a list of ..................
  @spec deleted_records(Changeset.t(), keyword) :: [map]
  defp deleted_records(%{action: action, data: %mod{}} = changeset, opts) do
    deletes =
      if action == :replace do
        changeset
        |> Changeset.apply_changes()
        |> maybe_build_version_params(Keyword.put(opts, :deleted, true))
        |> case do
          nil -> []
          params -> [struct(Module.concat(mod, Version), params)]
        end
      else
        []
      end

    Enum.reduce(mod.__schema__(:associations), deletes, fn assoc, acc ->
      cardinality = mod.__schema__(:association, assoc).cardinality
      change = Changeset.get_change(changeset, assoc)

      case {cardinality, change} do
        {_, nil} -> acc
        {:one, change} -> acc ++ deleted_records(change, opts)
        {:many, changes} -> acc ++ Enum.flat_map(changes, &deleted_records(&1, opts))
      end
    end)
  end

  # Get the configured Ecto.Repo module.
  @spec repo :: module
  defp repo, do: Application.get_env(:versioned, :repo)

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

  @doc "True if the given module or struct is a version."
  @spec version?(module | Ecto.Schema.t()) :: boolean
  def version?(%mod{}), do: version?(mod)

  def version?(mod),
    do: function_exported?(mod, :entity_module, 0) and versioned?(mod.entity_module())

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
  Preload version associations.
  """
  @spec preload(Ecto.Schema.t() | [Ecto.Schema.t()], atom | list) ::
          Ecto.Schema.t() | [Ecto.Schema.t()]
  def preload(list_or_struct, preload) when is_list(list_or_struct) do
    Enum.map(list_or_struct, &preload(&1, preload))
  end

  def preload(%mod{} = list_or_struct, preload) do
    preload = if is_list(preload), do: preload, else: [preload]
    assoc = &mod.__schema__(:association, &1)

    Enum.reduce(preload, list_or_struct, fn
      {field, sub_preload}, acc ->
        assoc = assoc.(field)
        preloaded = do_preload(acc, assoc, version?(assoc.queryable))
        %{acc | field => preload(preloaded, sub_preload)}

      field, acc when is_atom(field) ->
        assoc = assoc.(field)
        %{acc | field => do_preload(acc, assoc, version?(assoc.queryable))}
    end)
  end

  @spec do_preload(Ecto.Schema.t(), Ecto.Association.t(), boolean) ::
          Ecto.Schema.t() | [Ecto.Schema.t()]
  defp do_preload(struct, %{cardinality: :one} = assoc, true) do
    %{owner_key: owner_key, queryable: assoc_ver_mod} = assoc
    assoc_id = Map.get(struct, owner_key)

    repo().one(
      from assoc_ver in assoc_ver_mod,
        where:
          field(assoc_ver, ^owner_key) == ^assoc_id and
            assoc_ver.inserted_at <= ^struct.inserted_at,
        order_by: {:desc, :inserted_at},
        limit: 1
    )
  end

  defp do_preload(struct, %{cardinality: :many} = assoc, true) do
    %{owner_key: owner_key, queryable: assoc_ver_mod} = assoc
    assoc_ver_mod.entity_module().__schema__(:association, :person)
    assoc_mod = assoc_ver_mod.entity_module()
    assoc_singular_id = :"#{assoc_mod.__versioned__(:source_singular)}_id"

    versions =
      repo().all(
        from assoc_ver in assoc_ver_mod,
          distinct: ^assoc_singular_id,
          # assoc_ver.inserted_at <= ^struct.inserted_at,
          where:
            field(assoc_ver, ^owner_key) == ^Map.get(struct, owner_key) and
              assoc_ver.inserted_at <= ^struct.inserted_at,
          # assoc_ver.inserted_at <= datetime_add(^struct.inserted_at, 1, "second"),
          order_by: {:desc, :inserted_at}
      )

    Enum.reject(versions, & &1.is_deleted)
  end

  defp do_preload(struct, %{field: field}, _) do
    repo().preload(struct, field)
  end
end
