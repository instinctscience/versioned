defmodule Versioned.Helpers do
  @moduledoc "Tools shared between modules. (For internal use.)"
  alias Ecto.{Changeset, Schema}

  @doc "Wrap a line of AST in a block if it isn't already wrapped."
  @spec normalize_block(Macro.t()) :: Macro.t()
  def normalize_block({x, m, _} = line) when x != :__block__,
    do: {:__block__, m, [line]}

  def normalize_block(block), do: block

  @doc """
  Create a `version_mod` struct to insert from a new instance of the record.

  ## Options

  * `:deleted` - If `true`, records will marked as deleted.
  * `:change` - For updates, an `t:Ecto.Changeset.t/0` should be provided to
    inform which records were inserted vs updated vs deleted.
  """
  @spec build_version(Schema.t(), keyword) :: Changeset.t() | nil
  def build_version(%mod{} = struct, opts) do
    with %{} = params <- build_params(struct, opts) do
      mod
      |> Versioned.version_mod()
      |> struct()
      |> Changeset.change(params)
    end
  end

  @doc """
  Recursively crawl changeset and compile a list of version structs with
  is_deleted set to true.
  """
  @spec deleted_versions(Changeset.t(), keyword) :: [Ecto.Schema.t()]
  def deleted_versions(%{action: action, data: %mod{}} = changeset, opts) do
    deletes =
      if action == :replace do
        changeset
        |> Changeset.apply_changes()
        |> maybe_build_version_params(Keyword.put(opts, :deleted, true))
        |> case do
          nil -> []
          params -> [struct(Versioned.version_mod(mod), params)]
        end
      else
        []
      end

    Enum.reduce(mod.__schema__(:associations), deletes, fn assoc, acc ->
      %{cardinality: cardinality} = mod.__schema__(:association, assoc)
      change = Changeset.get_change(changeset, assoc)

      case {cardinality, change} do
        {_, nil} -> acc
        {:one, change} -> acc ++ deleted_versions(change, opts)
        {:many, changes} -> acc ++ Enum.flat_map(changes, &deleted_versions(&1, opts))
      end
    end)
  end

  @spec build_params(Schema.t(), keyword) :: map | nil
  defp build_params(%mod{} = struct, opts) do
    with %{} = params <- maybe_build_version_params(struct, opts) do
      Enum.reduce(mod.__schema__(:associations), params, fn assoc_name, acc ->
        :association |> mod.__schema__(assoc_name) |> do_build_params(struct, opts, acc)
      end)
    end
  end

  @spec do_build_params(Ecto.Association.t(), Schema.t(), keyword, map) :: map
  defp do_build_params(
         %{cardinality: cardinality, field: field, owner: owner, queryable: queryable} =
           assoc_info,
         struct,
         opts,
         acc
       ) do
    child = Map.get(struct, field)
    v? = Versioned.versioned?(queryable)

    finish = fn
      _, params, false -> Map.put(acc, field, params)
      ver_key, params, true -> Map.put(acc, ver_key, params)
    end

    case {cardinality, build_assoc_params(assoc_info, child, opts)} do
      {_, nil} -> acc
      {:one, params} -> finish.(:"#{field}_version", params, v?)
      {:many, list} -> finish.(owner.__versioned__(:has_many_field, field), list, v?)
    end
  end

  defp do_build_params(_, _, _, acc), do: acc

  # If the struct is versioned, build parameters for the corresponding version
  # record to insert. nil otherwise.
  @spec maybe_build_version_params(Schema.t(), keyword) :: map | nil
  defp maybe_build_version_params(%mod{} = struct, opts) do
    change = opts[:change]

    if Versioned.versioned?(mod) and (not is_map(change) or 0 < map_size(change.changes)) do
      :fields
      |> mod.__schema__()
      |> Enum.reject(&(&1 in [:id, :inserted_at, :updated_at]))
      |> Enum.filter(&(&1 in Versioned.version_mod(mod).__schema__(:fields)))
      |> Map.new(&{&1, Map.get(struct, &1)})
      |> Map.put(:"#{mod.__versioned__(:source_singular)}_id", struct.id)
      |> Map.put(:is_deleted, Keyword.get(opts, :deleted, false))
      |> Map.put(:inserted_at, opts[:inserted_at])
    else
      nil
    end
  end

  # Build parameters for an association if data is present.
  @spec build_assoc_params(Ecto.Association.t(), Schema.t() | [Schema.t()], keyword) :: list | nil
  defp build_assoc_params(_, %Ecto.Association.NotLoaded{}, _) do
    nil
  end

  defp build_assoc_params(%{cardinality: :one, field: field}, data, opts) do
    change =
      with %{} = cs <- opts[:change] do
        Changeset.get_change(cs, field)
      end

    build_params(data, Keyword.put(opts, :change, change))
  end

  defp build_assoc_params(%{cardinality: :many, field: field}, data, opts)
       when is_list(data) do
    {inserted_params_list, change_fn} =
      with %{} = change <- opts[:change],
           cs_list when is_list(cs_list) <- Changeset.get_change(change, field) do
        change_fn = fn record ->
          Enum.find(cs_list, &(Changeset.get_field(&1, :id) == record.id))
        end

        inserted_css = Enum.filter(cs_list, &(&1.action == :insert))

        inserted_params_list =
          inserted_css |> Enum.map(&build_params(&1, opts)) |> Enum.filter(& &1)

        {inserted_params_list, change_fn}
      else
        true_or_nil -> {[], fn _ -> true_or_nil end}
      end

    Enum.reduce(data, inserted_params_list, fn record, acc ->
      case build_params(record, Keyword.put(opts, :change, change_fn.(record))) do
        nil -> acc
        params -> [params | acc]
      end
    end)
  end
end
