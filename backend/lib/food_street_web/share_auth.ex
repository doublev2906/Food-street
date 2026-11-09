defmodule FoodStreetWeb.ShareAuth do
  @moduledoc """
  Cookie đăng nhập cho trang HTML chia sẻ (`/share/*`).

  Token đăng nhập của app nằm trong localStorage (gửi qua header Authorization), nên
  khi trình duyệt mở thẳng link `/share/...` sẽ không có gì để xác thực. Vì vậy mỗi
  lần đăng nhập / mở app (`/api/me`) backend gắn thêm cookie `fs_share`:

    * `HttpOnly` + `Path=/share` — JS không đọc được, chỉ gửi kèm request `/share/*`.
    * Giá trị là `Phoenix.Token` (ký bằng secret_key_base) chứa user id, hạn 30 ngày.

  Caddy dùng `forward_auth` gọi `/api/share_auth` trước khi trả file; backend đọc
  cookie này để cho qua hoặc redirect sang trang đăng nhập.
  """
  import Plug.Conn

  alias FoodStreet.Accounts

  @cookie "fs_share"
  @salt "share pages"
  @max_age 30 * 24 * 60 * 60

  def put_cookie(conn, %{id: user_id}) do
    token = Phoenix.Token.sign(FoodStreetWeb.Endpoint, @salt, user_id)
    put_resp_cookie(conn, @cookie, token, [max_age: @max_age] ++ cookie_opts(conn))
  end

  def delete_cookie(conn), do: delete_resp_cookie(conn, @cookie, cookie_opts(conn))

  @doc "User đang đăng nhập theo cookie `fs_share` (phải còn hạn và tài khoản còn hoạt động)."
  def verify(conn) do
    conn = fetch_cookies(conn)

    with token when is_binary(token) <- conn.cookies[@cookie],
         {:ok, user_id} <-
           Phoenix.Token.verify(FoodStreetWeb.Endpoint, @salt, token, max_age: @max_age),
         %{active: true} = user <- Accounts.get_user(user_id) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  # Prod chạy sau nginx/Caddy với X-Forwarded-Proto https (force_ssl rewrite) nên
  # scheme = :https -> cookie Secure. Dev qua http thì bỏ Secure kẻo trình duyệt vứt cookie.
  defp cookie_opts(conn) do
    [path: "/share", http_only: true, same_site: "Lax", secure: conn.scheme == :https]
  end
end
