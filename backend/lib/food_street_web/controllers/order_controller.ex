defmodule FoodStreetWeb.OrderController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Ordering
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    data = Enum.map(Ordering.list_user_orders(user.id), &embed_group/1)
    json(conn, %{data: data})
  end

  # Gắn kèm thông tin đợt (title + category) vào đơn.
  defp embed_group(order) do
    go =
      case order.group_order do
        %{id: id, title: title, status: status} = g ->
          %{id: id, title: title, status: status, category: g.category}

        _ ->
          nil
      end

    order
    |> Map.take([
      :id,
      :user_id,
      :group_order_id,
      :order_date,
      :status,
      :total_amount,
      :note,
      :confirmed_at,
      :inserted_at,
      :items
    ])
    |> Map.put(:group_order, go)
  end

  def cancel(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Ordering.get_order(id) do
      %{user_id: uid} = order when uid == user.id ->
        with {:ok, cancelled} <- Ordering.cancel_order(order) do
          json(conn, %{data: cancelled})
        end

      nil ->
        {:error, :not_found}

      _ ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end
end
