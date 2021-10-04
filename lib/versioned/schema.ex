defmodule Versioned.Schema do
  @moduledoc """
  Enhances `Ecto.Schema` modules to track a full history of changes.

  The `versioned_schema` macro works just like `schema` in `Ecto.Schema` but it
  also builds an `OriginalModule.Version` schema module as well to represent a
  version at a particular point in time.

  In addition to options allowed by `Ecto.Schema`, new ones are also allowed.

  ## Additional `belongs_to` Options

    * `:versioned` - If `true`, an additional field of the same name but with
      `_version` appended will be created.

  Example:

      versioned_schema "people" do
        belongs_to :car, Car, type: :binary_id, versioned: true
      end

  ## Additional `has_many` Options

    * `:versioned` - If `true`, an additional field of the same name but with
      `_version` appended will be created. If defined as another truthy atom,
      then that field name will be used instead.

  Example:

      versioned_schema "cars" do
        has_many :people, Person, on_replace: :delete, versioned: :person_versions
      end

  ## Example

      defmodule MyApp.Car do
        use Versioned.Schema

        versioned_schema "cars" do
          field :name, :string
          has_many :people, MyApp.Person, versioned: true
        end
      end

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
      * `:source_singular` - String `"#{@source_singular}"` will be returned.
      * `:has_many_fields` - List of field name atoms which are has_many.
      """
      @spec __versioned__(:entity_fk | :source_singular | :has_many_fields) ::
              atom | [atom] | String.t()
      def __versioned__(:entity_fk), do: :"#{@source_singular}_id"
      def __versioned__(:source_singular), do: @source_singular
      def __versioned__(:has_many_fields), do: __MODULE__.Version.has_many_fields()

      @doc """
      Given the has_many `field` name, get the has_many field name for the
      versioned schema.
      """
      @spec __versioned__(:has_many_field, atom) :: atom
      def __versioned__(:has_many_field, field), do: __MODULE__.Version.has_many_field(field)

      # Allow the using module to define @primary_key as an exit hatch.
      unless Module.has_attribute?(__MODULE__, :primary_key) do
        @primary_key {:id, :binary_id, autogenerate: true}
      end

      schema unquote(source) do
        field :version_id, :binary_id, virtual: true
        has_many :versions, __MODULE__.Version
        timestamps type: :utc_datetime_usec
        unquote(remove_versioned_opts(block))
      end

      defmodule Version do
        @moduledoc "A single version in history."
        use Ecto.Schema, @ecto_opts

        @before_compile {unquote(__MODULE__), :version_before_compile}
        @source_singular Module.get_attribute(unquote(mod), :source_singular)

        parent_primary_key_type =
          if Module.get_attribute(unquote(mod), :primary_key_uuid) do
            :binary_id
          else
            :integer
          end

        Module.register_attribute(__MODULE__, :has_many_fields, accumulate: true)

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
          field :is_deleted, :boolean
          belongs_to :"#{@source_singular}", unquote(mod), type: parent_primary_key_type
          timestamps type: :utc_datetime_usec, updated_at: false
          version_lines(unquote(lines_ast))
        end

        @doc "Get the Ecto.Schema module for which this version module belongs."
        @spec entity_module :: module
        def entity_module, do: unquote(mod)
      end
    end
  end

  # This ast is added to the end of the Version module.
  defmacro version_before_compile(_env) do
    quote do
      @doc "List of field name atoms in the main schema which are has_many."
      @spec has_many_fields :: [atom]
      def has_many_fields, do: Keyword.keys(@has_many_fields)

      @doc """
      Given the has_many `field` name in the main schema, get the has_many field
      name for the versioned schema.
      """
      @spec has_many_field(atom) :: atom
      def has_many_field(field), do: @has_many_fields[field]
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

  defp do_version_line({:belongs_to, _m, [field, entity, field_opts]} = orig_ast, acc) do
    do_belongs_to = fn key ->
      quote do
        belongs_to unquote(key),
                   unquote(entity),
                   unquote(Keyword.delete(field_opts, :versioned))

        belongs_to :"#{unquote(key)}_version", Versioned.version_mod(unquote(entity)),
          define_field: false,
          foreign_key: :"#{unquote(field)}_id"
      end
    end

    line =
      if field_opts[:versioned] in [nil, false],
        do: orig_ast,
        else: do_belongs_to.(field)

    [line | acc]
  end

  defp do_version_line({:has_many, m, [field, entity]}, acc),
    do: do_version_line({:has_many, m, [field, entity, []]}, acc)

  defp do_version_line({:has_many, _m, [field, entity, field_opts]}, acc) do
    do_has_many = fn key ->
      quote do
        @has_many_fields {unquote(field), unquote(key)}

        ver_mod = Versioned.version_mod(unquote(entity))
        foreign_key = unquote(field_opts[:foreign_key]) || :"#{@source_singular}_id"

        has_many unquote(key), ver_mod,
          foreign_key: foreign_key,
          references: :"#{@source_singular}_id"
      end
    end

    line =
      case field_opts[:versioned] do
        # Field is not versioned.
        v when v in [nil, false] ->
          quote do
            @has_many_fields {unquote(field), unquote(field)}

            has_many :"#{unquote(field)}", unquote(entity),
              foreign_key: :"#{@source_singular}_id",
              references: :"#{@source_singular}_id"
          end

        # has_many declaration used `versioned: true` -- just use an obvious name.
        true ->
          do_has_many.(quote do: :"#{unquote(entity).__versioned__(:source_singular)}_versions")

        # `:versioned` option used a proper key name -- use that.
        versions_key ->
          do_has_many.(versions_key)
      end

    [line | acc]
  end

  defp do_version_line(line, acc) do
    [line | acc]
  end

  # Drop our options from the AST for Ecto.Schema because it croaks otherwise.
  @spec remove_versioned_opts(Macro.t()) :: Macro.t()
  defp remove_versioned_opts({:__block__, top_m, lines}) do
    lines =
      Enum.map(lines, fn
        {:has_many, m, [a, b, opts]} ->
          {:has_many, m, [a, b, Keyword.delete(opts, :versioned)]}

        {:belongs_to, m, [a, b, opts]} ->
          {:belongs_to, m, [a, b, Keyword.delete(opts, :versioned)]}

        other ->
          other
      end)

    {:__block__, top_m, lines}
  end
end
