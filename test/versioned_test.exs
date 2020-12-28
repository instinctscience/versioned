defmodule VersionedTest do
  use Versioned.TestCase
  import Ecto.Query
  alias Versioned.Test.{Car, PassengerPerson}
  alias Versioned.Test.Repo

  test "basic functionality" do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})
    {:ok, %{id: person_id}} = Versioned.insert(%PassengerPerson{car_id: car_id, name: "Wendy"})

    {:ok, %{id: ^car_id}} =
      car
      |> Car.changeset(%{name: "Magnificent"})
      |> Versioned.update()

    assert [
             %Car.Version{car_id: ^car_id, name: "Magnificent"},
             %Car.Version{car_id: ^car_id, name: "Toad"}
           ] = Versioned.history(Car, car_id)

    assert %{
             id: ^car_id,
             name: "Magnificent",
             passenger_people: [%{id: ^person_id, name: "Wendy"}]
           } = Repo.one(from(Car, where: [id: ^car_id], preload: :passenger_people))
  end

  test "deletion" do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})
    {:ok, %{id: ^car_id}} = Versioned.delete(car)

    assert %{is_deleted: true, name: "Toad"} = Repo.get(Car, car_id)

    assert [%{is_deleted: true, name: "Toad"}, %{is_deleted: false, name: "Toad"}] =
             Versioned.history(Car, car_id)

    assert is_nil(Versioned.get(Car, car_id))
  end

  test "add_versioned_column" do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(Repo, """
      SELECT
        table_name,
        column_name,
        data_type
      FROM
        information_schema.columns
      WHERE
        table_name = 'cars';
      """)

    assert Enum.any?(rows, &(&1 == ["cars", "color", "character varying"]))
  end
end
