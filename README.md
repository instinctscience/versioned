# Versioned

Versioned is a tool for enhancing `Ecto.Schema` modules to keep a full
history of changes.

The underlying method is to create a corresponding "versions" table for each
schema (with all the same columns) where each record indicates a create,
update, or delete event. When a record is deleted, the versions table entry
has the record in its final state, and the special `is_deleted` field will be
set to true.

Records in the main table are mutable and operated on as normal, including
deletes where the record is truly deleted.

Versioned provides helpers for migrations and schemas. The `Versioned` module
has `insert/2`, `update/2` and `delete/2` which should be used in place of
your application's `Repo` for versioned tables. Finally, `history/3` can be
used to retrieve a list of entity versions.

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
    # Creates 2 tables:
    # - "cars" with columns id, name, inserted_at and updated_at
    # - "cars_versions" with columns id, name, car_id and inserted_at
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

    {:ok, _car} = Versioned.delete(car)

    # The record is deleted.
    nil = MyApp.Repo.get(Car, car_id)

    # `Versioned.history/2` still returns all changes, newest first.
    [
      %Car.Version{car_id: ^car_id, name: "Magnificent", is_deleted: true},
      %Car.Version{car_id: ^car_id, name: "Magnificent", is_deleted: false},
      %Car.Version{car_id: ^car_id, name: "Toad", is_deleted: false}
    ] = Versioned.history(Car, car_id)
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