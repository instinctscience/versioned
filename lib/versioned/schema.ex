defmodule Versioned.Schema do
  @moduledoc """
  Enhances Ecto.Schema modules to have track a full history of changes.
  """

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
    # If block has only one line, then it's not wrapped the same way.
    # Normalize input by wrapping in this case.
    {:__block__, mid, lines} =
      with {x, m, _} = line when x != :__block__ <- block do
        {:__block__, m, [line]}
      end

    version_block =
      {:__block__, mid,
       Enum.filter(lines, fn
         {x, _, _} when x in [:belongs_to, :field] -> true
         {x, _, _} when x in [:has_many, :many_to_many] -> false
       end)}

    mod = __CALLER__.module
    version_mod = Module.concat(mod, Version)

    quote do
      @source_singular Module.get_attribute(__MODULE__, :singular_opt) ||
                         unquote(String.trim_trailing(source, "s"))

      @doc "Get the non-plural name of the source."
      @spec source_singular :: String.t()
      def source_singular, do: @source_singular

      @primary_key {:id, :binary_id, autogenerate: true}
      schema unquote(source) do
        field(:is_deleted, :boolean)
        has_many(:versions, unquote(version_mod))
        timestamps(type: :utc_datetime_usec)
        unquote(block)
      end

      defmodule Version do
        @moduledoc "A single version in history."
        use Ecto.Schema, @ecto_opts

        @source_singular Module.get_attribute(unquote(mod), :source_singular)

        @primary_key {:id, :binary_id, autogenerate: true}
        schema "#{@source_singular}_versions" do
          field(:is_deleted, :boolean)
          belongs_to(:"#{@source_singular}", unquote(mod), type: :binary_id)
          timestamps(type: :utc_datetime_usec, updated_at: false)
          unquote(version_block)
        end
      end
    end
  end
end
