defmodule Versioned.Test.Person do
  @moduledoc false
  use Versioned.Schema, singular: :person
  import Ecto.Changeset
  alias Versioned.Test.{Car, Hobby}

  versioned_schema "people" do
    field :name, :string
    belongs_to :car, Car, type: :binary_id, versioned: true
    has_many :fancy_hobbies, Hobby, on_replace: :delete, versioned: :fancy_hobby_versions
  end

  def changeset(car_or_changeset, params) do
    car_or_changeset
    |> cast(params, [:name])
    |> validate_required([:name])
    |> cast_assoc(:fancy_hobbies)
    |> cast_assoc(:car)
  end
end
