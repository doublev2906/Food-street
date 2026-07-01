defmodule FoodStreet.Catalog.MenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Catalog.Category

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :description,
             :price,
             :available,
             :image_url,
             :category_id,
             :inserted_at
           ]}

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :available, :boolean, default: true
    field :image_url, :string

    belongs_to :category, Category

    timestamps(type: :utc_datetime)
  end

  def changeset(menu_item, attrs) do
    menu_item
    |> cast(attrs, [:name, :description, :price, :available, :image_url, :category_id])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:category_id)
  end
end
