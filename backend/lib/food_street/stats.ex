defmodule FoodStreet.Stats do
  @moduledoc "Thống kê cho admin: đơn hàng, doanh thu, món phổ biến, quỹ."

  import Ecto.Query, warn: false
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User
  alias FoodStreet.Ordering.Order
  alias FoodStreet.Ordering.OrderItem

  @doc "Tổng quan dashboard cho 1 ngày (mặc định hôm nay)."
  def summary(date \\ Date.utc_today()) do
    %{
      date: date,
      total_users: Repo.aggregate(User, :count, :id),
      active_users: Repo.aggregate(from(u in User, where: u.active == true), :count, :id),
      fund_total: Repo.aggregate(User, :sum, :balance) || Decimal.new(0),
      orders_today: count_orders(date, date),
      pending_today: count_orders(date, date, "pending"),
      confirmed_today: count_orders(date, date, "confirmed"),
      revenue_today: revenue(date, date),
      top_items: top_items(date, date)
    }
  end

  @doc """
  Thống kê tổng hợp cho một khoảng ngày `[from_date, to_date]`.

  Dùng cho báo cáo theo ngày / tháng / năm — FE tự quy đổi lựa chọn thành
  khoảng ngày rồi gọi vào đây (ngày = [d, d], tháng = [đầu tháng, cuối tháng]…).
  """
  def period_summary(from_date, to_date) do
    %{
      from: from_date,
      to: to_date,
      orders: count_orders(from_date, to_date),
      pending: count_orders(from_date, to_date, "pending"),
      confirmed: count_orders(from_date, to_date, "confirmed"),
      revenue: revenue(from_date, to_date),
      top_items: top_items(from_date, to_date)
    }
  end

  # Đếm đơn trong khoảng [from, to], tuỳ chọn lọc theo trạng thái.
  defp count_orders(from_date, to_date, status \\ nil) do
    from(o in Order, where: o.order_date >= ^from_date and o.order_date <= ^to_date)
    |> maybe_status(status)
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_status(query, nil), do: query
  defp maybe_status(query, status), do: from(o in query, where: o.status == ^status)

  # Doanh thu (tổng tiền đã chốt) trong khoảng [from, to].
  defp revenue(from_date, to_date) do
    Repo.one(
      from o in Order,
        where:
          o.order_date >= ^from_date and o.order_date <= ^to_date and o.status == "confirmed",
        select: coalesce(sum(o.total_amount), 0)
    )
  end

  # Các món được đặt nhiều nhất trong khoảng [from, to] (mọi đơn không bị hủy).
  defp top_items(from_date, to_date, limit \\ 10) do
    from(oi in OrderItem,
      join: o in Order,
      on: o.id == oi.order_id,
      where:
        o.order_date >= ^from_date and o.order_date <= ^to_date and o.status != "cancelled",
      group_by: oi.item_name,
      order_by: [desc: sum(oi.quantity)],
      limit: ^limit,
      select: %{
        item_name: oi.item_name,
        quantity: sum(oi.quantity),
        revenue: sum(oi.subtotal)
      }
    )
    |> Repo.all()
  end

  @doc "Doanh thu theo từng ngày trong khoảng (để vẽ biểu đồ)."
  def revenue_by_day(from_date, to_date) do
    from(o in Order,
      where: o.order_date >= ^from_date and o.order_date <= ^to_date and o.status == "confirmed",
      group_by: o.order_date,
      order_by: [asc: o.order_date],
      select: %{date: o.order_date, revenue: sum(o.total_amount), orders: count(o.id)}
    )
    |> Repo.all()
  end
end
