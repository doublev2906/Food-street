defmodule FoodStreetWeb.Admin.SharedPageControllerTest do
  use FoodStreetWeb.ConnCase, async: false

  alias FoodStreet.{Accounts, Guardian, SharedPages}

  setup %{conn: conn} do
    File.rm_rf!(SharedPages.dir())
    on_exit(fn -> File.rm_rf!(SharedPages.dir()) end)
    {:ok, conn: conn}
  end

  defp login(conn, role) do
    {:ok, user} =
      Accounts.create_user(%{
        name: "share-#{role}",
        username: "share_#{role}",
        email: "share_#{role}@example.com",
        password: "password123",
        role: role
      })

    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp upload(filename, content) do
    path = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: filename, content_type: "text/html"}
  end

  test "user thường không được upload", %{conn: conn} do
    conn =
      conn
      |> login("user")
      |> post(~p"/api/admin/shared_pages", %{"files" => [upload("a.html", "x")]})

    assert json_response(conn, 403)
    assert SharedPages.list() == []
  end

  test "admin upload nhiều file: file hợp lệ được lưu, file sai báo lỗi riêng", %{conn: conn} do
    conn = login(conn, "admin")

    resp =
      conn
      |> post(~p"/api/admin/shared_pages", %{
        "files" => [upload("Kế hoạch.html", "<p>ok</p>"), upload("evil.js", "x")]
      })
      |> json_response(201)

    assert [%{"name" => "ke-hoach.html", "url" => "/share/ke-hoach.html"}] = resp["data"]
    assert [%{"name" => "evil.js", "error" => _}] = resp["errors"]

    assert [%{"name" => "ke-hoach.html"}] =
             conn |> get(~p"/api/admin/shared_pages") |> json_response(200) |> Map.get("data")

    assert conn |> delete(~p"/api/admin/shared_pages/ke-hoach.html") |> response(204)
    assert SharedPages.list() == []
    assert conn |> delete(~p"/api/admin/shared_pages/ke-hoach.html") |> json_response(404)
  end

  test "tất cả file đều lỗi hoặc không gửi file → 422", %{conn: conn} do
    conn = login(conn, "admin")

    assert %{"error" => "upload_failed"} =
             conn
             |> post(~p"/api/admin/shared_pages", %{"files" => [upload("a.txt", "x")]})
             |> json_response(422)

    assert %{"error" => "no_files"} =
             conn |> post(~p"/api/admin/shared_pages", %{}) |> json_response(422)
  end
end
