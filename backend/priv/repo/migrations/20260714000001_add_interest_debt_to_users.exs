defmodule FoodStreet.Repo.Migrations.AddInterestDebtToUsers do
  @moduledoc """
  Nợ lãi riêng của user (issue #12) — tách khỏi `balance`.

  Lãi trên số dư âm cộng dồn vào đây (không trừ vào balance). Khi user nạp tiền,
  tiền trừ hết `interest_debt` trước, phần còn lại mới cộng vào `balance`.
  """
  use Ecto.Migration

  def change do
    # VND là số nguyên (không có hào) → numeric(12,0).
    alter table(:users) do
      add :interest_debt, :decimal, precision: 12, scale: 0, null: false, default: "0"
    end
  end
end
