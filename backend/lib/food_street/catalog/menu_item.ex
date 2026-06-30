defmodule FoodStreet.Catalog.MenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :name, :description, :price, :available, :inserted_at]}

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :available, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(menu_item, attrs) do
    menu_item
    |> cast(attrs, [:name, :description, :price, :available])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end
