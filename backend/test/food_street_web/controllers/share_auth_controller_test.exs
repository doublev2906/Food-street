defmodule FoodStreetWeb.ShareAuthControllerTest do
  use FoodStreetWeb.ConnCase, async: true

  alias FoodStreet.{Accounts, Guardian, Repo}

  defp make_user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.create_user(
        Map.merge(
          %{
            name: "Viewer",
            username: "viewer",
            email: "viewer@example.com",
            password: "password123",
            role: "user"
          },
          attrs
        )
      )

    user
  end

  defp share_cookie(conn), do: conn.resp_cookies["fs_share"]

  defp check(conn, cookie, uri \\ "/share/bao-cao.html") do
    conn
    |> put_req_header("x-forwarded-uri", uri)
    |> then(&if cookie, do: put_req_cookie(&1, "fs_share", cookie), else: &1)
    |> get(~p"/api/share_auth")
  end

  test "đăng nhập gắn cookie HttpOnly chỉ cho /share, cookie đó qua được share_auth",
       %{conn: conn} do
    make_user()

    login = post(conn, ~p"/api/login", %{"username" => "viewer", "password" => "password123"})
    assert json_response(login, 200)["token"]

    assert %{value: cookie, path: "/share", http_only: true, same_site: "Lax"} =
             share_cookie(login)

    assert build_conn() |> check(cookie) |> response(204)
  end

  test "/api/me làm mới cookie cho phiên đăng nhập cũ (chưa có cookie)", %{conn: conn} do
    user = make_user()
    {:ok, token, _} = Guardian.encode_and_sign(user)

    me = conn |> put_req_header("authorization", "Bearer " <> token) |> get(~p"/api/me")
    assert %{value: cookie} = share_cookie(me)
    assert build_conn() |> check(cookie) |> response(204)
  end

  test "chưa đăng nhập -> redirect về /login kèm next là trang đang mở", %{conn: conn} do
    resp = check(conn, nil, "/share/bao-cao.html")
    assert redirected_to(resp, 302) == "/login?next=%2Fshare%2Fbao-cao.html"
  end

  test "next ngoài /share bị bỏ (chống open redirect), cookie giả bị từ chối", %{conn: conn} do
    assert conn |> check("gia-mao", "//evil.com/x") |> redirected_to(302) ==
             "/login?next=%2Fshare%2F"
  end

  test "tài khoản bị khoá thì cookie cũ hết tác dụng", %{conn: conn} do
    user = make_user()
    cookie = conn |> FoodStreetWeb.ShareAuth.put_cookie(user) |> share_cookie() |> Map.get(:value)

    assert build_conn() |> check(cookie) |> response(204)

    Repo.update!(Ecto.Changeset.change(user, active: false))
    assert build_conn() |> check(cookie) |> redirected_to(302) =~ "/login?next="
  end

  test "logout xoá cookie", %{conn: conn} do
    resp = post(conn, ~p"/api/logout")
    assert response(resp, 204)
    assert %{max_age: 0, path: "/share"} = share_cookie(resp)
  end
end
