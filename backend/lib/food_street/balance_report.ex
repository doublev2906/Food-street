defmodule FoodStreet.BalanceReport do
  @moduledoc """
  Báo số dư quỹ của từng người vào Panchat lúc 17:00 (GMT+7) mỗi ngày.

  `run_tick/1` được `FoodStreet.OrderScheduler` gọi định kỳ. Tin gửi bằng token
  của một admin NGẪU NHIÊN có cấu hình Panchat token. Chống gửi trùng trong ngày
  bằng `job_runs` (key "balance_report"). Giờ tính theo giờ VN (UTC+7, không DST).
  """
  import Ecto.Query, warn: false
  require Logger

  alias FoodStreet.{Repo, Settings, Panchat, Scheduling}
  alias FoodStreet.Accounts.User

  @job "balance_report"
  @report_hour 17
  @vn_offset_seconds 7 * 3600

  @doc """
  Một nhịp: nếu đã tới 17:00 (VN) và hôm nay chưa gửi thì báo số dư vào Panchat.
  Trả `{:ok, :sent}` | `{:ok, :skipped, reason}` | `{:error, reason}`.
  """
  def run_tick(now_utc \\ DateTime.utc_now()) do
    {vn_date, vn_time} = vn_now(now_utc)

    cond do
      vn_time.hour < @report_hour ->
        {:ok, :skipped, :too_early}

      Scheduling.job_ran_on(@job) == vn_date ->
        {:ok, :skipped, :already_sent}

      true ->
        do_send(vn_date)
    end
  end

  defp do_send(vn_date) do
    case pick_admin_token() do
      nil ->
        Logger.warning("[BalanceReport] Không có admin nào cấu hình Panchat token — bỏ qua")
        {:ok, :skipped, :no_admin_token}

      token ->
        case Panchat.send_balance_report(active_users(), vn_date, token) do
          {:ok, _} ->
            Scheduling.mark_job_ran(@job, vn_date)
            {:ok, :sent}

          {:error, reason} ->
            Logger.warning("[BalanceReport] gửi thất bại: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp active_users do
    Repo.all(from u in User, where: u.active == true, order_by: [asc: u.name])
  end

  # Chọn ngẫu nhiên 1 admin đang hoạt động đã cấu hình Panchat token; nil nếu không có.
  defp pick_admin_token do
    admins = Repo.all(from u in User, where: u.role == "admin" and u.active == true)

    case Enum.filter(admins, &Settings.panchat_configured?(&1.id)) do
      [] -> nil
      list -> Settings.panchat_token(Enum.random(list).id)
    end
  end

  defp vn_now(now_utc) do
    vn = DateTime.add(now_utc, @vn_offset_seconds, :second)
    {DateTime.to_date(vn), DateTime.to_time(vn)}
  end
end
