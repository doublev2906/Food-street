defmodule FoodStreetWeb.FundController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Fund
  alias FoodStreet.Guardian

  # Số dư quỹ của chính user đang đăng nhập
  def balance(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{balance: user.balance, user_id: user.id, name: user.name})
  end

  # Lịch sử giao dịch quỹ của chính user
  def transactions(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{data: Fund.list_user_transactions(user.id)})
  end
end
