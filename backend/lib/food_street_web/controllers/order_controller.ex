defmodule FoodStreetWeb.OrderController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Ordering
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{data: Ordering.list_user_orders(user.id)})
  end

  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, order} <- Ordering.place_order(user, params) do
      conn |> put_status(:created) |> json(%{data: order})
    end
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
