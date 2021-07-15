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
used to retrieve a list of entity versions, newest first.

## Installation

```elixir
def deps do
  [
    {:versioned,
      git: "https://github.com/instinctscience/versioned.git",
      branch: "main"}
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

## Managing Groups of Records Together

Also of note is the library's ability to properly manage version records when
inserting, updating or deleting groups of records via `has_many` relationships
with `Ecto.Changeset.cast_assoc/3`. Note that creating or updating a single
child record in the params for a `belongs_to` connection is not currently
supported. In fact, there are probably other potentially useful features and
pieces which have not yet been explored.

## Extras

### Migration Helper: Add Column on a Versioned Table

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

### Absinthe Helper: Create a Version Object

While versioned does not depend on Absinthe, it does provide a shortcut for
creating an absinthe "version" object, wrapping one of your entities. In the
following example, `:car_version` would have the following fields:

* `:id` - primary key of the version record
* `:is_deleted` - boolean indicating if the record was deleted as of this version
* `:inserted_at` - UTC timestamp, indicating when the version was created
* `:car` - The car as it was in this version

```elixir
defmodule MyApp.Schema.Types.User do
  use Absinthe.Schema.Notation
  import Versioned.Absinthe

  object :car do
    field :id, :id
    field :name, :string
  end

  version_object :car_version, :car
end
```
