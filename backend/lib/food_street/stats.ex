defmodule FoodStreet.Stats do
  @moduledoc "Thống kê cho admin: đơn hàng, doanh thu, món phổ biến, quỹ."

  import Ecto.Query, warn: false
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User
  alias FoodStreet.Ordering.Order
  alias FoodStreet.Ordering.OrderItem
  alias FoodStreet.Fund.FundTransaction

  @vn_offset_seconds 7 * 3600

  @doc "Tổng quan dashboard cho 1 ngày (mặc định hôm nay)."
  def summary(date \\ Date.utc_today()) do
    flow = fund_flow(date, date)
    neg = negative_balances()

    %{
      date: date,
      total_users: Repo.aggregate(User, :count, :id),
      active_users: Repo.aggregate(from(u in User, where: u.active == true), :count, :id),
      fund_total: Repo.aggregate(User, :sum, :balance) || Decimal.new(0),
      fund_deposited: flow.deposited,
      fund_spent: flow.spent,
      fund_adjusted: flow.adjusted,
      negative_count: neg.count,
      negative_debt: neg.debt,
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
    flow = fund_flow(from_date, to_date)
    neg = negative_balances()

    %{
      from: from_date,
      to: to_date,
      orders: count_orders(from_date, to_date),
      pending: count_orders(from_date, to_date, "pending"),
      confirmed: count_orders(from_date, to_date, "confirmed"),
      revenue: revenue(from_date, to_date),
      fund_total: fund_total_until(to_date),
      fund_deposited: flow.deposited,
      fund_spent: flow.spent,
      fund_adjusted: flow.adjusted,
      negative_count: neg.count,
      negative_debt: neg.debt,
      top_items: top_items(from_date, to_date)
    }
  end

  # Dòng tiền quỹ trong khoảng [from, to] (theo giờ VN):
  #   deposited = tổng khoản nạp (type "deposit")
  #   spent     = tổng khoản trừ (type "order" + "split"), trả về số dương
  # Lọc theo `inserted_at` — mốc thời gian thật của giao dịch, quy về ranh giới VN.
  defp fund_flow(from_date, to_date) do
    {start_utc, end_utc} = vn_day_bounds(from_date, to_date)

    deposited =
      Repo.one(
        from t in FundTransaction,
          where:
            t.type == "deposit" and t.inserted_at >= ^start_utc and t.inserted_at < ^end_utc,
          select: coalesce(sum(t.amount), 0)
      )

    spent =
      Repo.one(
        from t in FundTransaction,
          where:
            t.type in ["order", "split"] and t.inserted_at >= ^start_utc and
              t.inserted_at < ^end_utc,
          select: coalesce(sum(t.amount), 0)
      )

    # Điều chỉnh có dấu (±): giữ nguyên dấu để `nạp - chi + điều_chỉnh` cân bằng.
    adjusted =
      Repo.one(
        from t in FundTransaction,
          where:
            t.type == "adjustment" and t.inserted_at >= ^start_utc and t.inserted_at < ^end_utc,
          select: coalesce(sum(t.amount), 0)
      )

    %{
      deposited: as_decimal(deposited),
      spent: spent |> as_decimal() |> Decimal.abs(),
      adjusted: as_decimal(adjusted)
    }
  end

  # Tổng quỹ LŨY KẾ đến hết ngày `to_date` (giờ VN): cộng mọi giao dịch có
  # `inserted_at` trước 00:00 của (to_date + 1). Tái dựng số dư quỹ tại thời điểm
  # cuối kỳ từ lịch sử giao dịch (giả định số dư chỉ đổi qua giao dịch).
  defp fund_total_until(to_date) do
    {_start, end_utc} = vn_day_bounds(to_date, to_date)

    Repo.one(
      from t in FundTransaction,
        where: t.inserted_at < ^end_utc,
        select: coalesce(sum(t.amount), 0)
    )
    |> as_decimal()
  end

  # Số người và tổng số tiền đang âm quỹ (trả về nợ dưới dạng số dương).
  defp negative_balances do
    debtors = from(u in User, where: u.balance < 0)

    debt =
      Repo.one(from u in User, where: u.balance < 0, select: coalesce(sum(u.balance), 0))

    %{count: Repo.aggregate(debtors, :count, :id), debt: debt |> as_decimal() |> Decimal.abs()}
  end

  # Ranh giới UTC cho các ngày VN [from, to] (bao gồm cả 2 đầu): ngày VN X bắt đầu
  # lúc X 00:00 (UTC+7) = X 00:00 UTC trừ 7 giờ. Cận trên là 00:00 của (to + 1).
  defp vn_day_bounds(from_date, to_date) do
    start_utc =
      from_date
      |> NaiveDateTime.new!(~T[00:00:00])
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(-@vn_offset_seconds, :second)

    end_utc =
      to_date
      |> Date.add(1)
      |> NaiveDateTime.new!(~T[00:00:00])
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(-@vn_offset_seconds, :second)

    {start_utc, end_utc}
  end

  defp as_decimal(%Decimal{} = d), do: d
  defp as_decimal(n), do: Decimal.new(n)

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
