defmodule Versioned.MultiTest do
  use Versioned.TestCase
  alias Versioned.Multi
  alias Versioned.Test.Car
  alias Versioned.Test.Repo

  test "insert" do
    assert {:ok, %{"car_record" => %{id: car_id}}} =
             Multi.new()
             |> Multi.insert(:car, %Car{name: "Toad"})
             |> Repo.transaction()

    assert [%Car.Version{id: version_id, name: "Toad"}] = Versioned.history(Car, car_id)

    assert %{car_id: ^car_id, name: "Toad"} = Versioned.get(Car.Version, version_id)
  end

  test "update with changeset" do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})

    assert {:ok, %{"car_record" => %{id: ^car_id, name: "Sprocket"}}} =
             Multi.new()
             |> Multi.update(:car, Car.changeset(car, %{name: "Sprocket"}))
             |> Repo.transaction()

    assert [%Car.Version{name: "Sprocket"}, _] = Versioned.history(Car, car_id)
  end

  test "update with function" do
    fun = fn _repo, %{"car_record" => car} ->
      Car.changeset(car, %{name: "#{car.name} Updated"})
    end

    assert {:ok, %{"car_updated_record" => %{id: car_id, name: "Toad Updated"}}} =
             Multi.new()
             |> Multi.insert(:car, %Car{name: "Toad"})
             |> Multi.update(:car_updated, fun)
             |> Repo.transaction()

    assert [%Car.Version{name: "Toad Updated"}, %{name: "Toad"}] = Versioned.history(Car, car_id)
  end
end
