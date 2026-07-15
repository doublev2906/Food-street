defmodule FoodStreet.Ordering do
  @moduledoc """
  Đặt đồ ăn theo **đợt đặt nhóm** (group order) và chốt đơn.

  Quy trình:
  1. Admin tạo 1 đợt đặt nhóm (`GroupOrder`) gắn với 1 danh mục + ngày, status `open`.
  2. User đặt đơn của mình vào đợt đó (chỉ chọn món thuộc danh mục của đợt).
     Mỗi user 1 đơn / đợt; sửa lại sẽ thay thế đơn cũ. Chỉ khi đợt còn `open`.
  3. Admin **chốt đợt** (`close_group_order`) -> trừ quỹ từng user, ghi
     `fund_transactions`, đổi đơn sang `confirmed`, đóng đợt. Toàn bộ atomic.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User
  alias FoodStreet.Catalog.MenuItem
  alias FoodStreet.Ordering.Order
  alias FoodStreet.Ordering.GroupOrder
  alias FoodStreet.Fund.FundTransaction

  # ===================== Group orders =====================

  @doc "Các đợt đặt đang mở (cho user)."
  def list_open_group_orders do
    GroupOrder
    |> where([g], g.status == "open")
    |> order_by([g], desc: g.order_date, desc: g.inserted_at)
    |> preload(:category)
    |> Repo.all()
  end

  @doc "Tất cả đợt đặt (admin), lọc theo `:status` tùy chọn."
  def list_group_orders(filters \\ %{}) do
    GroupOrder
    |> maybe_filter_status(filters[:status] || filters["status"])
    |> order_by([g], desc: g.order_date, desc: g.inserted_at)
    |> preload([:category, orders: [:items, :user]])
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [g], g.status == ^status)

  def get_group_order(id) do
    case Repo.get(GroupOrder, id) do
      nil -> nil
      go -> Repo.preload(go, [:category, orders: [:items, :user]])
    end
  end

  def create_group_order(attrs, %User{} = admin) do
    attrs = Map.put(string_keys(attrs), "created_by_id", admin.id)

    %GroupOrder{}
    |> GroupOrder.changeset(attrs)
    |> Repo.insert()
    |> preload_group()
  end

  def update_group_order(%GroupOrder{} = go, attrs) do
    go
    |> GroupOrder.changeset(string_keys(attrs))
    |> Repo.update()
    |> preload_group()
  end

  def delete_group_order(%GroupOrder{} = go), do: Repo.delete(go)

  defp preload_group({:ok, go}),
    do: {:ok, Repo.preload(go, [:category, orders: [:items, :user]], force: true)}

  defp preload_group(error), do: error

  @doc """
  Chốt cả đợt: trừ quỹ mọi đơn `pending` trong đợt, ghi giao dịch, đóng đợt.
  Atomic — lỗi 1 đơn thì rollback toàn bộ.
  """
  def close_group_order(%GroupOrder{} = go, %User{} = admin) do
    cond do
      go.status == "closed" ->
        {:error, :already_closed}

      go.status == "cancelled" ->
        {:error, :cancelled}

      true ->
        do_close_group(go, admin)
    end
  end

  defp do_close_group(go, admin) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    orders =
      Order
      |> where([o], o.group_order_id == ^go.id and o.status == "pending")
      |> preload(:user)
      |> Repo.all()

    multi =
      Enum.reduce(orders, Multi.new(), fn order, m ->
        user = order.user
        new_balance = Decimal.sub(user.balance, order.total_amount)

        m
        |> Multi.update({:user, order.id}, User.balance_changeset(user, new_balance))
        |> Multi.update(
          {:order, order.id},
          Order.status_changeset(order, %{status: "confirmed", confirmed_at: now})
        )
        |> Multi.insert(
          {:tx, order.id},
          FundTransaction.changeset(%FundTransaction{}, %{
            user_id: user.id,
            amount: Decimal.negate(order.total_amount),
            type: "order",
            description: "Chốt đợt: #{go.title} (#{go.order_date})",
            balance_after: new_balance,
            order_id: order.id,
            created_by_id: admin.id
          })
        )
      end)

    multi
    |> Multi.update(:group, GroupOrder.status_changeset(go, %{status: "closed", closed_at: now}))
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, %{confirmed: length(orders), group: get_group_order(go.id)}}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Bốc ngẫu nhiên `count` người đi lấy đồ từ những người đã đặt (đơn chưa huỷ)
  trong đợt. Trả danh sách `%User{}` (nhiều nhất `count`, hoặc toàn bộ người đặt
  nếu `count` lớn hơn). Trả `[]` khi `count <= 0` hoặc chưa ai đặt.
  """
  def pick_runners(%GroupOrder{} = go, count) when is_integer(count) and count > 0 do
    Enum.take_random(orderers(go), count)
  end

  def pick_runners(%GroupOrder{}, _count), do: []

  # Danh sách user (distinct) đã đặt đơn chưa huỷ trong đợt.
  defp orderers(%GroupOrder{} = go) do
    Order
    |> where([o], o.group_order_id == ^go.id and o.status != "cancelled")
    |> preload(:user)
    |> Repo.all()
    |> Enum.map(& &1.user)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  @doc """
  Gộp đơn của 1 đợt thành text gửi nhà bán — tái hiện đúng phần `copy` của
  `buildOrderExport` ở frontend (AdminDashboard.tsx): chỉ phần món + ghi chú chung,
  KHÔNG tiêu đề, KHÔNG dòng tổng.

  - Bỏ đơn `cancelled`.
  - Gom dòng theo tên món (giữ thứ tự món xuất hiện lần đầu); mỗi lượt đặt (kèm ghi
    chú riêng) là 1 dòng `"{số-lượng} {tên-món}{ ghi-chú}"`.
  - Nếu có đơn kèm ghi chú chung -> thêm khối "Ghi chú chung:" + `- {tên}: {ghi-chú}`.

  Trả `{:ok, text}` hoặc `{:error, :no_orders}` khi đợt chưa có đơn hợp lệ.
  `go` cần preload `orders: [:items, :user]` (tự preload nếu chưa).
  """
  def aggregate_seller_text(%GroupOrder{} = go) do
    go = Repo.preload(go, orders: [:items, :user])
    orders = Enum.reject(go.orders || [], &(&1.status == "cancelled"))

    if orders == [] do
      {:error, :no_orders}
    else
      {:ok, build_seller_text(orders)}
    end
  end

  defp build_seller_text(orders) do
    {names, rows} =
      for order <- orders, item <- order.items, reduce: {[], %{}} do
        {names, rows} ->
          name = item.item_name
          names = if Map.has_key?(rows, name), do: names, else: [name | names]
          rows = Map.update(rows, name, [item_line(item)], &(&1 ++ [item_line(item)]))
          {names, rows}
      end

    item_lines = names |> Enum.reverse() |> Enum.flat_map(&Map.fetch!(rows, &1))

    (item_lines ++ general_note_lines(orders))
    |> Enum.join("\n")
  end

  defp item_line(item) do
    base = "#{item.quantity} #{item.item_name}"

    case item.note && String.trim(item.note) do
      note when is_binary(note) and note != "" -> base <> " " <> note
      _ -> base
    end
  end

  defp general_note_lines(orders) do
    general = Enum.filter(orders, fn o -> o.note && String.trim(o.note) != "" end)

    if general == [] do
      []
    else
      ["", "Ghi chú chung:"] ++
        Enum.map(general, fn o ->
          "- #{(o.user && o.user.name) || "?"}: #{String.trim(o.note)}"
        end)
    end
  end

  # ===================== User orders =====================

  @doc "Danh sách đơn của 1 user (mới nhất trước)."
  def list_user_orders(user_id) do
    Order
    |> where([o], o.user_id == ^user_id)
    |> order_by([o], desc: o.order_date, desc: o.inserted_at)
    |> preload([:items, group_order: :category])
    |> Repo.all()
  end

  @doc """
  Đơn ĐANG HOẠT ĐỘNG của user trong đợt (pending/confirmed) — dùng để hiển thị
  "đơn của tôi". Bỏ qua đơn đã huỷ để user đặt lại được như đơn mới.
  """
  def get_user_order_in_group(user_id, group_order_id) do
    Order
    |> where(
      [o],
      o.user_id == ^user_id and o.group_order_id == ^group_order_id and o.status != "cancelled"
    )
    |> preload(:items)
    |> Repo.one()
  end

  # Bản ghi đơn của user trong đợt BẤT KỂ trạng thái. Cần cho upsert vì
  # unique index (group_order_id, user_id) chỉ cho 1 dòng — kể cả đã huỷ — nên
  # đặt lại phải tái dùng chính dòng đó thay vì insert mới (sẽ vi phạm ràng buộc).
  defp get_reusable_order_in_group(user_id, group_order_id) do
    Order
    |> where([o], o.user_id == ^user_id and o.group_order_id == ^group_order_id)
    |> preload(:items)
    |> Repo.one()
  end

  @doc "Danh sách đơn cho admin, lọc theo `:date` và `:status`."
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

  def get_order(id) do
    case Repo.get(Order, id) do
      nil -> nil
      order -> Repo.preload(order, [:items, :user])
    end
  end

  @doc """
  Đặt/cập nhật đơn của user vào 1 đợt đặt nhóm.

  `attrs`: %{"items" => [%{"menu_item_id" => id, "quantity" => n}], "note" => ...}
  Chỉ cho phép khi đợt `open` và các món thuộc đúng danh mục của đợt.
  """
  def place_order_in_group(%User{} = user, group_order_id, attrs) do
    note = attrs["note"] || attrs[:note]
    raw_items = attrs["items"] || attrs[:items] || []

    with %GroupOrder{} = go <- Repo.get(GroupOrder, group_order_id),
         :ok <- ensure_open(go),
         existing = get_reusable_order_in_group(user.id, go.id),
         :ok <- ensure_reorderable(existing),
         {:ok, items} <- build_items(raw_items, go.category_id) do
      total = Enum.reduce(items, Decimal.new(0), &Decimal.add(&2, &1.subtotal))
      base = existing || %Order{}

      changeset =
        Order.changeset(base, %{
          "user_id" => user.id,
          "group_order_id" => go.id,
          "order_date" => go.order_date,
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
      nil -> {:error, :group_not_found}
      {:error, _} = err -> err
    end
  end

  defp ensure_open(%GroupOrder{status: "open"}), do: :ok
  defp ensure_open(%GroupOrder{}), do: {:error, :group_not_open}

  # Chỉ sửa được đơn chưa chốt. `nil` = chưa có đơn (đang tạo mới) nên hợp lệ.
  defp ensure_editable(nil), do: :ok
  defp ensure_editable(%Order{status: "pending"}), do: :ok
  defp ensure_editable(%Order{}), do: {:error, :order_not_editable}

  # Đặt lại: cho phép khi chưa có đơn, đơn còn pending (sửa), hoặc đơn đã huỷ
  # (tái kích hoạt chính dòng đó về pending). Đơn đã chốt thì không đụng được.
  defp ensure_reorderable(nil), do: :ok
  defp ensure_reorderable(%Order{status: status}) when status in ["pending", "cancelled"], do: :ok
  defp ensure_reorderable(%Order{}), do: {:error, :order_not_editable}

  @doc """
  Admin sửa 1 đơn bất kỳ khi đơn chưa chốt và đợt còn mở.

  `attrs`: %{"items" => [...], "note" => ...} (như đặt đơn của user).
  """
  def update_order(%Order{} = order, attrs) do
    order = Repo.preload(order, [:group_order, :items])
    raw_items = attrs["items"] || attrs[:items] || []
    note = attrs["note"] || attrs[:note]

    with :ok <- ensure_editable(order),
         :ok <- ensure_open(order.group_order),
         {:ok, items} <- build_items(raw_items, order.group_order.category_id) do
      total = Enum.reduce(items, Decimal.new(0), &Decimal.add(&2, &1.subtotal))

      order
      |> Order.changeset(%{"note" => note, "total_amount" => total, "items" => items})
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, Repo.preload(updated, [:items, :user], force: true)}
        error -> error
      end
    end
  end

  # Snapshot tên + giá; chỉ nhận món còn bán và đúng danh mục của đợt.
  defp build_items([], _category_id), do: {:error, :empty_items}

  defp build_items(raw_items, category_id) do
    results =
      Enum.map(raw_items, fn item ->
        menu_item_id = item["menu_item_id"] || item[:menu_item_id]
        quantity = to_int(item["quantity"] || item[:quantity] || 1)
        note = item["note"] || item[:note]

        case Repo.get(MenuItem, menu_item_id) do
          %MenuItem{available: true, category_id: ^category_id} = mi when quantity > 0 ->
            %{
              menu_item_id: mi.id,
              item_name: mi.name,
              quantity: quantity,
              unit_price: mi.price,
              subtotal: Decimal.mult(mi.price, quantity),
              note: note
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

  @doc "Chốt 1 đơn lẻ (admin): trừ quỹ + ghi giao dịch + đổi trạng thái. Atomic."
  def confirm_order(%Order{} = order, %User{} = admin) do
    order = Repo.preload(order, :user)

    if order.status != "pending" do
      {:error, :not_pending}
    else
      do_confirm(order, admin)
    end
  end

  defp do_confirm(order, admin) do
    user = order.user
    new_balance = Decimal.sub(user.balance, order.total_amount)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:user, User.balance_changeset(user, new_balance))
    |> Multi.update(
      :order,
      Order.status_changeset(order, %{status: "confirmed", confirmed_at: now})
    )
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

  defp string_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp to_int(_), do: 0
end
