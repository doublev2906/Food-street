defmodule FoodStreet.Ordering.Order do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Accounts.User
  alias FoodStreet.Ordering.OrderItem
  alias FoodStreet.Ordering.GroupOrder

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :user_id,
             :group_order_id,
             :order_date,
             :status,
             :total_amount,
             :note,
             :confirmed_at,
             :inserted_at,
             :items
           ]}

  @statuses ~w(pending confirmed cancelled)

  schema "orders" do
    field :order_date, :date
    field :status, :string, default: "pending"
    field :total_amount, :decimal, default: Decimal.new(0)
    field :note, :string
    field :confirmed_at, :utc_datetime

    belongs_to :user, User
    belongs_to :group_order, GroupOrder
    has_many :items, OrderItem, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:user_id, :group_order_id, :order_date, :status, :note, :total_amount])
    |> validate_required([:user_id, :order_date, :status])
    |> validate_inclusion(:status, @statuses)
    |> cast_assoc(:items, with: &OrderItem.changeset/2, required: true)
    |> unique_constraint([:group_order_id, :user_id], name: :orders_group_order_user_index)
  end

  def status_changeset(order, attrs) do
    order
    |> cast(attrs, [:status, :confirmed_at])
    |> validate_inclusion(:status, @statuses)
  end
end
