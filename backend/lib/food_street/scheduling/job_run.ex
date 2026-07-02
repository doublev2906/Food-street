defmodule FoodStreet.Scheduling.JobRun do
  @moduledoc "Mốc chạy gần nhất của 1 job định kỳ (theo `key`) — chống chạy trùng trong ngày."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "job_runs" do
    field :key, :string
    field :last_run_on, :date

    timestamps(type: :utc_datetime)
  end

  def changeset(job_run, attrs) do
    job_run
    |> cast(attrs, [:key, :last_run_on])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
