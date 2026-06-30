defmodule FoodStreet.Catalog do
  @moduledoc "Quản lý thực đơn đồ ăn sáng."

  import Ecto.Query, warn: false
  alias FoodStreet.Repo
  alias FoodStreet.Catalog.MenuItem

  def list_menu_items do
    Repo.all(from m in MenuItem, order_by: [asc: m.name])
  end

  def list_available_menu_items do
    Repo.all(from m in MenuItem, where: m.available == true, order_by: [asc: m.name])
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
end
