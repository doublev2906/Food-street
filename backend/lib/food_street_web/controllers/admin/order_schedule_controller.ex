defmodule FoodStreetWeb.Admin.OrderScheduleController do
  @moduledoc "Admin cấu hình lịch hẹn tự động mở đợt đặt món hằng ngày (dùng chung)."
  use FoodStreetWeb, :controller

  alias FoodStreet.Scheduling
  alias FoodStreet.Settings

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

      enabled? and not Settings.panchat_configured?(owner_id) ->
        error(
          conn,
          "owner_panchat_token_missing",
          "Admin đứng tên chưa cấu hình Panchat token của mình — không thể bật lịch hẹn."
        )

      true ->
        with {:ok, schedule} <- Scheduling.upsert_schedule(params) do
          json(conn, %{data: shape(schedule)})
        end
    end
  end

  # Bổ sung cờ `panchat_ready` để UI cảnh báo khi chủ lịch chưa có token.
  defp shape(schedule) do
    ready = not is_nil(schedule.owner_id) and Settings.panchat_configured?(schedule.owner_id)

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
