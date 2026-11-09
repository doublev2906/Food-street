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
  end

  test "tạo thư mục, upload vào thư mục, list, xoá", %{conn: conn} do
    conn = login(conn, "admin")

    assert %{"data" => %{"path" => "bao-cao", "type" => "folder"}} =
             conn
             |> post(~p"/api/admin/shared_pages/folders", %{"dir" => "", "name" => "Báo cáo"})
             |> json_response(201)

    assert %{"error" => "already_exists"} =
             conn
             |> post(~p"/api/admin/shared_pages/folders", %{"name" => "bao cao"})
             |> json_response(422)

    resp =
      conn
      |> post(~p"/api/admin/shared_pages", %{
        "dir" => "bao-cao",
        "files" => [upload("Kế hoạch.html", "<p>ok</p>"), upload("evil.js", "x")]
      })
      |> json_response(201)

    assert [%{"path" => "bao-cao/ke-hoach.html", "url" => "/share/bao-cao/ke-hoach.html"}] =
             resp["data"]

    assert [%{"name" => "evil.js", "error" => _}] = resp["errors"]

    assert %{"dir" => "bao-cao", "folders" => [], "files" => [%{"name" => "ke-hoach.html"}]} =
             conn
             |> get(~p"/api/admin/shared_pages?dir=bao-cao")
             |> json_response(200)
             |> Map.get("data")

    assert %{"folders" => [%{"name" => "bao-cao"}]} =
             conn |> get(~p"/api/admin/shared_pages") |> json_response(200) |> Map.get("data")

    assert conn |> get(~p"/api/admin/shared_pages?dir=../etc") |> json_response(404)

    assert conn |> delete(~p"/api/admin/shared_pages?path=bao-cao") |> response(204)
    assert {:ok, %{folders: []}} = SharedPages.list()
    assert conn |> delete(~p"/api/admin/shared_pages?path=bao-cao") |> json_response(404)
  end

  test "trùng tên: mặc định báo lỗi, overwrite=true thì ghi đè", %{conn: conn} do
    conn = login(conn, "admin")
    post(conn, ~p"/api/admin/shared_pages", %{"files" => [upload("a.html", "v1")]})

    assert %{"error" => "upload_failed", "errors" => [%{"error" => msg}]} =
             conn
             |> post(~p"/api/admin/shared_pages", %{"files" => [upload("a.html", "v2")]})
             |> json_response(422)

    assert msg =~ "Ghi đè"

    assert %{"data" => [%{"replaced" => true}]} =
             conn
             |> post(~p"/api/admin/shared_pages", %{
               "files" => [upload("a.html", "v2")],
               "overwrite" => "true"
             })
             |> json_response(201)

    assert File.read!(Path.join(SharedPages.dir(), "a.html")) == "v2"
  end

  test "không gửi file → 422", %{conn: conn} do
    assert %{"error" => "no_files"} =
             conn
             |> login("admin")
             |> post(~p"/api/admin/shared_pages", %{})
             |> json_response(422)
  end
end
