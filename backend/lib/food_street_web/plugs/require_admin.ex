defmodule FoodStreetWeb.Plugs.RequireAdmin do
  @moduledoc "Chỉ cho phép user có role admin đi tiếp."
  import Plug.Conn

  alias FoodStreet.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      %{role: "admin"} ->
        conn

      _ ->
        body = Jason.encode!(%{error: "forbidden", reason: "admin_required"})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, body)
        |> halt()
    end
  end
end
