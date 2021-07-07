defmodule Versioned.Test.Repo.Migrations.CreateCar do
  use Versioned.Migration

  def change do
    create_versioned_table(:cars) do
      add(:name, :string)
    end

    create_versioned_table(:people, singular: :person) do
      add(:name, :string)
      add(:car_id, references(:cars, type: :uuid, versioned: true))
    end

    add_versioned_column(:cars, :color, :string)

    create_versioned_table(:hobbies, singular: :hobby) do
      add(:name, :string)
      add(:person_id, references(:people, type: :uuid, versioned: true))
    end
  end
end
