defmodule FoodStreet.SharedPages.State do
  @moduledoc "Dữ liệu người xem đã nhập trên 1 trang HTML chia sẻ (dùng chung cho mọi người)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shared_page_states" do
    field :page_path, :string
    field :data, :map, default: %{}
    belongs_to :updated_by, FoodStreet.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
