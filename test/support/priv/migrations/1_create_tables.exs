defmodule Versioned.Test.Repo.Migrations.CreateCar do
  use Versioned.Migration

  def change do
    create_versioned_table(:cars) do
      add(:name, :string)
    end

    create_versioned_table(:passenger_people, singular: :passenger_person) do
      add(:name, :string)
      add(:car_id, references(:cars, type: :uuid))
    end

    add_versioned_column(:cars, :color, :string)
  end
end
