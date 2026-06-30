defmodule FoodStreet.Catalog.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Catalog.MenuItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :name, :description, :active, :inserted_at]}

  schema "categories" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true

    has_many :menu_items, MenuItem

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :active])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
