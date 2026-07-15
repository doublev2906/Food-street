defmodule FoodStreet.Accounts do
  @moduledoc "Quản lý người dùng (user/admin) và xác thực đăng nhập."

  import Ecto.Query, warn: false
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User

  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  @doc """
  Danh sách user đã gắn `panchat_user_id` (khác nil và khác rỗng) — tức những
  người có thể mention thật (ping) trên Panchat. Dùng cho tính năng thông báo.
  """
  def list_users_with_panchat_id do
    User
    |> where([u], not is_nil(u.panchat_user_id) and u.panchat_user_id != "")
    |> order_by([u], asc: u.name)
    |> Repo.all()
  end

  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(String.trim(email)))
  end

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: String.downcase(String.trim(username)))
  end

  @doc "Tìm theo username trước, không có thì thử email."
  def get_user_by_identifier(identifier) when is_binary(identifier) do
    get_user_by_username(identifier) || get_user_by_email(identifier)
  end

  def create_user(attrs) do
    %User{}
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user), do: Repo.delete(user)

  @doc "Người dùng tự đổi tên hiển thị."
  def update_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Người dùng tự đổi mật khẩu: phải nhập đúng mật khẩu hiện tại.
  Trả về {:ok, user} | {:error, :invalid_current_password} | {:error, changeset}.
  """
  def change_password(%User{} = user, current_password, new_password) do
    if is_binary(current_password) and Bcrypt.verify_pass(current_password, user.password_hash) do
      user
      |> User.password_changeset(%{"password" => new_password})
      |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  @doc "Xác thực bằng username hoặc email + mật khẩu. {:ok, user} | {:error, reason}."
  def authenticate(identifier, password) when is_binary(identifier) and is_binary(password) do
    user = get_user_by_identifier(identifier)

    cond do
      user && user.active && Bcrypt.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user && !user.active ->
        {:error, :inactive}

      user ->
        {:error, :invalid_credentials}

      true ->
        # Tránh timing attack: vẫn chạy hash giả
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def admin?(%User{role: "admin"}), do: true
  def admin?(_), do: false

  def count_users, do: Repo.aggregate(User, :count, :id)
end
