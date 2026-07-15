defmodule FoodStreetWeb.Admin.GroupOrderController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Ordering
  alias FoodStreet.Guardian
  alias FoodStreet.Settings
  alias FoodStreet.Panchat
  alias FoodStreet.PancakePage

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

    # Bắt buộc admin đã cấu hình Panchat token CỦA MÌNH: không có thì không cho mở
    # đợt (vì lời mời được gửi bằng chính token của admin tạo đợt).
    if Settings.panchat_configured?(admin.id) do
      with {:ok, go} <- Ordering.create_group_order(params, admin) do
        panchat = send_invite(go, Settings.panchat_token(admin.id))
        conn |> put_status(:created) |> json(%{data: shape(go), panchat: panchat})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        error: "panchat_token_missing",
        message:
          "Bạn chưa cấu hình Panchat token của mình. Vào tab Cài đặt để nhập token trước khi tạo đợt."
      })
    end
  end

  # Gửi lời mời vào Panchat (best-effort): lỗi mạng không rollback đợt đã tạo,
  # chỉ báo lại trạng thái để admin biết.
  defp send_invite(go, token) do
    case Panchat.send_breakfast_invite(go, token) do
      {:ok, _message} ->
        %{sent: true}

      {:error, reason} ->
        Logger.warning("Không gửi được lời mời Panchat cho đợt #{go.id}: #{inspect(reason)}")
        %{sent: false, error: format_error(reason)}
    end
  end

  defp format_error(:panchat_token_missing), do: "Chưa cấu hình Panchat token."
  defp format_error(:pancake_not_configured), do: "Danh mục chưa cấu hình Pancake."
  defp format_error({:panchat, msg}) when is_binary(msg), do: msg
  defp format_error({:pancake, msg}) when is_binary(msg), do: msg
  defp format_error({:pancake, reason}), do: "Lỗi Pancake: #{inspect(reason)}"
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
    admin = Guardian.Plug.current_resource(conn)

    case Ordering.get_group_order(id) do
      nil ->
        {:error, :not_found}

      go ->
        with {:ok, _} <- Ordering.delete_group_order(go) do
          notify_deleted(go, admin)
          send_resp(conn, :no_content, "")
        end
    end
  end

  # Báo Panchat khi xoá đợt (best-effort, token admin thực hiện).
  defp notify_deleted(go, admin) do
    case Panchat.send_group_deleted(go, Settings.panchat_token(admin.id)) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Không gửi được tin xoá đợt #{go.id}: #{inspect(reason)}")
        :ok
    end
  end

  def close(conn, %{"id" => id}) do
    admin = Guardian.Plug.current_resource(conn)

    case Ordering.get_group_order(id) do
      nil ->
        {:error, :not_found}

      go ->
        with {:ok, result} <- Ordering.close_group_order(go, admin) do
          panchat = notify_closed(result.group, result.confirmed, admin)

          # Chốt xong tự bốc ngẫu nhiên người đi lấy đồ theo số đã chọn khi tạo đợt.
          runners = Ordering.pick_runners(result.group, result.group.runner_count)
          runners_panchat = notify_runners(result.group, runners, admin)

          json(conn, %{
            data: %{
              confirmed: result.confirmed,
              group_order: shape(result.group),
              runners: Enum.map(runners, &%{id: &1.id, name: &1.name})
            },
            panchat: panchat,
            runners_panchat: runners_panchat
          })
        end
    end
  end

  @doc """
  Gửi đơn gộp của đợt cho nhà bán qua Pancake Page (nút bấm thủ công của admin).

  Danh mục của đợt phải cấu hình sẵn Pancake (page_id + conversation_id + token). Đợt
  phải có ít nhất 1 đơn chưa huỷ. Best-effort — trả trạng thái gửi để FE hiển thị.
  """
  def send_to_seller(conn, %{"id" => id}) do
    case Ordering.get_group_order(id) do
      nil ->
        {:error, :not_found}

      go ->
        cond do
          not FoodStreet.Catalog.Category.pancake_configured?(go.category) ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "pancake_not_configured",
              message:
                "Danh mục \"#{go.category && go.category.name}\" chưa cấu hình Pancake (Page ID / Conversation ID / Token). Vào tab Danh mục để nhập."
            })

          true ->
            send_order_to_seller(conn, go)
        end
    end
  end

  defp send_order_to_seller(conn, go) do
    case Ordering.aggregate_seller_text(go) do
      {:error, :no_orders} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no_orders", message: "Đợt chưa có đơn nào để gửi nhà bán."})

      {:ok, text} ->
        result =
          case PancakePage.send_order(go.category, text) do
            {:ok, _} ->
              %{sent: true}

            {:error, reason} ->
              Logger.warning("Không gửi được đơn cho nhà bán (đợt #{go.id}): #{inspect(reason)}")
              %{sent: false, error: format_error(reason)}
          end

        json(conn, %{data: result})
    end
  end

  # Gửi tin tổng kết vào Panchat khi chốt đợt (best-effort, token admin bấm chốt).
  defp notify_closed(group, count, admin) do
    total =
      Enum.reduce(group.orders || [], Decimal.new(0), fn o, acc ->
        if o.status == "cancelled", do: acc, else: Decimal.add(acc, o.total_amount)
      end)

    case Panchat.send_group_closed_summary(group, count, total, Settings.panchat_token(admin.id)) do
      {:ok, _} ->
        %{sent: true}

      {:error, reason} ->
        Logger.warning("Không gửi được tin chốt đợt #{group.id}: #{inspect(reason)}")
        %{sent: false, error: format_error(reason)}
    end
  end

  # Gửi tin báo người đi lấy đồ vào Panchat (best-effort, token admin thực hiện).
  # Không ai được bốc (runner_count = 0 hoặc chưa ai đặt) thì bỏ qua, không gửi tin.
  defp notify_runners(_go, [], _admin), do: %{skipped: true}

  defp notify_runners(go, runners, admin) do
    case Panchat.send_runners_picked(go, runners, Settings.panchat_token(admin.id)) do
      {:ok, _} ->
        %{sent: true}

      {:error, reason} ->
        Logger.warning("Không gửi được tin bốc người lấy đồ đợt #{go.id}: #{inspect(reason)}")
        %{sent: false, error: format_error(reason)}
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
      category: shape_category(go.category),
      orders: orders,
      order_count: length(orders),
      total_amount: total
    }
  end

  # Category kèm cờ `pancake_configured` để FE bật/tắt nút "Gửi đơn cho nhà bán".
  # KHÔNG trả token (bí mật).
  defp shape_category(nil), do: nil

  defp shape_category(%FoodStreet.Catalog.Category{} = c) do
    %{
      id: c.id,
      name: c.name,
      description: c.description,
      active: c.active,
      pancake_configured: FoodStreet.Catalog.Category.pancake_configured?(c)
    }
  end
end
