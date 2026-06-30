defmodule FoodStreet.Repo.Migrations.AddUsernameToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :username, :string
    end

    # Backfill username từ phần trước @ của email cho dữ liệu cũ.
    execute "UPDATE users SET username = split_part(email, '@', 1) WHERE username IS NULL"

    create unique_index(:users, [:username])

    alter table(:users) do
      modify :username, :string, null: false
    end
  end

  def down do
    alter table(:users) do
      remove :username
    end
  end
end
