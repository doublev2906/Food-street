defmodule FoodStreet.Catalog.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias FoodStreet.Catalog.MenuItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :name, :description, :active, :inserted_at]}

  schema "categories" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true

    # Cấu hình Pancake Page của nhà bán phụ trách danh mục này. `page_access_token`
    # là bí mật — KHÔNG thêm vào @derive để tránh lộ qua JSON (menu/group_order nhúng
    # category trả cho user thường). Admin xem cấu hình qua shape riêng ở controller.
    field :pancake_page_id, :string
    field :pancake_conversation_id, :string
    field :pancake_page_access_token, :string

    has_many :menu_items, MenuItem

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [
      :name,
      :description,
      :active,
      :pancake_page_id,
      :pancake_conversation_id,
      :pancake_page_access_token
    ])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  @doc "Danh mục đã cấu hình đủ Pancake Page (page_id + conversation_id + token) chưa."
  def pancake_configured?(%__MODULE__{
        pancake_page_id: page_id,
        pancake_conversation_id: conv_id,
        pancake_page_access_token: token
      }) do
    present?(page_id) and present?(conv_id) and present?(token)
  end

  def pancake_configured?(_), do: false

  defp present?(v), do: is_binary(v) and String.trim(v) != ""
end
