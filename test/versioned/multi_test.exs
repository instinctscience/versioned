defmodule Versioned.MultiTest do
  use Versioned.TestCase
  alias Ecto.Changeset
  alias Versioned.Multi
  alias Versioned.Test.Car
  alias Versioned.Test.Repo

  defp test_insert(input) do
    assert {:ok, %{car: %{id: car_id}}} =
             Multi.new()
             |> Multi.insert(:car, input)
             |> Repo.transaction()

    assert [%Car.Version{id: version_id, name: "Toad"}] = Versioned.history(Car, car_id)

    assert %{car_id: ^car_id, name: "Toad"} = Versioned.get(Car.Version, version_id)
  end

  test "insert with schema" do
    test_insert(%Car{name: "Toad"})
  end

  test "insert with changeset" do
    test_insert(Car.changeset(%Car{}, %{name: "Toad"}))
  end

  test "insert with function" do
    test_insert(fn _ -> %Car{name: "Toad"} end)
  end

  test "update with changeset" do
    {:ok, car} = Versioned.insert(%Car{name: "Toad"})

    assert {:ok, %{car: %{name: "Magnificent"}}} =
             Multi.new()
             |> Multi.update(:car, Car.changeset(car, %{name: "Magnificent"}))
             |> Repo.transaction()

    assert [%Car.Version{name: "Magnificent"}, %{name: "Toad"}] = Versioned.history(Car, car.id)
  end

  test "update with function" do
    fun = &Car.changeset(&1.car, %{name: "Magnificent"})

    assert {:ok, %{car_updated: %{name: "Magnificent"} = car}} =
             Multi.new()
             |> Multi.insert(:car, %Car{name: "Toad"})
             |> Multi.update(:car_updated, fun)
             |> Repo.transaction()

    assert [%Car.Version{name: "Magnificent"}, %{name: "Toad"}] = Versioned.history(Car, car.id)
  end

  test "delete with schema" do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})

    assert {:ok, %{car: %{id: ^car_id}}} =
             Multi.new()
             |> Multi.delete(:car, car)
             |> Repo.transaction()

    assert [%Car.Version{is_deleted: true}, %Car.Version{is_deleted: false}] =
             Versioned.history(Car, car_id)
  end

  test "delete with changeset" do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})

    assert {:ok, %{car: %{id: ^car_id}}} =
             Multi.new()
             |> Multi.delete(:car, Changeset.change(car))
             |> Repo.transaction()

    assert [%Car.Version{is_deleted: true}, %Car.Version{is_deleted: false}] =
             Versioned.history(Car, car_id)
  end

  test "delete with function" do
    assert {:ok, %{car: %{id: car_id}, car_deleted: %{id: car_id}}} =
             Multi.new()
             |> Multi.insert(:car, %Car{name: "Toad"})
             |> Multi.delete(:car_deleted, & &1.car)
             |> Repo.transaction()

    assert [%Car.Version{is_deleted: true}, %Car.Version{is_deleted: false}] =
             Versioned.history(Car, car_id)
  end
end
