defmodule FoodStreetWeb.Admin.CategoryController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Catalog

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Catalog.list_categories()})
  end

  def create(conn, params) do
    with {:ok, category} <- Catalog.create_category(params) do
      conn |> put_status(:created) |> json(%{data: category})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Catalog.get_category(id) do
      nil ->
        {:error, :not_found}

      category ->
        with {:ok, updated} <- Catalog.update_category(category, params) do
          json(conn, %{data: updated})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Catalog.get_category(id) do
      nil ->
        {:error, :not_found}

      category ->
        with {:ok, _} <- Catalog.delete_category(category) do
          send_resp(conn, :no_content, "")
        end
    end
  end
end
