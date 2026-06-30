defmodule FoodStreet.Repo.Migrations.AddNoteToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :note, :string
    end
  end
end
