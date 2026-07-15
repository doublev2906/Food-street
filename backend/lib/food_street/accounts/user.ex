defmodule FoodStreet.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :username,
             :email,
             :role,
             :balance,
             :interest_debt,
             :active,
             :panchat_user_id,
             :inserted_at
           ]}

  @roles ~w(user admin)

  # UUID chuẩn (Panchat user_id), validate khi admin nhập tay để mention khỏi lệch.
  @uuid_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  schema "users" do
    field :name, :string
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :role, :string, default: "user"
    field :balance, :decimal, default: Decimal.new(0)

    # Nợ lãi trên số dư âm (issue #12) — tách khỏi balance; nạp tiền trừ khoản này trước.
    field :interest_debt, :decimal, default: Decimal.new(0)
    field :active, :boolean, default: true
    field :panchat_user_id, :string

    field :password, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a user (admin creates users)."
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :username, :email, :role, :active, :password, :balance, :panchat_user_id])
    |> validate_required([:name, :username, :email, :password])
    |> validate_inclusion(:role, @roles)
    |> validate_username()
    |> validate_email()
    |> validate_password()
    |> validate_panchat_user_id()
    |> put_password_hash()
  end

  @doc "Changeset for updating a user (admin)."
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :username, :email, :role, :active, :password, :panchat_user_id])
    |> validate_required([:name, :username, :email])
    |> validate_inclusion(:role, @roles)
    |> validate_username()
    |> validate_email()
    |> validate_panchat_user_id()
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

  @doc "Changeset that only updates the interest debt (used by Interest context)."
  def interest_debt_changeset(user, new_interest_debt) do
    change(user, interest_debt: new_interest_debt)
  end

  @doc """
  Changeset cập nhật đồng thời số dư và nợ lãi (dùng khi nạp tiền: trừ nợ lãi
  trước, phần còn lại vào balance).
  """
  def settle_changeset(user, new_balance, new_interest_debt) do
    change(user, balance: new_balance, interest_debt: new_interest_debt)
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

  # Panchat user_id là tùy chọn: chuỗi rỗng -> nil; nếu có thì phải đúng dạng UUID.
  defp validate_panchat_user_id(changeset) do
    changeset
    |> update_change(:panchat_user_id, fn
      nil -> nil
      value -> if String.trim(value) == "", do: nil, else: String.trim(value)
    end)
    |> validate_format(:panchat_user_id, @uuid_regex, message: "phải là UUID Panchat hợp lệ")
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
