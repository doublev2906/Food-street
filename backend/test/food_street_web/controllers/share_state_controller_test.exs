defmodule FoodStreetWeb.ShareStateControllerTest do
  # Chỉ lưu được cho trang còn file -> dùng chung folder tạm :share_dir nên không async.
  use FoodStreetWeb.ConnCase, async: false

  alias FoodStreet.{Accounts, Repo, SharedPages}
  alias FoodStreetWeb.ShareController

  setup do
    File.rm_rf!(SharedPages.dir())
    on_exit(fn -> File.rm_rf!(SharedPages.dir()) end)
    File.mkdir_p!(Path.join(SharedPages.dir(), "bao-cao"))
    File.write!(Path.join(SharedPages.dir(), "bao-cao/q4.html"), "<p>q4</p>")
    File.write!(Path.join(SharedPages.dir(), "a.html"), "<p>a</p>")

    {:ok, user} =
      Accounts.create_user(%{
        name: "Editor",
        username: "editor",
        email: "editor@example.com",
        password: "password123",
        role: "user"
      })

    {:ok, user: user}
  end

  # user nil = khách chưa đăng nhập (trang /share công khai).
  defp token(user, page),
    do:
      Phoenix.Token.sign(FoodStreetWeb.Endpoint, ShareController.state_salt(), %{
        "p" => page,
        "u" => user && user.id
      })

  defp updated_by(page), do: Repo.get_by!(SharedPages.State, page_path: page).updated_by_id

  # Như fetch() từ trang sandbox: body chuỗi JSON, Content-Type text/plain, Origin null.
  defp save(body) do
    build_conn()
    |> put_req_header("content-type", "text/plain;charset=UTF-8")
    |> put_req_header("origin", "null")
    |> post(~p"/api/share_state", Jason.encode!(body))
  end

  test "token hợp lệ -> gộp dữ liệu, cho phép đọc response từ origin null", %{user: user} do
    t = token(user, "bao-cao/q4.html")

    resp = save(%{"token" => t, "patch" => %{"f:#ten" => "An", "ls:theme" => "dark"}})
    assert json_response(resp, 200) == %{"ok" => true}
    assert get_resp_header(resp, "access-control-allow-origin") == ["*"]

    save(%{"token" => t, "patch" => %{"ls:theme" => nil}})
    assert SharedPages.get_state("bao-cao/q4.html") == %{"f:#ten" => "An"}

    assert updated_by("bao-cao/q4.html") == user.id
  end

  test "khách chưa đăng nhập lưu được, ghi đè người sửa = nil", %{user: user} do
    save(%{"token" => token(user, "a.html"), "patch" => %{"f:#ten" => "An"}})
    assert updated_by("a.html") == user.id

    assert save(%{"token" => token(nil, "a.html"), "patch" => %{"f:#tuoi" => "20"}})
           |> json_response(200)

    assert SharedPages.get_state("a.html") == %{"f:#ten" => "An", "f:#tuoi" => "20"}
    assert updated_by("a.html") == nil
  end

  test "user bị khoá / đã xoá -> vẫn lưu như khách (không ghi người sửa)", %{user: user} do
    t = token(user, "a.html")
    Repo.update!(Ecto.Changeset.change(user, active: false))
    assert save(%{"token" => t, "patch" => %{"a" => "b"}}) |> json_response(200)
    assert updated_by("a.html") == nil

    Repo.delete!(user)
    assert save(%{"token" => t, "patch" => %{"a" => "c"}}) |> json_response(200)
    assert SharedPages.get_state("a.html") == %{"a" => "c"}
  end

  test "token giả -> 401; patch sai kiểu -> 422; body hỏng -> 400", %{user: user} do
    assert save(%{"token" => "gia", "patch" => %{"a" => "b"}}) |> json_response(401)

    assert save(%{"token" => token(user, "a.html"), "patch" => %{"a" => %{"x" => 1}}})
           |> json_response(422)

    assert build_conn()
           |> put_req_header("content-type", "text/plain")
           |> post(~p"/api/share_state", "not json")
           |> json_response(400)
  end

  test "trang đã đổi tên / xoá -> 410, không để lại dữ liệu ở đường dẫn cũ", %{user: user} do
    t = token(user, "a.html")
    {:ok, _} = SharedPages.rename("a.html", "b")

    assert %{"error" => "page_gone"} =
             save(%{"token" => t, "patch" => %{"k" => "v"}}) |> json_response(410)

    assert SharedPages.get_state("a.html") == %{}

    assert save(%{"token" => token(user, "khong-co.html"), "patch" => %{"k" => "v"}})
           |> json_response(410)
  end
end
