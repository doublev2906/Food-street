defmodule FoodStreetWeb.FallbackController do
  use FoodStreetWeb, :controller

  alias Ecto.Changeset

  # Lỗi validation từ changeset
  def call(conn, {:error, %Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_failed", details: translate_errors(changeset)})
  end

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: to_string(reason)})
  end

  def call(conn, nil) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end

  defp translate_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
