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
      orders_today: count_orders(date),
      pending_today: count_orders(date, "pending"),
      confirmed_today: count_orders(date, "confirmed"),
      revenue_today: revenue(date),
      top_items: top_items(date)
    }
  end

  defp count_orders(date) do
    Repo.aggregate(from(o in Order, where: o.order_date == ^date), :count, :id)
  end

  defp count_orders(date, status) do
    Repo.aggregate(
      from(o in Order, where: o.order_date == ^date and o.status == ^status),
      :count,
      :id
    )
  end

  @doc "Doanh thu (tổng tiền đã chốt) của 1 ngày."
  def revenue(date) do
    Repo.one(
      from o in Order,
        where: o.order_date == ^date and o.status == "confirmed",
        select: coalesce(sum(o.total_amount), 0)
    )
  end

  @doc "Các món được đặt nhiều nhất trong ngày (mọi đơn không bị hủy)."
  def top_items(date, limit \\ 10) do
    from(oi in OrderItem,
      join: o in Order,
      on: o.id == oi.order_id,
      where: o.order_date == ^date and o.status != "cancelled",
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
