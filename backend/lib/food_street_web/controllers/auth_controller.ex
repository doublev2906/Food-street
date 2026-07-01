defmodule FoodStreetWeb.AuthController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Accounts
  alias FoodStreet.Guardian

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
        json(conn, %{token: token, user: user})

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

  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{user: user})
  end
end
