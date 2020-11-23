defmodule Versioned.Test.Car do
  @moduledoc false
  use Versioned.Schema
  alias Ecto.Changeset
  alias Versioned.Test.PassengerPerson

  versioned_schema "cars" do
    field(:name, :string)
    has_many(:passenger_people, PassengerPerson)
  end

  def changeset(car_or_changeset, params) do
    car_or_changeset
    |> Changeset.cast(params, [:name])
    |> Changeset.validate_required([:name])
  end
end
