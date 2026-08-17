defmodule FoodStreet.Catalog.MenuItemSize do
  @moduledoc "Một size (biến thể) của món ăn, mỗi size có giá riêng."
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Catalog.MenuItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :name, :price, :sort_order]}

  schema "menu_item_sizes" do
    field :name, :string
    field :price, :decimal
    field :sort_order, :integer, default: 0

    belongs_to :menu_item, MenuItem

    timestamps(type: :utc_datetime)
  end

  def changeset(size, attrs) do
    size
    |> cast(attrs, [:menu_item_id, :name, :price, :sort_order])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end
