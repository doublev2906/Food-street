defmodule FoodStreet.Fund do
  @moduledoc """
  Quản lý quỹ đồ ăn sáng.

  Mỗi user có 1 số dư (`users.balance`). Admin nạp tiền (`deposit`) hoặc điều
  chỉnh (`adjust`). Mỗi thay đổi số dư được ghi lại 1 dòng `fund_transactions`
  để soi lịch sử. Việc trừ tiền khi chốt đơn nằm ở `FoodStreet.Ordering`.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User
  alias FoodStreet.Fund.FundTransaction

  @doc "Lịch sử giao dịch quỹ của 1 user."
  def list_user_transactions(user_id) do
    FundTransaction
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc "Toàn bộ giao dịch quỹ (admin) — có phân trang."
  def list_transactions(page \\ 1, page_size \\ 20) do
    page = max(to_int(page, 1), 1)
    page_size = page_size |> to_int(20) |> min(100) |> max(1)
    total = Repo.aggregate(FundTransaction, :count, :id)

    entries =
      FundTransaction
      |> order_by([t], desc: t.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload([:user, :created_by])
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      page_size: page_size,
      total: total,
      total_pages: max(ceil(total / page_size), 1)
    }
  end

  defp to_int(v, _default) when is_integer(v), do: v

  defp to_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> default
    end
  end

  defp to_int(_, default), do: default

  @doc "Nạp tiền vào quỹ cho 1 user. `amount` > 0."
  def deposit(%User{} = user, amount, %User{} = admin, description \\ nil) do
    apply_delta(user, amount, "deposit", admin, description || "Nạp quỹ")
  end

  @doc """
  Điều chỉnh số dư: `amount` có thể âm hoặc dương. Dùng để sửa sai/hoàn tiền.
  """
  def adjust(%User{} = user, amount, %User{} = admin, description \\ nil) do
    apply_delta(user, amount, "adjustment", admin, description || "Điều chỉnh quỹ")
  end

  defp apply_delta(user, amount, type, admin, description) do
    with {:ok, decimal} <- to_decimal(amount) do
      new_balance = Decimal.add(user.balance, decimal)

      Multi.new()
      |> Multi.update(:user, User.balance_changeset(user, new_balance))
      |> Multi.insert(:tx, fn _ ->
        FundTransaction.changeset(%FundTransaction{}, %{
          user_id: user.id,
          amount: decimal,
          type: type,
          description: description,
          balance_after: new_balance,
          created_by_id: admin.id
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: updated, tx: tx}} -> {:ok, %{user: updated, transaction: tx}}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  @doc "Tổng số dư toàn quỹ (cộng balance của mọi user)."
  def total_balance do
    Repo.aggregate(User, :sum, :balance) || Decimal.new(0)
  end

  defp to_decimal(%Decimal{} = d), do: {:ok, d}
  defp to_decimal(n) when is_integer(n) or is_float(n), do: {:ok, Decimal.new(to_string(n))}

  defp to_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, ""} -> {:ok, d}
      _ -> {:error, :invalid_amount}
    end
  end

  defp to_decimal(_), do: {:error, :invalid_amount}
end
