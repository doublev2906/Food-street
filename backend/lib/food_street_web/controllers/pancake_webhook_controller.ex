defmodule FoodStreetWeb.PancakeWebhookController do
  @moduledoc """
  Nhận webhook `messaging` từ Pancake Page. Endpoint công khai (Pancake gọi, không có
  đăng nhập) nên bảo vệ bằng 1 `secret` nhúng trong URL:

      POST /api/webhooks/pancake/<secret>

  Trả 200 ngay rồi relay tin nhà bán về Panchat nội bộ **async** (best-practice: phản
  hồi < 5s để Pancake không treo webhook). Xem `FoodStreet.PancakeInbound`.
  """
  use FoodStreetWeb, :controller

  require Logger

  alias FoodStreet.PancakeInbound

  def messaging(conn, %{"secret" => secret} = params) do
    if secret_ok?(secret) do
      payload = Map.delete(params, "secret")

      Task.Supervisor.start_child(FoodStreet.TaskSupervisor, fn ->
        try do
          PancakeInbound.handle_messaging(payload)
        rescue
          e -> Logger.error("[PancakeWebhook] xử lý lỗi: #{Exception.message(e)}")
        end
      end)

      send_resp(conn, 200, "")
    else
      send_resp(conn, 401, "")
    end
  end

  defp secret_ok?(given) do
    case Application.get_env(:food_street, :pancake_webhook_secret) do
      configured when is_binary(configured) and configured != "" ->
        Plug.Crypto.secure_compare(given, configured)

      _ ->
        Logger.warning("[PancakeWebhook] chưa cấu hình :pancake_webhook_secret — từ chối")
        false
    end
  end
end
