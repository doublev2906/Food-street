defmodule FoodStreet.Fund.ExternalPurchase do
  @moduledoc """
  Khoản mua đồ ăn ngoài menu do admin ứng, chia tiền cho những người cùng ăn.

  Mỗi người ăn tương ứng 1 dòng `FoodStreet.Fund.FundTransaction` type "split"
  (trừ số dư người đó), liên kết về khoản mua này qua `external_purchase_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Accounts.User
  alias FoodStreet.Fund.FundTransaction

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :description,
             :total_amount,
             :purchase_date,
             :created_by_id,
             :inserted_at
           ]}

  schema "external_purchases" do
    field :description, :string
    field :total_amount, :decimal
    field :purchase_date, :date

    belongs_to :created_by, User
    has_many :transactions, FundTransaction

    timestamps(type: :utc_datetime)
  end

  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [:description, :total_amount, :purchase_date, :created_by_id])
    |> validate_required([:description, :total_amount, :purchase_date])
    |> validate_number(:total_amount, greater_than: 0)
  end
end
