# Versioned

Versioned is a tool for enhancing `Ecto.Schema` modules to keep a full
history of changes such that no historical data is lost.

The underlying method is to create a corresponding "versions" table where any
change can be found as an inserted record. When a record is deleted, the
`:is_deleted` field will be set to `true` in two places: the preexisting,
main record and the newly inserted record in the versions table.

Versioned provides helpers for migrations and schemas, and then the
`Versioned` module can be used in place of your application's `Repo` module
for several common uses to manage these records.

## Installation

```elixir
def deps do
  [
    {:versioned,
      git: "https://github.com/instinctscience/versioned.git",
      branch: "master"}
  ]
end
```

## Example

```elixir
defmodule MyApp.Repo.Migrations.CreateCar do
  use Versioned.Migration

  def change do
    create_versioned_table(:cars) do
      add(:name, :string)
    end
  end
end

defmodule MyApp.Car do
  use Versioned.Schema

  versioned_schema "cars" do
    field(:name, :string)
  end
end

defmodule MyApp do
  alias MyApp.Car

  def do_some_stuff do
    {:ok, %{id: car_id} = car} = Versioned.insert(%Car{name: "Toad"})

    {:ok, car} =
      car
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.cast(%{name: "Magnificent"}, [:name])
      |> Versioned.update()

    {:ok, car} = Versioned.delete(car)

    # `Versioned.history/2` returns all changes, newest first.
    [
      %Car.Version{car_id: ^car_id, name: "Magnificent", is_deleted: true},
      %Car.Version{car_id: ^car_id, name: "Magnificent", is_deleted: false},
      %Car.Version{car_id: ^car_id, name: "Toad", is_deleted: false}
    ] = Versioned.history(Car, car_id)

    # The record really does exist, but it's marked as deleted.
    %{is_deleted: true} = MyApp.Repo.get(Car, car_id)

    # The Versioned convenience function will obfuscate this fact.
    nil = Versioned.get(Car, car_id)
  end
end
```

Later, add a new column in a migration with this convenience macro which
appropriately adds the field to both tables.

```elixir
defmodule MyApp.Repo.Migrations.AddCarColor do
  use Versioned.Migration

  def change do
    add_versioned_column(:cars, :color, :string)
  end
end
```