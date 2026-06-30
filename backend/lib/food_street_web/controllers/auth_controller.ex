defmodule FoodStreetWeb.AuthController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Accounts
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate(email, password) do
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
        |> json(%{error: "invalid_credentials", message: "Email hoặc mật khẩu không đúng"})
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_params", message: "Cần email và password"})
  end

  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{user: user})
  end
end
