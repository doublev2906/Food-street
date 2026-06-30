defmodule FoodStreetWeb.Admin.GroupOrderController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Ordering
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, params) do
    filters = Map.take(params, ["status"])
    data = Enum.map(Ordering.list_group_orders(filters), &shape/1)
    json(conn, %{data: data})
  end

  def show(conn, %{"id" => id}) do
    case Ordering.get_group_order(id) do
      nil -> {:error, :not_found}
      go -> json(conn, %{data: shape(go)})
    end
  end

  def create(conn, params) do
    admin = Guardian.Plug.current_resource(conn)

    with {:ok, go} <- Ordering.create_group_order(params, admin) do
      conn |> put_status(:created) |> json(%{data: shape(go)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Ordering.get_group_order(id) do
      nil ->
        {:error, :not_found}

      go ->
        with {:ok, updated} <- Ordering.update_group_order(go, params) do
          json(conn, %{data: shape(updated)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Ordering.get_group_order(id) do
      nil ->
        {:error, :not_found}

      go ->
        with {:ok, _} <- Ordering.delete_group_order(go) do
          send_resp(conn, :no_content, "")
        end
    end
  end

  def close(conn, %{"id" => id}) do
    admin = Guardian.Plug.current_resource(conn)

    case Ordering.get_group_order(id) do
      nil ->
        {:error, :not_found}

      go ->
        with {:ok, result} <- Ordering.close_group_order(go, admin) do
          json(conn, %{data: %{confirmed: result.confirmed, group_order: shape(result.group)}})
        end
    end
  end

  # Gắn thông tin user vào từng đơn để admin xem ai đặt gì.
  defp shape(go) do
    orders =
      Enum.map(go.orders || [], fn o ->
        %{
          id: o.id,
          user_id: o.user_id,
          status: o.status,
          total_amount: o.total_amount,
          note: o.note,
          items: o.items,
          user: o.user && %{id: o.user.id, name: o.user.name, email: o.user.email}
        }
      end)

    total =
      Enum.reduce(orders, Decimal.new(0), fn o, acc ->
        if o.status == "cancelled", do: acc, else: Decimal.add(acc, o.total_amount)
      end)

    %{
      id: go.id,
      title: go.title,
      order_date: go.order_date,
      status: go.status,
      note: go.note,
      deadline: go.deadline,
      closed_at: go.closed_at,
      category: go.category,
      orders: orders,
      order_count: length(orders),
      total_amount: total
    }
  end
end
