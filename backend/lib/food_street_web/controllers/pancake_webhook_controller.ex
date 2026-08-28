defmodule FoodStreetWeb.PancakeWebhookController do
  @moduledoc """
  Nhận webhook `messaging` từ Pancake Page. Endpoint công khai (Pancake gọi, không có
  đăng nhập) nên bảo vệ bằng 1 `secret` nhúng trong URL:

      POST /api/webhooks/pancake/<secret>

  Đưa tin nhà bán vào bộ debounce rồi trả 200 ngay (best-practice: phản hồi < 5s để
  Pancake không treo webhook). Xem `FoodStreet.PancakeInbound`.
  """
  use FoodStreetWeb, :controller

  require Logger

  alias FoodStreet.PancakeInbound

  def messaging(conn, %{"secret" => secret} = params) do
    if secret_ok?(secret) do
      payload = Map.delete(params, "secret")

      PancakeInbound.enqueue_messaging(payload)

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
