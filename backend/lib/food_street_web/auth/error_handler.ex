defmodule FoodStreetWeb.Auth.ErrorHandler do
  @moduledoc "Trả lỗi 401 khi xác thực Guardian thất bại."
  import Plug.Conn
  @behaviour Guardian.Plug.ErrorHandler

  @impl true
  def auth_error(conn, {type, _reason}, _opts) do
    body = Jason.encode!(%{error: "unauthorized", reason: to_string(type)})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
  end
end
