defmodule FoodStreetWeb.ShareStateController do
  @moduledoc """
  Lưu dữ liệu người xem nhập trên trang `/share/*` (gọi từ `priv/share/inject.js`).

  Trang chạy trong CSP sandbox (origin `null`) nên request không mang cookie; xác thực
  bằng token ký sẵn (trang + user) mà `ShareController` nhúng vào lúc trả trang. Body là
  JSON gửi dạng `text/plain` (simple request, không preflight):

      {"token": "...", "patch": {"f:#ghi-chu": "abc", "ls:theme": null}}
  """
  use FoodStreetWeb, :controller

  alias FoodStreet.{Accounts, SharedPages}
  alias FoodStreetWeb.ShareController

  @max_body 1_000_000

  def save(conn, _params) do
    # Origin sandbox là "null" -> cho phép đọc response (không dùng cookie nên an toàn).
    conn = put_resp_header(conn, "access-control-allow-origin", "*")

    with {:ok, %{"token" => token, "patch" => patch}, conn} <- read_payload(conn),
         {:ok, %{"p" => page_path, "u" => user_id}} <-
           Phoenix.Token.verify(FoodStreetWeb.Endpoint, ShareController.state_salt(), token,
             max_age: ShareController.state_max_age()
           ),
         %{active: true} <- Accounts.get_user(user_id),
         :ok <- SharedPages.merge_state(page_path, patch, user_id) do
      json(conn, %{ok: true})
    else
      {:error, :too_large} ->
        error(conn, 413, "payload_too_large")

      {:error, :invalid_patch} ->
        error(conn, 422, "invalid_patch")

      {:error, reason} when reason in [:expired, :invalid, :missing] ->
        error(conn, 401, "invalid_token")

      %{active: false} ->
        error(conn, 401, "invalid_token")

      nil ->
        error(conn, 401, "invalid_token")

      _ ->
        error(conn, 400, "bad_request")
    end
  end

  # JSON gửi kèm Content-Type application/json thì Plug.Parsers đã parse sẵn; text/plain
  # (mặc định của fetch khi body là chuỗi) thì tự đọc body.
  defp read_payload(%{body_params: %{"token" => _} = params} = conn), do: {:ok, params, conn}

  defp read_payload(conn) do
    case read_body(conn, length: @max_body) do
      {:ok, body, conn} ->
        case Jason.decode(body) do
          {:ok, %{} = payload} -> {:ok, payload, conn}
          _ -> {:error, :bad_json}
        end

      {:more, _, _} ->
        {:error, :too_large}

      {:error, _} ->
        {:error, :bad_body}
    end
  end

  defp error(conn, status, code) do
    conn |> put_status(status) |> json(%{error: code})
  end
end
