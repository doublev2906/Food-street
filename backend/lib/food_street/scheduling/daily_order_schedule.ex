defmodule FoodStreet.Scheduling.DailyOrderSchedule do
  @moduledoc """
  Lịch hẹn tự động mở đợt đặt món hằng ngày (singleton — 1 lịch dùng chung).

  `weekdays` theo ISO `Date.day_of_week/1`: 1 = Thứ 2 … 7 = Chủ nhật.
  `owner` là admin đứng tên: đợt auto do owner tạo và gửi Panchat bằng token owner.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Accounts.User
  alias FoodStreet.Catalog.Category

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :enabled,
             :owner_id,
             :category_id,
             :title,
             :note,
             :weekdays,
             :create_time,
             :deadline_time,
             :runner_count,
             :last_run_on,
             :updated_at
           ]}

  schema "daily_order_schedules" do
    field :enabled, :boolean, default: false
    field :title, :string
    field :note, :string
    field :weekdays, {:array, :integer}, default: []
    field :create_time, :time
    field :deadline_time, :time
    field :runner_count, :integer, default: 0
    field :last_run_on, :date

    belongs_to :owner, User
    belongs_to :category, Category

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset cho phần cấu hình admin nhập. Khi `enabled` = true thì mọi trường cần
  để chạy đều bắt buộc (owner/category/giờ/ngày).
  """
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :enabled,
      :owner_id,
      :category_id,
      :title,
      :note,
      :weekdays,
      :create_time,
      :deadline_time,
      :runner_count
    ])
    |> validate_weekdays()
    |> validate_number(:runner_count, greater_than_or_equal_to: 0)
    |> validate_time_order()
    |> maybe_require_when_enabled()
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:category_id)
  end

  @doc "Cập nhật mốc đã chạy trong ngày (chống tạo trùng)."
  def ran_changeset(schedule, date) do
    change(schedule, last_run_on: date)
  end

  defp validate_weekdays(changeset) do
    validate_change(changeset, :weekdays, fn :weekdays, days ->
      cond do
        Enum.all?(days, &(&1 in 1..7)) and Enum.uniq(days) == days -> []
        true -> [weekdays: "chỉ nhận các ngày 1..7 (không trùng)"]
      end
    end)
  end

  defp validate_time_order(changeset) do
    create = get_field(changeset, :create_time)
    deadline = get_field(changeset, :deadline_time)

    if create && deadline && Time.compare(create, deadline) != :lt do
      add_error(changeset, :deadline_time, "giờ chốt đơn phải sau giờ tạo")
    else
      changeset
    end
  end

  defp maybe_require_when_enabled(changeset) do
    if get_field(changeset, :enabled) do
      changeset
      |> validate_required([:owner_id, :category_id, :title, :create_time, :deadline_time])
      |> validate_length(:weekdays, min: 1)
    else
      changeset
    end
  end
end
