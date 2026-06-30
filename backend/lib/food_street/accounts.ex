defmodule FoodStreet.Accounts do
  @moduledoc "Quản lý người dùng (user/admin) và xác thực đăng nhập."

  import Ecto.Query, warn: false
  alias FoodStreet.Repo
  alias FoodStreet.Accounts.User

  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(String.trim(email)))
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

  @doc "Xác thực bằng email + mật khẩu. Trả về {:ok, user} hoặc {:error, reason}."
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

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
