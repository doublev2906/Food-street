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
    |> json(%{error: to_string(reason), message: message(reason)})
  end

  def call(conn, nil) do
    conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end

  defp message(:order_not_editable), do: "Đơn đã chốt, không sửa được."
  defp message(:group_not_open), do: "Đợt đã đóng, không thao tác được."
  defp message(:empty_items), do: "Hãy chọn ít nhất 1 món."
  defp message(:invalid_items), do: "Có món không hợp lệ hoặc không thuộc danh mục của đợt."
  defp message(reason), do: to_string(reason)

  defp translate_errors(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
