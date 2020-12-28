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
      @singular_opt unquote(singular_opt && to_string(singular_opt))
    end
  end

  @doc "Create a versioned schema."
  defmacro versioned_schema(source, do: block) do
    {:__block__, mid, lines} = Helpers.normalize_block(block)

    # For versions table, include only lines which yield local foreign keys.
    versions_block =
      {:__block__, mid,
       Enum.reverse(
         Enum.reduce(lines, [], fn
           {:belongs_to, m, [name | _]}, acc -> [{:field, m, [:"#{name}_id", :binary_id]} | acc]
           {:field, _, _} = line, acc -> [line | acc]
           _, acc -> acc
         end)
       )}

    mod = __CALLER__.module

    quote do
      @source_singular Module.get_attribute(__MODULE__, :singular_opt) ||
                         unquote(String.trim_trailing(source, "s"))

      @doc "Get the non-plural name of the source."
      @spec source_singular :: String.t()
      def source_singular, do: @source_singular

      @primary_key {:id, :binary_id, autogenerate: true}
      schema unquote(source) do
        timestamps(type: :utc_datetime_usec)
        unquote(block)
      end

      defmodule Version do
        @moduledoc "A single version in history."
        use Ecto.Schema, @ecto_opts

        @source_singular Module.get_attribute(unquote(mod), :source_singular)

        @typedoc """
        #{String.upcase(@source_singular)} version. See `#{unquote(mod)}` for
        base fields. Additionally, this schema has:

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
          unquote(versions_block)
        end
      end
    end
  end
end
