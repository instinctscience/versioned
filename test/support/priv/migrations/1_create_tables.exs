defmodule Versioned.Test.Repo.Migrations.CreateCar do
  use Versioned.Migration

  def change do
    create table(:garages) do
      add(:name, :string)
    end

    create_versioned_table(:cars) do
      add(:name, :string)
    end

    add_versioned_column(:cars, :garage_id, references(:garages))

    create_versioned_table(:people, singular: :person) do
      add(:name, :string)
      add(:car_id, references(:cars, type: :uuid))
    end

    add_versioned_column(:cars, :color, :string)

    create_versioned_table(:hobbies, singular: :hobby) do
      add(:name, :string)
      add(:person_id, references(:people, type: :uuid))
    end
  end
end
