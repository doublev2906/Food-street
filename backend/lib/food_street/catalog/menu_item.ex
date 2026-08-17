defmodule FoodStreet.Catalog.MenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Catalog.{Category, MenuItemSize}

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
             :sizes,
             :inserted_at
           ]}

  schema "menu_items" do
    field :name, :string
    field :description, :string
    field :price, :decimal
    field :available, :boolean, default: true
    field :image_url, :string

    belongs_to :category, Category

    # `on_replace: :delete`: admin gửi lại toàn bộ mảng sizes → size bị bỏ sẽ xóa.
    has_many :sizes, MenuItemSize, on_replace: :delete, preload_order: [asc: :sort_order]

    timestamps(type: :utc_datetime)
  end

  def changeset(menu_item, attrs) do
    menu_item
    |> cast(attrs, [:name, :description, :price, :available, :image_url, :category_id])
    |> validate_required([:name, :price])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> cast_assoc(:sizes, with: &MenuItemSize.changeset/2)
    |> foreign_key_constraint(:category_id)
  end
end
