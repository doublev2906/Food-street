defmodule FoodStreet.Interest.InterestCharge do
  @moduledoc """
  Một lần tính lãi trên số dư âm của 1 user (sổ cái quỹ lãi — xem `FoodStreet.Interest`).

  `amount` là tiền lãi (dương) cộng vào quỹ trong ngày `charged_on`. `base_amount`
  là gốc tính lãi (`|số dư âm| + nợ lãi trước đó`, do lãi kép). `interest_debt_after`
  là tổng nợ lãi của user sau khi cộng lãi ngày này. Lãi KHÔNG trừ vào `balance`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :user_id,
             :amount,
             :base_amount,
             :interest_debt_after,
             :charged_on,
             :inserted_at
           ]}

  schema "interest_charges" do
    field :amount, :decimal
    field :base_amount, :decimal
    field :interest_debt_after, :decimal
    field :charged_on, :date

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(charge, attrs) do
    charge
    |> cast(attrs, [:user_id, :amount, :base_amount, :interest_debt_after, :charged_on])
    |> validate_required([:user_id, :amount, :base_amount, :interest_debt_after, :charged_on])
    |> unique_constraint([:user_id, :charged_on])
  end
end
