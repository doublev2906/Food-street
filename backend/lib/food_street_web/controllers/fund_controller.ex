defmodule FoodStreetWeb.FundController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Fund
  alias FoodStreet.Guardian

  # Số dư quỹ của chính user đang đăng nhập
  def balance(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{balance: user.balance, user_id: user.id, name: user.name})
  end

  # Lịch sử giao dịch quỹ của chính user — phân trang, kèm tổng vào/ra toàn lịch sử
  def transactions(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    result = Fund.paginate_user_transactions(user.id, Map.take(params, ["page", "page_size"]))

    json(conn, %{
      data: result.entries,
      page: result.page,
      page_size: result.page_size,
      total: result.total,
      total_pages: result.total_pages,
      total_in: result.total_in,
      total_out: result.total_out
    })
  end
end
