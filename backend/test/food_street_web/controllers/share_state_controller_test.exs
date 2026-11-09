defmodule FoodStreetWeb.ShareStateControllerTest do
  use FoodStreetWeb.ConnCase, async: true

  alias FoodStreet.{Accounts, Repo, SharedPages}
  alias FoodStreetWeb.ShareController

  setup do
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

  defp token(user, page),
    do:
      Phoenix.Token.sign(FoodStreetWeb.Endpoint, ShareController.state_salt(), %{
        "p" => page,
        "u" => user.id
      })

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

    assert Repo.get_by!(SharedPages.State, page_path: "bao-cao/q4.html").updated_by_id == user.id
  end

  test "token giả / user bị khoá -> 401; patch sai kiểu -> 422; body hỏng -> 400",
       %{user: user} do
    assert save(%{"token" => "gia", "patch" => %{"a" => "b"}}) |> json_response(401)

    assert save(%{"token" => token(user, "a.html"), "patch" => %{"a" => %{"x" => 1}}})
           |> json_response(422)

    assert build_conn()
           |> put_req_header("content-type", "text/plain")
           |> post(~p"/api/share_state", "not json")
           |> json_response(400)

    t = token(user, "a.html")
    Repo.update!(Ecto.Changeset.change(user, active: false))
    assert save(%{"token" => t, "patch" => %{"a" => "b"}}) |> json_response(401)
  end
end
