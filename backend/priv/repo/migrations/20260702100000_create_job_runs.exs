defmodule FoodStreet.Repo.Migrations.CreateJobRuns do
  @moduledoc """
  Ghi mốc chạy gần nhất của các job định kỳ hệ thống (theo `key`), để chống chạy
  trùng trong ngày. Vd: job "balance_report" báo số dư 17:00 GMT+7 mỗi ngày.
  """
  use Ecto.Migration

  def change do
    create table(:job_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :last_run_on, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:job_runs, [:key])
  end
end
