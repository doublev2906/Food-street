defmodule FoodStreet.Settings do
  @moduledoc """
  Cấu hình toàn cục dạng key-value lưu trong DB (bảng `settings`).

  Hiện dùng để lưu Panchat token do admin nhập qua UI. Token này cần thiết để
  gửi lời mời ăn sáng vào channel Panchat (xem `FoodStreet.Panchat`).
  """

  import Ecto.Query, warn: false
  alias FoodStreet.Repo
  alias FoodStreet.Settings.Setting

  @panchat_token_key "panchat_token"

  @doc "Đọc giá trị 1 setting theo key, trả `default` nếu chưa có."
  def get_value(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      nil -> default
      %Setting{value: value} -> value
    end
  end

  @doc "Upsert 1 setting (tạo mới hoặc cập nhật value theo key)."
  def put_value(key, value) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
      conflict_target: :key
    )
  end

  @doc "Panchat token hiện tại (hoặc nil nếu chưa cấu hình)."
  def panchat_token, do: get_value(@panchat_token_key)

  @doc "Lưu Panchat token."
  def put_panchat_token(token), do: put_value(@panchat_token_key, token)

  @doc "Đã cấu hình Panchat token hay chưa."
  def panchat_configured? do
    case panchat_token() do
      nil -> false
      "" -> false
      token -> String.trim(token) != ""
    end
  end
end
