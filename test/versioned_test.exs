defmodule VersionedTest do
  use Versioned.TestCase
  import Ecto.Query
  alias Versioned.Test.{Car, Hobby, Person}
  alias Versioned.Test.Repo

  test "basic functionality" do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})
    {:ok, %{id: person_id}} = Versioned.insert(%Person{car_id: car_id, name: "Wendy"})

    {:ok, %{id: ^car_id}} =
      car
      |> Car.changeset(%{name: "Magnificent"})
      |> Versioned.update()

    assert [
             %Car.Version{car_id: ^car_id, name: "Magnificent"},
             %Car.Version{id: ver_id, car_id: ^car_id, name: "Toad"}
           ] = Versioned.history(Car, car_id)

    assert %{
             id: ^car_id,
             name: "Magnificent",
             people: [%{id: ^person_id, name: "Wendy"}]
           } = Repo.one(from(Car, where: [id: ^car_id], preload: :people))

    assert %{car_id: ^car_id, name: "Toad"} = Versioned.get(Car, ver_id)
  end

  describe "deletion" do
    test "basic" do
      {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})
      {:ok, %{id: ^car_id}} = Versioned.delete(car)

      assert is_nil(Repo.get(Car, car_id))

      assert [
               %{car_id: ^car_id, is_deleted: true, name: "Toad"},
               %{car_id: ^car_id, is_deleted: false, name: "Toad"}
             ] = Versioned.history(Car, car_id)
    end

    test "with related record, raises exception" do
      {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})
      {:ok, _person} = Versioned.insert(%Person{car_id: car_id, name: "Wendy"})

      assert_raise Ecto.ConstraintError, fn ->
        Versioned.delete(car)
      end
    end

    test "with related record, deleting it first" do
      {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})
      {:ok, %{id: person_id} = person} = Versioned.insert(%Person{car_id: car_id, name: "Wendy"})

      # Notice that we don't raise a ContstraintError with the version records
      # pointing at these because we haven't made a db-level constraint.
      {:ok, %{id: ^person_id}} = Versioned.delete(person)
      {:ok, %{id: ^car_id}} = Versioned.delete(car)

      assert is_nil(Repo.get(Car, car_id))
      assert is_nil(Repo.get(Person, person_id))

      assert [
               %Car.Version{is_deleted: true, name: "Toad"},
               %Car.Version{is_deleted: false, name: "Toad"}
             ] = Versioned.history(Car, car_id)

      assert [
               %Person.Version{
                 car_id: ^car_id,
                 is_deleted: true,
                 name: "Wendy",
                 person_id: ^person_id
               },
               %Person.Version{
                 car_id: ^car_id,
                 is_deleted: false,
                 name: "Wendy",
                 person_id: ^person_id
               }
             ] = Versioned.history(Person, person_id)
    end
  end

  test "history with limit" do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Mustang"})

    {:ok, %{id: ^car_id}} = car |> Car.changeset(%{name: "Mustangg"}) |> Versioned.update()
    {:ok, %{id: ^car_id}} = car |> Car.changeset(%{name: "Mustanggg"}) |> Versioned.update()

    assert [
             %Versioned.Test.Car.Version{car_id: car_id, name: "Mustanggg"},
             %Versioned.Test.Car.Version{car_id: car_id, name: "Mustangg"}
           ] = Versioned.history(Car, car_id, limit: 2)
  end

  # The migration added the color column with this feature. Assert it exists.
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

  test "simultaneous inserts, preload" do
    params = %{
      name: "Mustang",
      people: [%{name: "Fred", fancy_hobbies: [%{name: "Go-Kart"}, %{name: "Strudal"}]}]
    }

    {:ok, %{id: car_id, people: [%{id: fred_id}]}} =
      %Car{} |> Car.changeset(params) |> Versioned.insert()

    {:ok, _} =
      Car |> Repo.get(car_id) |> Car.changeset(%{name: "tooo neww"}) |> Versioned.update()

    {:ok, _} = Versioned.insert(%Hobby{person_id: fred_id, name: "too new"})

    assert [p] = Versioned.history(Person, fred_id)

    assert %{
             car_version: %{name: "Mustang"},
             fancy_hobby_versions: [_, _] = hobby_versions,
             name: "Fred"
           } = Versioned.preload(p, [:car_version, :fancy_hobby_versions])

    # (Order is uncertain.)
    for hob <- ~w(Go-Kart Strudal) do
      assert Enum.any?(hobby_versions, &(&1.name == hob))
    end
  end
end
