defmodule FoodStreetWeb.ShareAuthController do
  @moduledoc """
  Điểm kiểm tra cho Caddy `forward_auth` trước khi trả file `/share/*`.

    * Cookie `fs_share` hợp lệ -> 204 (Caddy cho xem file).
    * Không có / hết hạn -> 302 về `/login?next=<trang đang mở>` (Caddy chuyển nguyên
      response này cho trình duyệt), đăng nhập xong frontend quay lại đúng trang.
  """
  use FoodStreetWeb, :controller

  alias FoodStreetWeb.ShareAuth

  def check(conn, _params) do
    case ShareAuth.verify(conn) do
      {:ok, _user} ->
        send_resp(conn, :no_content, "")

      :error ->
        # Caddy gửi URI gốc trong X-Forwarded-Uri. Chỉ nhận đường dẫn dưới /share/
        # để không thành open redirect.
        next =
          case get_req_header(conn, "x-forwarded-uri") do
            ["/share/" <> _ = uri | _] -> uri
            _ -> "/share/"
          end

        conn
        |> put_resp_header("cache-control", "no-store")
        |> redirect(to: "/login?" <> URI.encode_query(%{"next" => next}))
    end
  end
end
