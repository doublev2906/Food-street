defmodule FoodStreetWeb.Admin.GroupOrderController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Ordering
  alias FoodStreet.Guardian
  alias FoodStreet.Settings
  alias FoodStreet.Panchat

  require Logger

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

    # Bắt buộc có Panchat token: không có thì không cho mở đợt (vì không gửi
    # được lời mời ăn sáng vào channel).
    if Settings.panchat_configured?() do
      with {:ok, go} <- Ordering.create_group_order(params, admin) do
        panchat = send_invite(go)
        conn |> put_status(:created) |> json(%{data: shape(go), panchat: panchat})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        error: "panchat_token_missing",
        message: "Chưa cấu hình Panchat token. Vào tab Cài đặt để nhập token trước khi tạo đợt."
      })
    end
  end

  # Gửi lời mời vào Panchat (best-effort): lỗi mạng không rollback đợt đã tạo,
  # chỉ báo lại trạng thái để admin biết.
  defp send_invite(go) do
    case Panchat.send_breakfast_invite(go) do
      {:ok, _message} ->
        %{sent: true}

      {:error, reason} ->
        Logger.warning("Không gửi được lời mời Panchat cho đợt #{go.id}: #{inspect(reason)}")
        %{sent: false, error: format_error(reason)}
    end
  end

  defp format_error(:panchat_token_missing), do: "Chưa cấu hình Panchat token."
  defp format_error({:panchat, msg}) when is_binary(msg), do: msg
  defp format_error(other), do: inspect(other)

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
