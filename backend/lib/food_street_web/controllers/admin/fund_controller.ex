defmodule FoodStreetWeb.Admin.FundController do
  use FoodStreetWeb, :controller

  alias FoodStreet.Fund
  alias FoodStreet.Accounts
  alias FoodStreet.Guardian

  action_fallback FoodStreetWeb.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Fund.list_transactions()})
  end

  def deposit(conn, %{"user_id" => user_id, "amount" => amount} = params) do
    admin = Guardian.Plug.current_resource(conn)

    case Accounts.get_user(user_id) do
      nil ->
        {:error, :not_found}

      user ->
        with {:ok, result} <- Fund.deposit(user, amount, admin, params["description"]) do
          conn |> put_status(:created) |> json(%{data: result})
        end
    end
  end

  def deposit(_conn, _params), do: {:error, :missing_params}

  def adjust(conn, %{"user_id" => user_id, "amount" => amount} = params) do
    admin = Guardian.Plug.current_resource(conn)

    case Accounts.get_user(user_id) do
      nil ->
        {:error, :not_found}

      user ->
        with {:ok, result} <- Fund.adjust(user, amount, admin, params["description"]) do
          conn |> put_status(:created) |> json(%{data: result})
        end
    end
  end

  def adjust(_conn, _params), do: {:error, :missing_params}
end
