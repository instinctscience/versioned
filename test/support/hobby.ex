defmodule Versioned.Test.Hobby do
  @moduledoc false
  use Versioned.Schema, singular: :hobby
  alias Ecto.Changeset
  alias Versioned.Test.Person

  versioned_schema "hobbies" do
    field :name, :string
    belongs_to :person, Person, type: :binary_id
  end

  def changeset(car_or_changeset, params) do
    car_or_changeset
    |> Changeset.cast(params, [:inserted_at, :name])
    |> Changeset.validate_required([:name])
  end
end
