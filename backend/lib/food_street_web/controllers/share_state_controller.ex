defmodule FoodStreetWeb.ShareStateController do
  @moduledoc """
  Lưu dữ liệu người xem nhập trên trang `/share/*` (gọi từ `priv/share/inject.js`).

  Trang chạy trong CSP sandbox (origin `null`) nên request không mang cookie; xác thực
  bằng token ký sẵn (trang + user) mà `ShareController` nhúng vào lúc trả trang. Trang
  `/share` công khai nên ai mở được trang cũng lưu được (kể cả chưa đăng nhập); user trong
  token chỉ để ghi nhận người sửa cuối. Body là JSON gửi dạng `text/plain` (simple
  request, không preflight):

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
         {:ok, %{"p" => page_path} = claims} <-
           Phoenix.Token.verify(FoodStreetWeb.Endpoint, ShareController.state_salt(), token,
             max_age: ShareController.state_max_age()
           ),
         # Token gắn đường dẫn lúc mở trang: trang đã đổi tên / xoá thì không ghi tiếp, kẻo
         # dữ liệu nằm ở đường dẫn cũ (mất, hoặc dính sang file sau này upload trùng tên).
         :ok <- if(SharedPages.page?(page_path), do: :ok, else: {:error, :page_gone}),
         :ok <- SharedPages.merge_state(page_path, patch, editor_id(claims["u"])) do
      json(conn, %{ok: true})
    else
      {:error, :too_large} ->
        error(conn, 413, "payload_too_large")

      {:error, :page_gone} ->
        error(conn, 410, "page_gone")

      {:error, :invalid_patch} ->
        error(conn, 422, "invalid_patch")

      {:error, reason} when reason in [:expired, :invalid, :missing] ->
        error(conn, 401, "invalid_token")

      _ ->
        error(conn, 400, "bad_request")
    end
  end

  # Người sửa: user còn hoạt động thì ghi nhận, khách / tài khoản đã khoá hay xoá thì nil
  # (vẫn lưu như khách — trang công khai; nil cũng tránh lỗi khoá ngoại khi user đã xoá).
  defp editor_id(nil), do: nil

  defp editor_id(user_id) do
    case Accounts.get_user(user_id) do
      %{active: true, id: id} -> id
      _ -> nil
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
