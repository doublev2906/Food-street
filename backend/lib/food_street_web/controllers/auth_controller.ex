defmodule FoodStreetWeb.AuthController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Accounts
  alias FoodStreet.Guardian
  alias FoodStreetWeb.ShareAuth

  action_fallback FoodStreetWeb.FallbackController

  def login(conn, %{"password" => password} = params) do
    identifier = params["username"] || params["email"]
    do_login(conn, identifier, password)
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_params", message: "Cần username và password"})
  end

  defp do_login(conn, identifier, password) when is_binary(identifier) do
    case Accounts.authenticate(identifier, password) do
      {:ok, user} ->
        token = Guardian.create_token(user)

        conn
        |> ShareAuth.put_cookie(user)
        |> json(%{token: token, user: user})

      {:error, :inactive} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "account_inactive", message: "Tài khoản đã bị khóa"})

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "invalid_credentials",
          message: "Tên đăng nhập hoặc mật khẩu không đúng"
        })
    end
  end

  defp do_login(conn, _identifier, _password) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_params", message: "Cần username và password"})
  end

  # Frontend gọi mỗi lần mở app -> làm mới luôn cookie xem trang /share.
  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    conn
    |> ShareAuth.put_cookie(user)
    |> json(%{user: user})
  end

  def logout(conn, _params) do
    conn
    |> ShareAuth.delete_cookie()
    |> send_resp(:no_content, "")
  end
end
