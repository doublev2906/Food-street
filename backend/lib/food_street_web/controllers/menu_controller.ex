defmodule FoodStreetWeb.MenuController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Catalog

  def index(conn, _params) do
    json(conn, %{data: Catalog.list_available_menu_items()})
  end
end
