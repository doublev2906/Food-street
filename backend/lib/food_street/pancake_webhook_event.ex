defmodule FoodStreet.PancakeWebhookEvent do
  @moduledoc "Mốc đã xử lý 1 tin webhook Pancake (theo `message_id`) — chống relay trùng."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "pancake_webhook_events" do
    field :message_id, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:message_id])
    |> validate_required([:message_id])
    |> unique_constraint(:message_id)
  end
end
