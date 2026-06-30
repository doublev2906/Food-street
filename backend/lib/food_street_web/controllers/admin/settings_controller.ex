defmodule FoodStreetWeb.Admin.SettingsController do
  @moduledoc "Admin cấu hình hệ thống — hiện chỉ có Panchat token."
  use FoodStreetWeb, :controller

  alias FoodStreet.Settings

  action_fallback FoodStreetWeb.FallbackController

  # Trạng thái Panchat token — KHÔNG trả full token, chỉ trả preview 4 ký tự cuối.
  def show(conn, _params) do
    json(conn, %{data: panchat_status()})
  end

  def update(conn, params) do
    token = params["panchat_token"] || params["token"] || ""

    if String.trim(token) == "" do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "empty_token", message: "Token không được để trống."})
    else
      with {:ok, _} <- Settings.put_panchat_token(String.trim(token)) do
        json(conn, %{data: panchat_status()})
      end
    end
  end

  defp panchat_status do
    token = Settings.panchat_token()

    %{
      panchat_configured: Settings.panchat_configured?(),
      panchat_token_preview: mask(token)
    }
  end

  defp mask(nil), do: ""
  defp mask(""), do: ""

  defp mask(token) when is_binary(token) do
    last4 = token |> String.slice(-4, 4)
    "••••" <> (last4 || "")
  end
end
