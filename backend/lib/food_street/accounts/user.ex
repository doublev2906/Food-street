defmodule FoodStreet.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [:id, :name, :username, :email, :role, :balance, :active, :inserted_at]}

  @roles ~w(user admin)

  schema "users" do
    field :name, :string
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :role, :string, default: "user"
    field :balance, :decimal, default: Decimal.new(0)
    field :active, :boolean, default: true

    field :password, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a user (admin creates users)."
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :username, :email, :role, :active, :password, :balance])
    |> validate_required([:name, :username, :email, :password])
    |> validate_inclusion(:role, @roles)
    |> validate_username()
    |> validate_email()
    |> validate_password()
    |> put_password_hash()
  end

  @doc "Changeset for updating a user (admin)."
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :username, :email, :role, :active, :password])
    |> validate_required([:name, :username, :email])
    |> validate_inclusion(:role, @roles)
    |> validate_username()
    |> validate_email()
    |> maybe_validate_password()
    |> maybe_put_password_hash()
  end

  @doc "Người dùng tự cập nhật hồ sơ (chỉ tên)."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end

  @doc "Đặt mật khẩu mới (đã xác thực mật khẩu cũ ở context)."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> put_password_hash()
  end

  @doc "Changeset that only updates the balance (used by Fund context)."
  def balance_changeset(user, new_balance) do
    change(user, balance: new_balance)
  end

  defp validate_username(changeset) do
    changeset
    |> update_change(:username, &String.downcase(String.trim(&1 || "")))
    |> validate_format(:username, ~r/^[a-z0-9_.]+$/,
      message: "chỉ gồm chữ thường, số, dấu chấm hoặc gạch dưới"
    )
    |> validate_length(:username, min: 3, max: 30)
    |> unique_constraint(:username)
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &String.downcase(String.trim(&1 || "")))
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "email không hợp lệ")
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 6, max: 72)
  end

  defp maybe_validate_password(changeset) do
    if get_change(changeset, :password), do: validate_password(changeset), else: changeset
  end

  defp put_password_hash(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))

      _ ->
        changeset
    end
  end

  defp maybe_put_password_hash(changeset) do
    if get_change(changeset, :password), do: put_password_hash(changeset), else: changeset
  end
end
