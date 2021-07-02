defmodule Versioned.Test.Car do
  @moduledoc false
  use Versioned.Schema
  alias Versioned.Test.Person
  import Ecto.Changeset

  versioned_schema "cars" do
    field(:name, :string)
    has_many(:people, Person, versioned: true)
  end

  def changeset(car_or_changeset, params) do
    car_or_changeset
    |> cast(params, [:name])
    |> validate_required([:name])
    |> cast_assoc(:people)
  end
end
