defmodule FoodStreetWeb.HealthController do
  use FoodStreetWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok", service: "food_street", time: DateTime.utc_now()})
  end
end
