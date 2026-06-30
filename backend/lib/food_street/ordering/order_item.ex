defmodule FoodStreet.Ordering.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Ordering.Order
  alias FoodStreet.Catalog.MenuItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [:id, :menu_item_id, :item_name, :quantity, :unit_price, :subtotal, :note]}

  schema "order_items" do
    field :item_name, :string
    field :quantity, :integer, default: 1
    field :unit_price, :decimal
    field :subtotal, :decimal
    field :note, :string

    belongs_to :order, Order
    belongs_to :menu_item, MenuItem

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:menu_item_id, :item_name, :quantity, :unit_price, :subtotal, :note])
    |> validate_required([:menu_item_id, :item_name, :quantity, :unit_price])
    |> validate_number(:quantity, greater_than: 0)
    |> put_subtotal()
  end

  defp put_subtotal(changeset) do
    quantity = get_field(changeset, :quantity)
    unit_price = get_field(changeset, :unit_price)

    if is_integer(quantity) and match?(%Decimal{}, unit_price) do
      put_change(changeset, :subtotal, Decimal.mult(unit_price, quantity))
    else
      changeset
    end
  end
end
