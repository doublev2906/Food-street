defmodule FoodStreetWeb.InterestController do
  @moduledoc "Cho user tự xem tình trạng nợ (gốc + lãi) của chính mình (issue #12)."
  use FoodStreetWeb, :controller

  alias FoodStreet.Interest
  alias FoodStreet.Guardian

  # Tình trạng nợ của chính user đang đăng nhập.
  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{data: Interest.user_status(user)})
  end
end
