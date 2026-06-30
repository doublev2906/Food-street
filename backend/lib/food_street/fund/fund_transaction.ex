defmodule FoodStreet.Fund.FundTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Accounts.User
  alias FoodStreet.Ordering.Order

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :user_id,
             :amount,
             :type,
             :description,
             :balance_after,
             :order_id,
             :created_by_id,
             :inserted_at
           ]}

  @types ~w(deposit order adjustment)

  schema "fund_transactions" do
    field :amount, :decimal
    field :type, :string
    field :description, :string
    field :balance_after, :decimal

    belongs_to :user, User
    belongs_to :order, Order
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(tx, attrs) do
    tx
    |> cast(attrs, [
      :user_id,
      :amount,
      :type,
      :description,
      :balance_after,
      :order_id,
      :created_by_id
    ])
    |> validate_required([:user_id, :amount, :type, :balance_after])
    |> validate_inclusion(:type, @types)
  end
end
