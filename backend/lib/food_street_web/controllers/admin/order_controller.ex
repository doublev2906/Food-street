defmodule FoodStreetWeb.Admin.OrderController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Ordering
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, params) do
    filters = Map.take(params, ["date", "status"])
    data = Enum.map(Ordering.list_orders(filters), &embed_user/1)
    json(conn, %{data: data})
  end

  # Gắn kèm thông tin user vào đơn để admin xem được ai đặt.
  defp embed_user(order) do
    user =
      case order.user do
        %{id: id, name: name, email: email} -> %{id: id, name: name, email: email}
        _ -> nil
      end

    order
    |> Map.take([
      :id,
      :user_id,
      :order_date,
      :status,
      :total_amount,
      :note,
      :confirmed_at,
      :inserted_at,
      :items
    ])
    |> Map.put(:user, user)
  end

  def confirm(conn, %{"id" => id}) do
    admin = Guardian.Plug.current_resource(conn)

    case Ordering.get_order(id) do
      nil ->
        {:error, :not_found}

      order ->
        with {:ok, confirmed} <- Ordering.confirm_order(order, admin) do
          json(conn, %{data: confirmed})
        end
    end
  end

  def confirm_date(conn, %{"date" => date_str}) do
    admin = Guardian.Plug.current_resource(conn)

    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:ok, result} = Ordering.confirm_orders_for_date(date, admin)
        json(conn, %{data: result})

      _ ->
        {:error, :invalid_date}
    end
  end

  def confirm_date(_conn, _params), do: {:error, :missing_date}
end
