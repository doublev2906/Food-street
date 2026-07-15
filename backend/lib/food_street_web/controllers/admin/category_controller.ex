defmodule FoodStreetWeb.Admin.CategoryController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Catalog
  alias FoodStreet.Catalog.Category

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Catalog.list_categories(), &shape/1)})
  end

  def create(conn, params) do
    with {:ok, category} <- Catalog.create_category(params) do
      conn |> put_status(:created) |> json(%{data: shape(category)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Catalog.get_category(id) do
      nil ->
        {:error, :not_found}

      category ->
        with {:ok, updated} <- Catalog.update_category(category, params) do
          json(conn, %{data: shape(updated)})
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

  # Trả cấu hình Pancake của nhà bán cho admin — page_id/conversation_id hiển thị được,
  # nhưng KHÔNG trả `pancake_page_access_token` (bí mật), chỉ báo đã cấu hình hay chưa.
  defp shape(%Category{} = c) do
    %{
      id: c.id,
      name: c.name,
      description: c.description,
      active: c.active,
      inserted_at: c.inserted_at,
      pancake_page_id: c.pancake_page_id,
      pancake_conversation_id: c.pancake_conversation_id,
      pancake_configured: Category.pancake_configured?(c)
    }
  end
end
