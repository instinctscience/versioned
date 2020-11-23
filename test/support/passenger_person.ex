defmodule Versioned.Test.PassengerPerson do
  @moduledoc false
  use Versioned.Schema, singular: :passenger_person
  alias Versioned.Test.Car

  versioned_schema "passenger_people" do
    field(:name, :string)
    belongs_to(:car, Car, type: :binary_id)
  end
end
