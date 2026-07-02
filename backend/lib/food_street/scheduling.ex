defmodule FoodStreet.Scheduling do
  @moduledoc """
  Lịch hẹn tự động mở đợt đặt món hằng ngày (1 lịch dùng chung toàn hệ thống).

  `run_tick/1` được `FoodStreet.OrderScheduler` gọi định kỳ: nếu tới ngày/giờ đã
  hẹn và hôm nay chưa chạy, tạo 1 đợt đặt nhóm đứng tên `owner` rồi gửi lời mời
  Panchat bằng token của owner. Giờ tính theo giờ Việt Nam (UTC+7, không DST).
  """
  import Ecto.Query, warn: false
  require Logger

  alias FoodStreet.Repo
  alias FoodStreet.Scheduling.{DailyOrderSchedule, JobRun}
  alias FoodStreet.{Accounts, Ordering, Settings, Panchat}

  # Việt Nam: UTC+7 cố định, không có DST → không cần tzdata.
  @vn_offset_seconds 7 * 3600

  @doc "Lịch hẹn hiện tại (row singleton), hoặc `%DailyOrderSchedule{}` mặc định nếu chưa có."
  def get_schedule do
    Repo.one(from s in DailyOrderSchedule, order_by: [asc: s.inserted_at], limit: 1) ||
      %DailyOrderSchedule{}
  end

  @doc "Tạo mới hoặc cập nhật lịch hẹn dùng chung."
  def upsert_schedule(attrs) do
    get_schedule()
    |> DailyOrderSchedule.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Ngày (VN) job `key` chạy gần nhất, hoặc nil."
  def job_ran_on(key) do
    case Repo.get_by(JobRun, key: key) do
      nil -> nil
      %JobRun{last_run_on: date} -> date
    end
  end

  @doc "Đánh dấu job `key` đã chạy vào `date`."
  def mark_job_ran(key, date) do
    %JobRun{}
    |> JobRun.changeset(%{key: key, last_run_on: date})
    |> Repo.insert(
      on_conflict: [set: [last_run_on: date, updated_at: DateTime.utc_now(:second)]],
      conflict_target: :key
    )
  end

  @doc """
  Đã tới lúc chạy chưa (thuần, không side-effect) — dựa trên `now_utc`.

  Đúng khi: đang bật, hôm nay (VN) thuộc `weekdays`, đã qua `create_time`, và
  chưa chạy trong ngày (`last_run_on` khác ngày VN hiện tại).
  """
  def due?(%DailyOrderSchedule{} = s, now_utc) do
    with true <- s.enabled,
         true <- not is_nil(s.create_time),
         {vn_date, vn_time} <- vn_now(now_utc),
         true <- Date.day_of_week(vn_date) in (s.weekdays || []),
         true <- s.last_run_on != vn_date,
         true <- Time.compare(vn_time, s.create_time) != :lt do
      true
    else
      _ -> false
    end
  end

  @doc """
  Một nhịp chạy lịch. Trả:
  - `{:ok, :created, group_order}` khi vừa tạo đợt,
  - `{:ok, :skipped, reason}` khi chưa tới lúc / thiếu điều kiện,
  - `{:error, reason}` khi tạo đợt lỗi.
  """
  def run_tick(now_utc \\ DateTime.utc_now()) do
    schedule = get_schedule()

    cond do
      not due?(schedule, now_utc) ->
        {:ok, :skipped, :not_due}

      true ->
        maybe_create(schedule, now_utc)
    end
  end

  defp maybe_create(schedule, now_utc) do
    owner = schedule.owner_id && Accounts.get_user(schedule.owner_id)

    cond do
      is_nil(owner) or not Accounts.admin?(owner) ->
        Logger.warning(
          "[Scheduling] Bỏ qua: chủ lịch không hợp lệ (owner_id=#{schedule.owner_id})"
        )

        {:ok, :skipped, :owner_invalid}

      not Settings.panchat_configured?(owner.id) ->
        Logger.warning("[Scheduling] Bỏ qua: chủ lịch chưa cấu hình Panchat token")
        {:ok, :skipped, :owner_token_missing}

      true ->
        create_and_notify(schedule, owner, now_utc)
    end
  end

  defp create_and_notify(schedule, owner, now_utc) do
    {vn_date, _} = vn_now(now_utc)

    attrs = %{
      "title" => schedule.title,
      "order_date" => vn_date,
      "category_id" => schedule.category_id,
      "note" => schedule.note,
      "deadline" => deadline_utc(vn_date, schedule.deadline_time)
    }

    case Ordering.create_group_order(attrs, owner) do
      {:ok, go} ->
        # Đánh dấu đã chạy NGAY sau khi tạo thành công (chống tạo trùng dù Panchat lỗi).
        schedule |> DailyOrderSchedule.ran_changeset(vn_date) |> Repo.update!()
        send_invite(go, owner)
        {:ok, :created, go}

      {:error, reason} = err ->
        Logger.error("[Scheduling] Tạo đợt tự động thất bại: #{inspect(reason)}")
        err
    end
  end

  defp send_invite(go, owner) do
    case Panchat.send_breakfast_invite(go, Settings.panchat_token(owner.id)) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Scheduling] Không gửi được lời mời Panchat cho đợt #{go.id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  # Giờ Việt Nam từ UTC: trả {Date, Time} theo giờ tường VN.
  defp vn_now(now_utc) do
    vn = DateTime.add(now_utc, @vn_offset_seconds, :second)
    {DateTime.to_date(vn), DateTime.to_time(vn)}
  end

  # Deadline: giờ tường VN (vn_date @ deadline_time) → mốc UTC tương ứng.
  defp deadline_utc(_vn_date, nil), do: nil

  defp deadline_utc(vn_date, %Time{} = deadline_time) do
    vn_date
    |> DateTime.new!(deadline_time, "Etc/UTC")
    |> DateTime.add(-@vn_offset_seconds, :second)
    |> DateTime.truncate(:second)
  end
end
