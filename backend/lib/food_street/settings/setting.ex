defmodule FoodStreet.Settings.Setting do
  @moduledoc "Một cặp key-value cấu hình toàn cục của hệ thống."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :key, :value, :inserted_at, :updated_at]}

  schema "settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
