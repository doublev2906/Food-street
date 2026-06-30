defmodule FoodStreetWeb.GroupOrderController do
  @moduledoc "Phía user: xem các đợt đặt đang mở và đặt đơn vào đợt."
  use FoodStreetWeb, :controller

  alias FoodStreet.Ordering
  alias FoodStreet.Catalog
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  # Danh sách đợt đang mở
  def index(conn, _params) do
    data =
      Enum.map(Ordering.list_open_group_orders(), fn go ->
        %{
          id: go.id,
          title: go.title,
          order_date: go.order_date,
          status: go.status,
          note: go.note,
          deadline: go.deadline,
          category: go.category
        }
      end)

    json(conn, %{data: data})
  end

  # Chi tiết 1 đợt: thông tin đợt + menu theo danh mục + đơn hiện tại của user
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Ordering.get_group_order(id) do
      nil ->
        {:error, :not_found}

      go ->
        json(conn, %{
          data: %{
            group_order: %{
              id: go.id,
              title: go.title,
              order_date: go.order_date,
              status: go.status,
              note: go.note,
              deadline: go.deadline,
              category: go.category
            },
            menu_items: Catalog.list_available_by_category(go.category_id),
            my_order: Ordering.get_user_order_in_group(user.id, go.id)
          }
        })
    end
  end

  # Đặt/cập nhật đơn của user trong đợt
  def create_order(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, order} <- Ordering.place_order_in_group(user, id, params) do
      conn |> put_status(:created) |> json(%{data: order})
    end
  end
end
