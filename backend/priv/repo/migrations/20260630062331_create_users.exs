defmodule FoodStreet.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :role, :string, null: false, default: "user"
      add :balance, :decimal, null: false, default: 0, precision: 12, scale: 2
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create index(:users, [:role])
  end
end
