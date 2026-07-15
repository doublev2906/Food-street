defmodule FoodStreetWeb.Admin.InterestController do
  @moduledoc """
  Quỹ lãi (issue #12): xem tổng quan quỹ, lịch sử tính lãi và chạy tính lãi thủ công.
  """
  use FoodStreetWeb, :controller

  alias FoodStreet.Interest

  action_fallback FoodStreetWeb.FallbackController

  @doc "Tổng quan quỹ lãi + thông số lãi suất hiện hành."
  def fund(conn, _params) do
    json(conn, %{data: Interest.fund_summary()})
  end

  @doc "Lịch sử tính lãi (sổ cái quỹ) — phân trang, lọc theo user."
  def index(conn, params) do
    result = Interest.list_charges(params)

    json(conn, %{
      data: Enum.map(result.entries, &shape/1),
      page: result.page,
      page_size: result.page_size,
      total: result.total,
      total_pages: result.total_pages
    })
  end

  @doc "Chạy tính lãi cho hôm nay ngay (bỏ qua chặn giờ); idempotent trong ngày."
  def run(conn, _params) do
    result = Interest.accrue_today()
    json(conn, %{data: result, fund: Interest.fund_summary()})
  end

  defp shape(charge) do
    charge
    |> Map.take([
      :id,
      :user_id,
      :amount,
      :debt_before,
      :balance_after,
      :charged_on,
      :fund_transaction_id,
      :inserted_at
    ])
    |> Map.put(:user, user_map(charge.user))
  end

  defp user_map(%{id: id, name: name}), do: %{id: id, name: name}
  defp user_map(_), do: nil
end
