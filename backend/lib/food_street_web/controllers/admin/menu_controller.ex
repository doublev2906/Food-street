defmodule FoodStreetWeb.Admin.MenuController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Catalog

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Catalog.list_menu_items()})
  end

  def create(conn, params) do
    with {:ok, item} <- Catalog.create_menu_item(params) do
      conn |> put_status(:created) |> json(%{data: item})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Catalog.get_menu_item(id) do
      nil ->
        {:error, :not_found}

      item ->
        with {:ok, updated} <- Catalog.update_menu_item(item, params) do
          json(conn, %{data: updated})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Catalog.get_menu_item(id) do
      nil ->
        {:error, :not_found}

      item ->
        with {:ok, _} <- Catalog.delete_menu_item(item) do
          send_resp(conn, :no_content, "")
        end
    end
  end
end
