defmodule FoodStreetWeb.Admin.UserController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Accounts

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Accounts.list_users()})
  end

  def show(conn, %{"id" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> json(conn, %{data: user})
    end
  end

  def create(conn, params) do
    with {:ok, user} <- Accounts.create_user(params) do
      conn |> put_status(:created) |> json(%{data: user})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Accounts.get_user(id) do
      nil ->
        {:error, :not_found}

      user ->
        with {:ok, updated} <- Accounts.update_user(user, params) do
          json(conn, %{data: updated})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    admin = Guardian.Plug.current_resource(conn)

    cond do
      admin && admin.id == id ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "cannot_delete_self", message: "Không thể tự xóa chính mình"})

      true ->
        case Accounts.get_user(id) do
          nil ->
            {:error, :not_found}

          user ->
            with {:ok, _} <- Accounts.delete_user(user) do
              send_resp(conn, :no_content, "")
            end
        end
    end
  end
end
