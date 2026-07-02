defmodule FoodStreetWeb.Admin.ExternalPurchaseController do
  @moduledoc "Admin ghi nhận khoản mua đồ ăn ngoài menu và chia tiền cho người ăn."
  use FoodStreetWeb, :controller

  alias FoodStreet.Fund
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, params) do
    result = Fund.list_external_purchases(params["page"] || 1, params["page_size"] || 20)

    json(conn, %{
      data: Enum.map(result.entries, &shape/1),
      page: result.page,
      page_size: result.page_size,
      total: result.total,
      total_pages: result.total_pages
    })
  end

  def create(conn, params) do
    admin = Guardian.Plug.current_resource(conn)

    case Fund.record_external_purchase(admin, params) do
      {:ok, purchase} ->
        conn |> put_status(:created) |> json(%{data: shape(purchase)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason), message: message(reason)})
    end
  end

  defp shape(p) do
    eaters =
      Enum.map(p.transactions || [], fn tx ->
        %{
          user_id: tx.user_id,
          name: tx.user && tx.user.name,
          amount: tx.amount && Decimal.abs(tx.amount)
        }
      end)

    %{
      id: p.id,
      description: p.description,
      total_amount: p.total_amount,
      purchase_date: p.purchase_date,
      created_by_id: p.created_by_id,
      inserted_at: p.inserted_at,
      eaters: eaters
    }
  end

  defp message(:amount_mismatch), do: "Tổng tiền chia không khớp với tổng khoản mua."
  defp message(:invalid_amount), do: "Số tiền không hợp lệ."
  defp message(:invalid_share), do: "Có người ăn thiếu số tiền hợp lệ (> 0)."
  defp message(:no_shares), do: "Hãy chọn ít nhất 1 người ăn."
  defp message(:duplicate_user), do: "Một người ăn bị chọn trùng."
  defp message(:user_not_found), do: "Có người dùng không tồn tại."
  defp message(other), do: "Không lưu được: #{inspect(other)}"
end
