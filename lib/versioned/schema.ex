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

        # Set @foreign_key_type if the main module did.
        with t when not is_nil(t) <- Module.get_attribute(unquote(mod), :foreign_key_type) do
          @foreign_key_type t
        end

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
          # unquote(versions_block)
          # unquote({:__block__, mid, version_lines(lines, quote(do: @source_singular))})
        end
      end
    end
  end

  defmacro version_lines(lines_ast) do
    # IO.inspect(source_singular, label: "SSSINGULAR")
    # {:has_many, [line: 23], [:location_users, {:__aliases__, [line: 23], [:LocationUser]}]}

    lines_ast
    |> Enum.reduce([], fn
      {:has_many, _m, [field, entity]}, acc ->
        ast =
          quote do
            has_many(unquote(field), unquote(entity),
              foreign_key: :"#{@source_singular}_id",
              references: :"#{@source_singular}_id"
            )
          end

        [ast | acc]

      # {:belongs_to, m, [:inserted_by, entity]}

      line, acc ->
        # IO.inspect(line, label: "line")
        [line | acc]
    end)
    |> Enum.reverse()
  end

  # defp do_version_lines(line, acc) do
  #   [line | acc]
  # end

  #   versions_block =
  #     {:__block__, mid,
  #      Enum.reverse(
  #        Enum.reduce(lines, [], fn
  #          {:belongs_to, m, [name | _]}, acc ->
  #            [{:field, m, [:"#{name}_id", :binary_id]} | acc]

  #          {:field, _, [_name, _type, opts]} = line, acc ->
  #            if opts[:virtual], do: acc, else: [line | acc]

  #          {:field, _, _} = line, acc ->
  #            [line | acc]

  #          _, acc ->
  #   end)
  #   |> Enum.reverse()
  # end

  # defp do_version_lines({:has_many, entity}, acc) do
  #   IO.inspect(k, label: "kkkkkkk")
  #   acc
  # end

  # defp do_version_lines(line, acc) do
  #   [line | acc]
  # end

  # versions_block =
  #   {:__block__, mid,
  #    Enum.reverse(
  #      Enum.reduce(lines, [], fn
  #        {:belongs_to, m, [name | _]}, acc ->
  #          [{:field, m, [:"#{name}_id", :binary_id]} | acc]

  #        {:field, _, [_name, _type, opts]} = line, acc ->
  #          if opts[:virtual], do: acc, else: [line | acc]

  #        {:field, _, _} = line, acc ->
  #          [line | acc]

  #        _, acc ->
  #          acc
  #      end)
  #    )}
end
