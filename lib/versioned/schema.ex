defmodule Versioned.Schema do
  @moduledoc """
  Enhances Ecto.Schema modules to have track a full history of changes.
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
      """
      @spec __versioned__(atom) :: String.t()
      def __versioned__(:source_singular), do: @source_singular

      @primary_key {:id, :binary_id, autogenerate: true}
      schema unquote(source) do
        timestamps(type: :utc_datetime_usec)
        unquote(block)
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
        has:

        * `:is_deleted` - true if the record is deleted.
        * `:#{@source_singular}_id` - id of the #{@source_singular} in the main
          table to which this version belongs. Note that it is just a field and
          not a true relationship so that the main record can be deleted while
          preserving the versions.
        """
        @type t :: %__MODULE__{}

        @primary_key {:id, :binary_id, autogenerate: true}
        schema "#{unquote(source)}_versions" do
          field(:is_deleted, :boolean)
          field(:"#{@source_singular}_id", :binary_id)
          timestamps(type: :utc_datetime_usec, updated_at: false)
          version_lines(unquote(lines_ast))
        end
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

  @spec do_version_line(Macro.t(), Macro.t()) :: Macro.t()
  defp do_version_line({:has_many, _m, [field, entity]}, acc) do
    line_ast =
      quote bind_quoted: [entity: entity, field: field] do
        assoc_mod =
          if function_exported?(entity, :__versioned__, 1),
            do: Module.concat(entity, Version),
            else: entity

        has_many(field, assoc_mod,
          foreign_key: :"#{@source_singular}_id",
          references: :"#{@source_singular}_id"
        )
      end

    [line_ast | acc]
  end

  defp do_version_line(line_ast, acc) do
    [line_ast | acc]
  end
end
