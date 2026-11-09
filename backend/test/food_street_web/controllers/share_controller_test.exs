defmodule FoodStreetWeb.ShareControllerTest do
  use FoodStreetWeb.ConnCase, async: false

  alias FoodStreet.{Accounts, Repo, SharedPages}
  alias FoodStreetWeb.ShareAuth

  setup do
    File.rm_rf!(SharedPages.dir())
    File.mkdir_p!(Path.join(SharedPages.dir(), "bao-cao"))
    on_exit(fn -> File.rm_rf!(SharedPages.dir()) end)

    {:ok, user} =
      Accounts.create_user(%{
        name: "Viewer",
        username: "viewer",
        email: "viewer@example.com",
        password: "password123",
        role: "user"
      })

    {:ok, user: user}
  end

  defp put_file(rel, content), do: File.write!(Path.join(SharedPages.dir(), rel), content)

  defp share_cookie(conn), do: conn.resp_cookies["fs_share"]

  defp cookie_for(user), do: build_conn() |> ShareAuth.put_cookie(user) |> share_cookie()

  defp authed(user), do: build_conn() |> put_req_cookie("fs_share", cookie_for(user).value)

  describe "đăng nhập" do
    test "login và /me gắn cookie HttpOnly chỉ cho /share", %{conn: conn, user: user} do
      login = post(conn, ~p"/api/login", %{"username" => "viewer", "password" => "password123"})
      assert %{path: "/share", http_only: true, same_site: "Lax"} = share_cookie(login)

      {:ok, token, _} = FoodStreet.Guardian.encode_and_sign(user)
      me = build_conn() |> put_req_header("authorization", "Bearer " <> token) |> get(~p"/api/me")
      assert %{value: cookie} = share_cookie(me)

      put_file("a.html", "<p>hi</p>")

      assert build_conn()
             |> put_req_cookie("fs_share", cookie)
             |> get("/share/a.html")
             |> response(200)
    end

    test "chưa đăng nhập / cookie giả -> redirect về /login kèm next", %{conn: conn} do
      put_file("a.html", "x")

      assert conn |> get("/share/a.html?x=1") |> redirected_to(302) ==
               "/login?next=%2Fshare%2Fa.html%3Fx%3D1"

      assert build_conn()
             |> put_req_cookie("fs_share", "gia")
             |> get("/share/")
             |> redirected_to(302) ==
               "/login?next=%2Fshare%2F"
    end

    test "tài khoản bị khoá thì cookie cũ hết tác dụng", %{user: user} do
      put_file("a.html", "x")
      cookie = cookie_for(user).value

      assert build_conn()
             |> put_req_cookie("fs_share", cookie)
             |> get("/share/a.html")
             |> response(200)

      Repo.update!(Ecto.Changeset.change(user, active: false))

      assert build_conn()
             |> put_req_cookie("fs_share", cookie)
             |> get("/share/a.html")
             |> response(302)
    end

    test "logout xoá cookie", %{conn: conn} do
      resp = post(conn, ~p"/api/logout")
      assert response(resp, 204)
      assert %{max_age: 0, path: "/share"} = share_cookie(resp)
    end
  end

  describe "serve" do
    test "HTML: chèn script ngay sau <head> kèm dữ liệu đã lưu + CSP sandbox", %{user: user} do
      put_file(
        "bao-cao/q4.html",
        ~s(<!doctype html><html><head><title>Q4</title></head><body><header>x</header></body></html>)
      )

      :ok = SharedPages.merge_state("bao-cao/q4.html", %{"f:#ten" => "</script><b>"}, nil)

      resp = user |> authed() |> get("/share/bao-cao/q4.html")
      body = html_response(resp, 200)

      assert [csp] = get_resp_header(resp, "content-security-policy")
      assert csp =~ "sandbox allow-scripts"
      refute csp =~ "allow-same-origin"
      assert get_resp_header(resp, "cache-control") == ["private, no-cache"]

      assert body =~ ~r/^<!doctype html><html><head><script>window.__FS_SHARE__=/
      assert body =~ "<title>Q4</title>"
      # Giá trị người dùng nhập không phá được thẻ <script> (escape html_safe).
      refute body =~ "</script><b>"
      assert body =~ ~s("saveUrl":"\\/api\\/share_state")
    end

    test "HTML không có <head> vẫn chèn sau doctype (không rơi vào quirks mode)", %{user: user} do
      put_file("a.html", "<!DOCTYPE html><p>x</p>")

      assert user |> authed() |> get("/share/a.html") |> html_response(200) =~
               ~r/^<!DOCTYPE html><script>/
    end

    test "thư mục: redirect thêm / , hiện danh sách, có index.html thì serve file đó", %{
      user: user
    } do
      put_file("bao-cao/<b>.html", "x")
      conn = authed(user)

      assert conn |> get("/share/bao-cao") |> redirected_to(302) == "/share/bao-cao/"

      listing = conn |> get("/share/bao-cao/") |> html_response(200)
      assert listing =~ ~s(href="/share/bao-cao/%3Cb%3E.html")
      assert listing =~ "&lt;b&gt;.html"
      refute listing =~ "<b>.html"

      root = conn |> get("/share/") |> html_response(200)
      assert root =~ ~s(href="/share/bao-cao/")

      put_file("bao-cao/index.html", "<head></head>INDEX")
      assert conn |> get("/share/bao-cao/") |> html_response(200) =~ "INDEX"
    end

    test "file không phải HTML trả nguyên, không chèn script", %{user: user} do
      put_file("bao-cao/style.css", "body{color:red}")
      resp = user |> authed() |> get("/share/bao-cao/style.css")
      assert response(resp, 200) == "body{color:red}"
      assert [ct] = get_resp_header(resp, "content-type")
      assert ct =~ "text/css"
    end

    test "404 cho file không có, file ẩn, path traversal", %{user: user} do
      put_file(".secret", "x")
      conn = authed(user)
      assert conn |> get("/share/khong-co.html") |> response(404)
      assert conn |> get("/share/.secret") |> response(404)
      assert conn |> get("/share/..%2F..%2Fmix.exs") |> response(404)
    end
  end
end
