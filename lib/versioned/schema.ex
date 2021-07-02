defmodule Versioned.Schema do
  @moduledoc """
  Enhances Ecto.Schema modules to track a full history of changes.
  """
  alias Versioned.Helpers

  defmacro __using__(opts) do
    {singular_opt, ecto_opts} = Keyword.pop(opts, :singular)

    quote do
      use Ecto.Schema, unquote(ecto_opts)
      import unquote(__MODULE__)
      @ecto_opts unquote(ecto_opts)
      @source_singular unquote(singular_opt && to_string(singular_opt))
    end
  end

  @doc "Create a versioned schema."
  defmacro versioned_schema(source, do: block) do
    {:__block__, _m, lines_ast} = Helpers.normalize_block(block)

    mod = __CALLER__.module

    quote do
      @source_singular Module.get_attribute(__MODULE__, :source_singular) ||
                         unquote(String.trim_trailing(source, "s"))

      @doc """
      Get some information about this versioned schema.

      The argument, an atom, can be one of:

      * `:entity_fk` - `:#{@source_singular}_id` will be returned, the foreign
        key column on the versions table which points at the real record.
      * `:source_singular` - the string `"#{@source_singular}"` will be
        returned.
      """
      @spec __versioned__(:entity_fk | :source_singular) :: atom | String.t()
      def __versioned__(:entity_fk), do: :"#{@source_singular}_id"
      def __versioned__(:source_singular), do: @source_singular

      @primary_key {:id, :binary_id, autogenerate: true}
      schema unquote(source) do
        field(:version_id, :binary_id, virtual: true)
        timestamps(type: :utc_datetime_usec)
        unquote(remove_versioned_opts(block))
      end

      defmodule Version do
        @moduledoc "A single version in history."
        use Ecto.Schema, @ecto_opts

        @source_singular Module.get_attribute(unquote(mod), :source_singular)

        # Set @foreign_key_type if the main module did.
        fkt = Module.get_attribute(unquote(mod), :foreign_key_type)
        fkt && @foreign_key_type fkt

        @typedoc """
        #{String.capitalize(@source_singular)} version. See
        `#{unquote(inspect(mod))}` for base fields. Additionally, this schema
        has `:is_deleted` (true if the record is deleted) and
        `:#{@source_singular}_id` which holds id of the #{@source_singular}
        in the main table to which this version belongs. Note that it is just
        a field and not a true relationship so that the main record can be
        deleted while preserving the versions.
        """
        @type t :: %__MODULE__{}

        @primary_key {:id, :binary_id, autogenerate: true}
        schema "#{unquote(source)}_versions" do
          field(:is_deleted, :boolean)
          field(:"#{@source_singular}_id", :binary_id)
          timestamps(type: :utc_datetime_usec, updated_at: false)
          version_lines(unquote(lines_ast))
        end

        @doc "Get the Ecto.Schema module for which this version module belongs."
        @spec entity_module :: module
        def entity_module, do: unquote(mod)
      end
    end
  end

  @doc """
  Convert a list of ast lines from the main schema into ast lines to be used
  for the version schema.
  """
  defmacro version_lines(lines_ast) do
    lines_ast
    |> Enum.reduce([], &do_version_line/2)
    |> Enum.reverse()
  end

  # Take the original schema declaration ast and attach to the accumulator the
  # corresponding version schema ast to use.
  @spec do_version_line(Macro.t(), Macro.t()) :: Macro.t()
  defp do_version_line({:belongs_to, m, [field, entity]}, acc),
    do: do_version_line({:belongs_to, m, [field, entity, []]}, acc)

  defp do_version_line({:belongs_to, _m, [field, entity, opts]}, acc) do
    line =
      quote do
        belongs_to(:"#{unquote(field)}", unquote(entity), unquote(opts))
        field(:"#{unquote(field)}_version", :map, virtual: true)
      end

    [line | acc]
  end

  defp do_version_line({:has_many, m, [field, entity]}, acc),
    do: do_version_line({:has_many, m, [field, entity, []]}, acc)

  defp do_version_line({:has_many, _m, [field, entity, field_opts]}, acc) do
    line =
      if field_opts[:versioned] do
        quote do
          has_many(
            :"#{unquote(entity).__versioned__(:source_singular)}_versions",
            Module.concat(unquote(entity), Version),
            foreign_key: :"#{@source_singular}_id",
            references: :"#{@source_singular}_id"
          )
        end
      else
        quote do
          has_many(:"#{unquote(field)}", unquote(entity),
            foreign_key: :"#{@source_singular}_id",
            references: :"#{@source_singular}_id"
          )
        end
      end

    [line | acc]
  end

  defp do_version_line(line, acc) do
    [line | acc]
  end

  # Drop our options from the AST for Ecto.Schema.
  @spec remove_versioned_opts(Macro.t()) :: Macro.t()
  defp remove_versioned_opts({:__block__, top_m, lines}) do
    lines =
      Enum.map(lines, fn
        {:has_many, m, [a, b, opts]} ->
          {:has_many, m, [a, b, Keyword.delete(opts, :versioned)]}

        other ->
          other
      end)

    {:__block__, top_m, lines}
  end
end
