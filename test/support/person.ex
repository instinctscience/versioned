defmodule Versioned.Test.Person do
  @moduledoc false
  use Versioned.Schema, singular: :person
  import Ecto.Changeset
  alias Versioned.Test.{Car, Hobby}

  versioned_schema "people" do
    field(:name, :string)
    belongs_to(:car, Car, type: :binary_id)
    has_many(:hobbies, Hobby, versioned: true)
  end

  def changeset(car_or_changeset, params) do
    car_or_changeset
    |> cast(params, [:name])
    |> validate_required([:name])
    |> cast_assoc(:hobbies)
  end
end
