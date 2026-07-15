defmodule FoodStreet.Repo.Migrations.CreateInterestCharges do
  @moduledoc """
  Sổ cái quỹ lãi: mỗi lần tính lãi trên số dư âm của 1 user ghi 1 dòng ở đây.

  Đây là "quỹ riêng" tách khỏi balance của user (xem issue #12). Lãi KHÔNG trừ vào
  balance mà cộng vào `users.interest_debt` (khoản nợ lãi riêng). Tổng quỹ lãi đã
  cộng dồn = tổng `amount` của bảng này.

  `charged_on` là ngày (giờ VN) áp lãi; unique (user_id, charged_on) chống tính
  trùng lãi cho cùng 1 user trong cùng 1 ngày (idempotent khi job chạy lại).
  """
  use Ecto.Migration

  def change do
    create table(:interest_charges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Tiền lãi cộng vào quỹ trong ngày (dương, đơn vị đồng, số nguyên, đã làm tròn LÊN).
      # VND không có hào → dùng numeric(12,0) (số nguyên).
      add :amount, :decimal, null: false, precision: 12, scale: 0

      # Gốc tính lãi = |số dư âm| + nợ lãi trước đó (lãi kép) — để đối soát.
      add :base_amount, :decimal, null: false, precision: 12, scale: 0
      # Tổng nợ lãi của user sau khi cộng lãi ngày này.
      add :interest_debt_after, :decimal, null: false, precision: 12, scale: 0
      add :charged_on, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:interest_charges, [:user_id])
    create index(:interest_charges, [:charged_on])
    create unique_index(:interest_charges, [:user_id, :charged_on])
  end
end
