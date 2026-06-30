defmodule FoodStreetWeb.ProfileController do
  @moduledoc "Người dùng tự cập nhật hồ sơ: đổi tên, đổi mật khẩu."
  use FoodStreetWeb, :controller

  alias FoodStreet.Accounts
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  # Đổi tên hiển thị
  def update(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, updated} <- Accounts.update_profile(user, params) do
      json(conn, %{user: updated})
    end
  end

  # Đổi mật khẩu — cần mật khẩu hiện tại
  def change_password(conn, %{"current_password" => cur, "new_password" => new}) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.change_password(user, cur, new) do
      {:ok, _user} ->
        json(conn, %{ok: true, message: "Đổi mật khẩu thành công"})

      {:error, :invalid_current_password} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_current_password", message: "Mật khẩu hiện tại không đúng"})

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def change_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_params", message: "Cần current_password và new_password"})
  end
end
