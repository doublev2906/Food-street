defmodule FoodStreet.PancakeInboundTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.{PancakeInbound, Catalog, Accounts, Settings}

  # ---- helpers ----

  defp make_category(attrs \\ %{}) do
    {:ok, cat} =
      Catalog.create_category(
        Map.merge(
          %{
            name: "Ăn sáng",
            pancake_page_id: "p1",
            pancake_conversation_id: "conv1",
            pancake_page_access_token: "ptok"
          },
          attrs
        )
      )

    cat
  end

  defp make_admin_with_token(username, token) do
    {:ok, admin} =
      Accounts.create_user(%{
        name: "Admin #{username}",
        username: username,
        email: "#{username}@example.com",
        password: "password123",
        role: "admin"
      })

    {:ok, _} = Settings.put_panchat_token(admin.id, token)
    admin
  end

  defp stub_panchat! do
    test_pid = self()

    Req.Test.stub(FoodStreet.Panchat, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:panchat, Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(raw)}
      )

      Req.Test.json(conn, %{"success" => true})
    end)
  end

  # Payload webhook messaging từ nhà bán (INBOX, from != page).
  defp inbox_payload(overrides \\ %{}) do
    msg =
      Map.merge(
        %{"id" => "msg1", "message" => "hết xôi rồi", "from" => %{"id" => "cust1"}},
        overrides[:message] || %{}
      )

    conv = Map.merge(%{"id" => "conv1", "type" => "INBOX"}, overrides[:conversation] || %{})

    %{
      "event_type" => Map.get(overrides, :event_type, "messaging"),
      "page_id" => "p1",
      "data" => %{"conversation" => conv, "message" => msg}
    }
  end

  # ---- relay_text ----

  describe "relay_text/2" do
    test "gồm tên danh mục + nội dung nhà bán + nhắc đổi đơn" do
      cat = make_category()
      text = PancakeInbound.relay_text(cat, %{text: "hết xôi"})

      assert text =~ ~s(Nhà bán "Ăn sáng")
      assert text =~ "hết xôi"
      assert text =~ "đặt lại đơn"
    end
  end

  # ---- handle_messaging ----

  describe "handle_messaging/1 — relay tin nhà bán" do
    test "tin INBOX từ nhà bán → relay Panchat với token admin" do
      make_category()
      make_admin_with_token("admina", "bearer-tok")
      stub_panchat!()

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, ["Bearer bearer-tok"], body}
      # nội dung relay có tên danh mục
      assert inspect(body) =~ "Ăn sáng"
    end

    test "dedup: cùng message_id chỉ relay 1 lần" do
      make_category()
      make_admin_with_token("admina", "tok")
      stub_panchat!()

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert {:skip, :duplicate} = PancakeInbound.handle_messaging(inbox_payload())
    end
  end

  describe "handle_messaging/1 — bỏ qua" do
    test "tin của chính page (outbound của ta) → :own_message" do
      make_category()
      make_admin_with_token("admina", "tok")

      payload = inbox_payload(%{message: %{"from" => %{"id" => "p1"}}})
      assert {:skip, :own_message} = PancakeInbound.handle_messaging(payload)
    end

    test "không phải INBOX (COMMENT) → :not_inbox" do
      make_category()
      payload = inbox_payload(%{conversation: %{"type" => "COMMENT"}})
      assert {:skip, :not_inbox} = PancakeInbound.handle_messaging(payload)
    end

    test "conversation không map được danh mục → :no_category" do
      make_category(%{pancake_conversation_id: "khac"})
      make_admin_with_token("admina", "tok")

      assert {:skip, :no_category} = PancakeInbound.handle_messaging(inbox_payload())
    end

    test "event_type khác messaging → :not_messaging" do
      assert {:skip, :not_messaging} =
               PancakeInbound.handle_messaging(inbox_payload(%{event_type: "post"}))
    end

    test "text rỗng → :empty_text" do
      make_category()
      payload = inbox_payload(%{message: %{"message" => "   "}})
      assert {:skip, :empty_text} = PancakeInbound.handle_messaging(payload)
    end
  end

  describe "handle_messaging/1 — lỗi" do
    test "không admin nào cấu hình token → :no_admin_token (không đánh dấu đã xử lý)" do
      make_category()
      # không tạo admin có token

      assert {:error, :no_admin_token} = PancakeInbound.handle_messaging(inbox_payload())

      # relay lỗi → chưa đánh dấu → lần sau (khi có token) vẫn relay lại được
      make_admin_with_token("admina", "tok")
      stub_panchat!()
      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
    end
  end
end
