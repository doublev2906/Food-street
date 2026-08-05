defmodule FoodStreet.Settings do
  @moduledoc """
  Cấu hình dạng key-value lưu trong DB (bảng `settings`), **gắn theo từng user**.

  Dùng để lưu Panchat token do mỗi admin tự nhập qua UI. Token của admin nào chỉ
  áp cho đợt do admin đó tạo (xem `FoodStreet.Panchat`) — không ảnh hưởng admin khác.
  """

  alias FoodStreet.Repo
  alias FoodStreet.Settings.Setting

  @panchat_token_key "panchat_token"

  @doc "Đọc giá trị 1 setting của `user_id` theo key, trả `default` nếu chưa có."
  def get_value(user_id, key, default \\ nil) do
    case Repo.get_by(Setting, user_id: user_id, key: key) do
      nil -> default
      %Setting{value: value} -> value
    end
  end

  @doc "Upsert 1 setting của `user_id` (tạo mới hoặc cập nhật value theo (user_id, key))."
  def put_value(user_id, key, value) do
    %Setting{}
    |> Setting.changeset(%{user_id: user_id, key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
      conflict_target: [:user_id, :key]
    )
  end

  @doc "Panchat token của `user_id` (hoặc nil nếu chưa cấu hình)."
  def panchat_token(user_id), do: get_value(user_id, @panchat_token_key)

  @doc "Lưu Panchat token cho `user_id`."
  def put_panchat_token(user_id, token), do: put_value(user_id, @panchat_token_key, token)

  @doc "`user_id` đã cấu hình Panchat token hay chưa."
  def panchat_configured?(user_id) do
    case panchat_token(user_id) do
      nil -> false
      "" -> false
      token -> String.trim(token) != ""
    end
  end
end
