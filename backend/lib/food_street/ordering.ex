defmodule FoodStreet.Ordering do
  @moduledoc """
  Đặt đồ ăn và chốt đơn.

  Quy trình: user tạo/sửa đơn (status `pending`) trong ngày. Admin "chốt đơn"
  (`confirm`) -> trừ tiền từ số dư quỹ của user, ghi `fund_transactions`, đổi
  trạng thái đơn sang `confirmed`. Toàn bộ chốt đơn chạy trong transaction.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User
  alias FoodStreet.Catalog.MenuItem
  alias FoodStreet.Ordering.Order
  alias FoodStreet.Fund.FundTransaction

  @doc "Danh sách đơn của 1 user (mới nhất trước)."
  def list_user_orders(user_id) do
    Order
    |> where([o], o.user_id == ^user_id)
    |> order_by([o], desc: o.order_date, desc: o.inserted_at)
    |> preload(:items)
    |> Repo.all()
  end

  @doc "Danh sách đơn cho admin, lọc theo `:date` và `:status` (tùy chọn)."
  def list_orders(filters \\ %{}) do
    Order
    |> filter_by_date(filters[:date] || filters["date"])
    |> filter_by_status(filters[:status] || filters["status"])
    |> order_by([o], desc: o.order_date, desc: o.inserted_at)
    |> preload([:items, :user])
    |> Repo.all()
  end

  defp filter_by_date(query, nil), do: query
  defp filter_by_date(query, ""), do: query

  defp filter_by_date(query, %Date{} = date),
    do: where(query, [o], o.order_date == ^date)

  defp filter_by_date(query, date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> where(query, [o], o.order_date == ^d)
      _ -> query
    end
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, ""), do: query
  defp filter_by_status(query, status), do: where(query, [o], o.status == ^status)

  def get_order!(id), do: Repo.get!(Order, id) |> Repo.preload([:items, :user])

  def get_order(id) do
    case Repo.get(Order, id) do
      nil -> nil
      order -> Repo.preload(order, [:items, :user])
    end
  end

  @doc """
  Tạo hoặc cập nhật đơn `pending` của user cho 1 ngày.

  `attrs` ví dụ:

      %{"order_date" => "2026-06-30", "note" => "ít cay",
        "items" => [%{"menu_item_id" => id, "quantity" => 2}]}

  Nếu user đã có đơn `pending` trong ngày đó thì đơn cũ được thay thế.
  """
  def place_order(%User{} = user, attrs) do
    order_date = parse_date(attrs["order_date"] || attrs[:order_date])
    raw_items = attrs["items"] || attrs[:items] || []
    note = attrs["note"] || attrs[:note]

    with {:ok, date} <- order_date,
         {:ok, items} <- build_items(raw_items) do
      total = Enum.reduce(items, Decimal.new(0), &Decimal.add(&2, &1.subtotal))

      existing = pending_order_for(user.id, date)
      base = existing || %Order{}

      changeset =
        Order.changeset(base, %{
          "user_id" => user.id,
          "order_date" => date,
          "status" => "pending",
          "note" => note,
          "total_amount" => total,
          "items" => items
        })

      case Repo.insert_or_update(changeset) do
        {:ok, order} -> {:ok, Repo.preload(order, :items, force: true)}
        error -> error
      end
    else
      {:error, _} = err -> err
    end
  end

  defp pending_order_for(user_id, date) do
    Order
    |> where([o], o.user_id == ^user_id and o.order_date == ^date and o.status == "pending")
    |> preload(:items)
    |> Repo.one()
  end

  # Lấy snapshot tên + giá từ menu_items theo từng dòng đặt.
  defp build_items([]), do: {:error, :empty_items}

  defp build_items(raw_items) do
    results =
      Enum.map(raw_items, fn item ->
        menu_item_id = item["menu_item_id"] || item[:menu_item_id]
        quantity = to_int(item["quantity"] || item[:quantity] || 1)

        case Repo.get(MenuItem, menu_item_id) do
          %MenuItem{available: true} = mi when quantity > 0 ->
            %{
              menu_item_id: mi.id,
              item_name: mi.name,
              quantity: quantity,
              unit_price: mi.price,
              subtotal: Decimal.mult(mi.price, quantity)
            }

          _ ->
            :invalid
        end
      end)

    if Enum.any?(results, &(&1 == :invalid)) do
      {:error, :invalid_items}
    else
      {:ok, results}
    end
  end

  def cancel_order(%Order{status: "pending"} = order) do
    order
    |> Order.status_changeset(%{status: "cancelled"})
    |> Repo.update()
  end

  def cancel_order(%Order{}), do: {:error, :not_pending}

  @doc "Chốt 1 đơn: trừ quỹ + ghi giao dịch + đổi trạng thái. Atomic."
  def confirm_order(%Order{} = order, %User{} = admin) do
    order = Repo.preload(order, :user)

    cond do
      order.status != "pending" ->
        {:error, :not_pending}

      true ->
        do_confirm(order, admin)
    end
  end

  defp do_confirm(order, admin) do
    user = order.user
    new_balance = Decimal.sub(user.balance, order.total_amount)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:user, User.balance_changeset(user, new_balance))
    |> Multi.update(:order, Order.status_changeset(order, %{status: "confirmed", confirmed_at: now}))
    |> Multi.insert(:tx, fn _ ->
      FundTransaction.changeset(%FundTransaction{}, %{
        user_id: user.id,
        amount: Decimal.negate(order.total_amount),
        type: "order",
        description: "Chốt đơn ngày #{order.order_date}",
        balance_after: new_balance,
        order_id: order.id,
        created_by_id: admin.id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: confirmed}} -> {:ok, Repo.preload(confirmed, [:items, :user], force: true)}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc "Chốt tất cả đơn `pending` của 1 ngày. Trả về {:ok, %{confirmed: n}}."
  def confirm_orders_for_date(%Date{} = date, %User{} = admin) do
    orders =
      Order
      |> where([o], o.order_date == ^date and o.status == "pending")
      |> preload(:user)
      |> Repo.all()

    results = Enum.map(orders, &do_confirm(&1, admin))
    confirmed = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    {:ok, %{confirmed: confirmed, failed: failed, total: length(orders)}}
  end

  defp parse_date(%Date{} = d), do: {:ok, d}

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_date(_), do: {:error, :invalid_date}

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp to_int(_), do: 0
end
