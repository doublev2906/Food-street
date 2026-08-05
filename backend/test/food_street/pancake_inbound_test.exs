defmodule FoodStreet.PancakeInboundTest do
  # async: false — relay dùng token bot đọc từ Application env; test "no bot token"
  # tạm xoá env đó (toàn cục) nên module chạy tuần tự để tránh đua.
  use FoodStreet.DataCase, async: false

  alias FoodStreet.{PancakeInbound, Catalog, Accounts, Settings, Ordering}

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

  # Stub Gemini trả về envelope generateContent với `map` (intent/items) là JSON.
  defp stub_gemini!(map) do
    Req.Test.stub(FoodStreet.Gemini, fn conn ->
      Req.Test.json(conn, %{
        "candidates" => [%{"content" => %{"parts" => [%{"text" => Jason.encode!(map)}]}}]
      })
    end)
  end

  # Mặc định OTHER → giữ hành vi relay nguyên văn (cho các test không kiểm phân loại).
  defp stub_gemini_other!, do: stub_gemini!(%{"intent" => "OTHER", "items" => []})

  # Gemini trả 5xx → classify {:error, _} → fallback relay + note lỗi.
  defp stub_gemini_error! do
    Req.Test.stub(FoodStreet.Gemini, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)
  end

  defp make_user(username, attrs \\ %{}) do
    {:ok, u} =
      Accounts.create_user(
        Map.merge(
          %{
            name: username,
            username: username,
            email: "#{username}@example.com",
            password: "password123",
            role: "user"
          },
          attrs
        )
      )

    u
  end

  # Đợt đang mở của `cat` + 1 món tên `item_name`. Trả {group_order, menu_item}.
  defp open_group_with_item(cat, admin, item_name) do
    {:ok, mi} =
      Catalog.create_menu_item(%{
        name: item_name,
        price: "20000",
        category_id: cat.id,
        available: true
      })

    {:ok, go} =
      Ordering.create_group_order(
        %{"title" => "Sáng", "order_date" => "2026-07-02", "category_id" => cat.id},
        admin
      )

    {go, mi}
  end

  defp order_item(user, go, mi, qty \\ 1) do
    {:ok, _} =
      Ordering.place_order_in_group(user, go.id, %{
        "items" => [%{"menu_item_id" => mi.id, "quantity" => qty}]
      })
  end

  # Payload webhook messaging từ nhà bán (INBOX, from != page).
  defp inbox_payload(overrides \\ %{}) do
    msg =
      Map.merge(
        %{
          "id" => "msg1",
          "message" => "hết xôi rồi",
          "original_message" => "hết xôi rồi",
          "from" => %{"id" => "cust1"}
        },
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

      assert text =~ ~s(Nhà bán hàng "Ăn sáng")
      assert text =~ "hết xôi"
      refute text =~ "đặt lại đơn"
    end
  end

  # ---- handle_messaging ----

  describe "handle_messaging/1 — relay tin nhà bán" do
    test "tin INBOX từ nhà bán → relay Panchat bằng token BOT (không cần admin token)" do
      make_category()
      stub_panchat!()
      stub_gemini_other!()

      bot = Application.get_env(:food_street, :panchat_bot_token)

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, auth, body}
      assert auth == ["Bearer #{bot}"]
      # nội dung relay có tên danh mục
      assert inspect(body) =~ "Ăn sáng"
    end

    test "dedup: cùng message_id chỉ relay 1 lần" do
      make_category()
      stub_panchat!()
      stub_gemini_other!()

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert {:skip, :duplicate} = PancakeInbound.handle_messaging(inbox_payload())
    end

    test "ưu tiên original_message thay vì message" do
      make_category()
      stub_panchat!()
      stub_gemini_other!()

      payload =
        inbox_payload(%{
          message: %{"message" => "bản rút gọn", "original_message" => "nội dung gốc đầy đủ"}
        })

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(payload)
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "nội dung gốc đầy đủ"
      refute inspect(body) =~ "bản rút gọn"
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
      payload = inbox_payload(%{message: %{"message" => "   ", "original_message" => "   "}})
      assert {:skip, :empty_text} = PancakeInbound.handle_messaging(payload)
    end
  end

  describe "handle_messaging/1 — lỗi" do
    test "chưa cấu hình bot token → :no_bot_token (không đánh dấu đã xử lý)" do
      make_category()

      prev = Application.get_env(:food_street, :panchat_bot_token)
      Application.delete_env(:food_street, :panchat_bot_token)
      on_exit(fn -> Application.put_env(:food_street, :panchat_bot_token, prev) end)

      assert {:error, :no_bot_token} = PancakeInbound.handle_messaging(inbox_payload())

      # chưa đánh dấu → sau khi cấu hình bot token vẫn relay lại được (không mất tin)
      Application.put_env(:food_street, :panchat_bot_token, prev)
      stub_panchat!()
      stub_gemini_other!()
      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
    end
  end

  describe "handle_messaging/1 — phân loại Gemini → hành động" do
    test "OUT_OF_STOCK: ping người đã đặt món hết, mention thật khi có UUID" do
      cat = make_category()
      admin = make_admin_with_token("admina", "tok")
      stub_panchat!()

      {go, mi} = open_group_with_item(cat, admin, "Xôi")
      eater = make_user("annie", %{panchat_user_id: "33333333-3333-3333-3333-333333333333"})
      order_item(eater, go, mi)

      stub_gemini!(%{"intent" => "OUT_OF_STOCK", "items" => ["Xôi"]})

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "hết Xôi rồi"
      assert inspect(body) =~ "đổi lại giúp mình"
      assert inspect(body) =~ "@annie"
      assert inspect(body) =~ "33333333-3333-3333-3333-333333333333"
    end

    test "OUT_OF_STOCK nhưng không ai đặt món đó → relay nguyên văn" do
      cat = make_category()
      admin = make_admin_with_token("admina", "tok")
      stub_panchat!()

      {go, mi} = open_group_with_item(cat, admin, "Xôi")
      order_item(make_user("annie"), go, mi)

      # Gemini báo hết "Phở" — không ai đặt món này.
      stub_gemini!(%{"intent" => "OUT_OF_STOCK", "items" => ["Phở"]})

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "phản hồi"
      refute inspect(body) =~ "đổi lại giúp mình"
    end

    test "READY_FOR_PICKUP: ping đúng nhóm runners đã lưu" do
      cat = make_category()
      admin = make_admin_with_token("admina", "tok")
      stub_panchat!()

      {go, _mi} = open_group_with_item(cat, admin, "Xôi")
      runner = make_user("runna", %{panchat_user_id: "44444444-4444-4444-4444-444444444444"})
      {:ok, _} = Ordering.set_runners(go, [runner])

      stub_gemini!(%{"intent" => "READY_FOR_PICKUP", "items" => []})

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "Người bán đã ship rồi"
      assert inspect(body) =~ "đi lấy đồ giúp mọi người"
      assert inspect(body) =~ "@runna"
      assert inspect(body) =~ "44444444-4444-4444-4444-444444444444"
    end

    test "READY_FOR_PICKUP nhưng chưa bốc runners → relay nguyên văn" do
      cat = make_category()
      admin = make_admin_with_token("admina", "tok")
      stub_panchat!()
      open_group_with_item(cat, admin, "Xôi")

      stub_gemini!(%{"intent" => "READY_FOR_PICKUP", "items" => []})

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "phản hồi"
      refute inspect(body) =~ "Người bán đã ship rồi"
    end

    test "PAYMENT: relay nội dung + nhắc admin chuyển khoản, KHÔNG tag @all" do
      make_category()
      make_admin_with_token("admina", "tok")
      stub_panchat!()

      stub_gemini!(%{"intent" => "PAYMENT", "items" => []})

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "báo thanh toán"
      assert inspect(body) =~ "chuyển khoản"
      refute inspect(body) =~ "@all"
    end

    test "Gemini lỗi → relay nguyên văn kèm dòng báo phân loại lỗi" do
      make_category()
      make_admin_with_token("admina", "tok")
      stub_panchat!()

      stub_gemini_error!()

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "phản hồi"
      assert inspect(body) =~ "Gemini phân loại lỗi"
    end

    test "OTHER: relay nguyên văn, KHÔNG kèm dòng báo lỗi" do
      make_category()
      make_admin_with_token("admina", "tok")
      stub_panchat!()

      stub_gemini_other!()

      assert {:ok, :relayed} = PancakeInbound.handle_messaging(inbox_payload())
      assert_received {:panchat, _auth, body}
      assert inspect(body) =~ "phản hồi"
      refute inspect(body) =~ "Gemini phân loại lỗi"
    end
  end
end
