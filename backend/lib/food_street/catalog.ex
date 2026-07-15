defmodule FoodStreet.Catalog do
  @moduledoc "Quản lý thực đơn và danh mục món ăn."

  import Ecto.Query, warn: false
  alias FoodStreet.Repo
  alias FoodStreet.Catalog.MenuItem
  alias FoodStreet.Catalog.Category

  # ---- Menu items ----

  def list_menu_items do
    Repo.all(from m in MenuItem, order_by: [asc: m.name], preload: :category)
  end

  def list_available_menu_items do
    Repo.all(from m in MenuItem, where: m.available == true, order_by: [asc: m.name])
  end

  @doc "Các món còn bán thuộc 1 danh mục (dùng khi đặt theo đợt nhóm)."
  def list_available_by_category(category_id) do
    Repo.all(
      from m in MenuItem,
        where: m.available == true and m.category_id == ^category_id,
        order_by: [asc: m.name]
    )
  end

  def get_menu_item!(id), do: Repo.get!(MenuItem, id)
  def get_menu_item(id), do: Repo.get(MenuItem, id)

  def create_menu_item(attrs) do
    %MenuItem{}
    |> MenuItem.changeset(attrs)
    |> Repo.insert()
  end

  def update_menu_item(%MenuItem{} = item, attrs) do
    item
    |> MenuItem.changeset(attrs)
    |> Repo.update()
  end

  def delete_menu_item(%MenuItem{} = item), do: Repo.delete(item)

  # ---- Categories ----

  def list_categories do
    Repo.all(from c in Category, order_by: [asc: c.name])
  end

  def list_active_categories do
    Repo.all(from c in Category, where: c.active == true, order_by: [asc: c.name])
  end

  def get_category(id), do: Repo.get(Category, id)

  @doc """
  Tìm danh mục theo `pancake_conversation_id` — map ngược từ webhook Pancake (khi
  nhà bán trả lời trong 1 conversation) về đúng danh mục/nhà bán. `nil` nếu không khớp.
  """
  def get_category_by_conversation_id(conversation_id) when is_binary(conversation_id) do
    Repo.one(from c in Category, where: c.pancake_conversation_id == ^conversation_id)
  end

  def get_category_by_conversation_id(_), do: nil

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%Category{} = category), do: Repo.delete(category)
end
