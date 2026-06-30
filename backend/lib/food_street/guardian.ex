defmodule FoodStreet.Guardian do
  use Guardian, otp_app: :food_street

  alias FoodStreet.Accounts

  @impl true
  def subject_for_token(%{id: id}, _claims), do: {:ok, to_string(id)}
  def subject_for_token(_, _), do: {:error, :invalid_resource}

  @impl true
  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_), do: {:error, :invalid_claims}

  @doc "Tạo JWT cho user kèm role trong claims."
  def create_token(user) do
    {:ok, token, _claims} =
      encode_and_sign(user, %{"role" => user.role, "name" => user.name})

    token
  end
end
