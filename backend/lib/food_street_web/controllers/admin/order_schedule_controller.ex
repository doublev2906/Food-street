defmodule FoodStreetWeb.Admin.OrderScheduleController do
  @moduledoc "Admin cấu hình lịch hẹn tự động mở đợt đặt món hằng ngày (dùng chung)."
  use FoodStreetWeb, :controller

  alias FoodStreet.Scheduling
  alias FoodStreet.Panchat

  action_fallback FoodStreetWeb.FallbackController

  def show(conn, _params) do
    json(conn, %{data: shape(Scheduling.get_schedule())})
  end

  def update(conn, params) do
    enabled? = truthy(params["enabled"])
    owner_id = params["owner_id"]

    cond do
      enabled? and (is_nil(owner_id) or owner_id == "") ->
        error(conn, "owner_required", "Hãy chọn admin đứng tên trước khi bật lịch.")

      enabled? and is_nil(Panchat.bot_token()) ->
        error(
          conn,
          "panchat_bot_token_missing",
          "Hệ thống chưa cấu hình token bot Panchat (PANCHAT_BOT_TOKEN) — không thể bật lịch hẹn."
        )

      true ->
        with {:ok, schedule} <- Scheduling.upsert_schedule(params) do
          json(conn, %{data: shape(schedule)})
        end
    end
  end

  # Cờ `panchat_ready`: đợt tự động gửi bằng token bot → sẵn sàng khi bot token đã cấu hình.
  defp shape(schedule) do
    ready = not is_nil(Panchat.bot_token())

    %{
      id: schedule.id,
      enabled: schedule.enabled,
      owner_id: schedule.owner_id,
      category_id: schedule.category_id,
      title: schedule.title,
      note: schedule.note,
      weekdays: schedule.weekdays || [],
      create_time: schedule.create_time,
      deadline_time: schedule.deadline_time,
      runner_count: schedule.runner_count,
      last_run_on: schedule.last_run_on,
      panchat_ready: ready
    }
  end

  defp truthy(true), do: true
  defp truthy("1"), do: true
  defp truthy("true"), do: true
  defp truthy(_), do: false

  defp error(conn, code, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: code, message: message})
  end
end
