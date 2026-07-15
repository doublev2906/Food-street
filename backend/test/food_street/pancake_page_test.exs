defmodule FoodStreet.PancakePageTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.PancakePage
  alias FoodStreet.Catalog.Category

  describe "post_message/4 — HTTP request pages.fm" do
    test "POST đúng URL, token qua query param, body reply_inbox" do
      test_pid = self()

      Req.Test.stub(FoodStreet.PancakePage, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.method, conn.request_path, conn.query_string, Jason.decode!(raw)}
        )

        Req.Test.json(conn, %{"success" => true, "id" => "m1"})
      end)

      assert {:ok, %{"success" => true}} =
               PancakePage.post_message("p1", "c1", "tok", "5 Xôi xéo")

      assert_received {:req, "POST", path, qs, body}
      assert path == "/api/public_api/v1/pages/p1/conversations/c1/messages"
      assert qs =~ "page_access_token=tok"
      assert body == %{"action" => "reply_inbox", "message" => "5 Xôi xéo"}
    end

    test "body success=false -> {:error, {:pancake, ...}}" do
      Req.Test.stub(FoodStreet.PancakePage, fn conn ->
        Req.Test.json(conn, %{"success" => false, "message" => "bad"})
      end)

      assert {:error, {:pancake, _}} = PancakePage.post_message("p", "c", "t", "x")
    end

    test "HTTP 4xx -> {:error, {:pancake, http_...}}" do
      Req.Test.stub(FoodStreet.PancakePage, fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"error" => "x"})
      end)

      assert {:error, {:pancake, "http_422"}} = PancakePage.post_message("p", "c", "t", "x")
    end
  end

  describe "send_order/2 guard cấu hình" do
    test "danh mục chưa cấu hình Pancake -> :pancake_not_configured" do
      assert {:error, :pancake_not_configured} =
               PancakePage.send_order(%Category{name: "X"}, "hi")
    end

    test "đã cấu hình -> gửi được" do
      Req.Test.stub(FoodStreet.PancakePage, fn conn ->
        Req.Test.json(conn, %{"success" => true})
      end)

      cat = %Category{
        name: "Ăn sáng",
        pancake_page_id: "p1",
        pancake_conversation_id: "c1",
        pancake_page_access_token: "tok"
      }

      assert {:ok, _} = PancakePage.send_order(cat, "5 Xôi")
    end
  end
end
