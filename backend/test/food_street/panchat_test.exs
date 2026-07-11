defmodule FoodStreet.PanchatTest do
  use ExUnit.Case, async: true

  alias FoodStreet.Panchat
  alias FoodStreet.Ordering.GroupOrder
  alias FoodStreet.Fund.{ExternalPurchase, FundTransaction}
  alias FoodStreet.Accounts.User

  describe "invite_text/1" do
    test "contains title, date and app link (@all is sent via mention attachment, not text)" do
      go = %GroupOrder{title: "Ăn sáng thứ 2", order_date: ~D[2026-07-01], note: nil}
      text = Panchat.invite_text(go)

      assert text =~ "Ăn sáng thứ 2"
      assert text =~ "2026-07-01"
      assert text =~ "/app"
    end

    test "includes note when present, omits when blank" do
      with_note =
        Panchat.invite_text(%GroupOrder{title: "X", order_date: ~D[2026-07-01], note: "Chốt 8h"})

      assert with_note =~ "Chốt 8h"

      without_note =
        Panchat.invite_text(%GroupOrder{title: "X", order_date: ~D[2026-07-01], note: nil})

      refute without_note =~ "📝"
    end
  end

  describe "send_breakfast_invite/2" do
    test "returns error when token is missing (nil or blank) without calling network" do
      go = %GroupOrder{title: "X", order_date: ~D[2026-07-01], note: nil}

      assert Panchat.send_breakfast_invite(go, nil) == {:error, :panchat_token_missing}
      assert Panchat.send_breakfast_invite(go, "   ") == {:error, :panchat_token_missing}
    end
  end

  describe "close_text/3 và send_group_closed_summary/4" do
    test "close_text chứa tiêu đề, ngày, số đơn và tổng tiền định dạng VN" do
      go = %GroupOrder{id: "abc", title: "Sáng T2", order_date: ~D[2026-07-02]}
      text = Panchat.close_text(go, 3, Decimal.new("90000"))

      assert text =~ "Sáng T2"
      assert text =~ "2026-07-02"
      assert text =~ "3 đơn"
      assert text =~ "90.000đ"
    end

    test "send_group_closed_summary lỗi khi thiếu token, không gọi mạng" do
      go = %GroupOrder{id: "abc", title: "X", order_date: ~D[2026-07-02]}

      assert Panchat.send_group_closed_summary(go, 1, Decimal.new("1000"), nil) ==
               {:error, :panchat_token_missing}

      assert Panchat.send_group_closed_summary(go, 1, Decimal.new("1000"), "  ") ==
               {:error, :panchat_token_missing}
    end
  end

  describe "deleted_text/1 và send_group_deleted/2" do
    test "deleted_text chứa tiêu đề và ngày" do
      go = %GroupOrder{id: "abc", title: "Sáng T2", order_date: ~D[2026-07-02]}
      text = Panchat.deleted_text(go)

      assert text =~ "Sáng T2"
      assert text =~ "2026-07-02"
    end

    test "send_group_deleted lỗi khi thiếu token, không gọi mạng" do
      go = %GroupOrder{id: "abc", title: "X", order_date: ~D[2026-07-02]}

      assert Panchat.send_group_deleted(go, nil) == {:error, :panchat_token_missing}
      assert Panchat.send_group_deleted(go, "  ") == {:error, :panchat_token_missing}
    end
  end

  describe "runners_body/2 và send_runners_picked/3" do
    @uuid "11111111-1111-1111-1111-111111111111"

    test "liệt kê tên người được chọn và mention thật ai có panchat_user_id" do
      go = %GroupOrder{id: "abc", title: "Sáng T2", order_date: ~D[2026-07-02]}

      users = [
        %User{name: "An", panchat_user_id: @uuid},
        %User{name: "Bình", panchat_user_id: nil}
      ]

      body = Panchat.runners_body(go, users)
      [header, runner_p, footer] = body["text"]

      assert header["content"] =~ "Sáng T2"
      assert header["content"] =~ "2026-07-02"
      assert runner_p["content"] =~ "@An"
      assert runner_p["content"] =~ "@Bình"
      assert footer["content"] =~ "lấy hàng"

      # Chỉ An (có UUID) được mention thật; Bình không sinh span.
      assert [%{"type" => "mention", "ref" => %{"type" => "user", "user_id" => @uuid}}] =
               runner_p["spans"]
    end

    test "offset mention theo UTF-16 (👉 emoji đứng trước) trỏ đúng @Tên" do
      go = %GroupOrder{id: "abc", title: "X", order_date: ~D[2026-07-02]}
      users = [%User{name: "An", panchat_user_id: @uuid}]

      body = Panchat.runners_body(go, users)
      [_header, runner_p, _footer] = body["text"]
      [span] = runner_p["spans"]

      # "👉 " = 👉(2) + space(1) = 3 code unit UTF-16; "@An" dài 3.
      assert span["from"] == 3
      assert span["to"] == 6
    end

    test "send_runners_picked lỗi khi thiếu token, không gọi mạng" do
      go = %GroupOrder{id: "abc", title: "X", order_date: ~D[2026-07-02]}
      users = [%User{name: "An", panchat_user_id: @uuid}]

      assert Panchat.send_runners_picked(go, users, nil) == {:error, :panchat_token_missing}
      assert Panchat.send_runners_picked(go, users, "  ") == {:error, :panchat_token_missing}
    end
  end

  describe "external_purchase_text/1 và send_external_purchase/2" do
    defp purchase do
      %ExternalPurchase{
        id: "p1",
        description: "Bún chả cô Tâm",
        total_amount: Decimal.new("50000"),
        purchase_date: ~D[2026-07-02],
        transactions: [
          %FundTransaction{amount: Decimal.new("-30000"), user: %User{name: "An"}},
          %FundTransaction{amount: Decimal.new("-20000"), user: %User{name: "Bình"}}
        ]
      }
    end

    test "external_purchase_text chứa mô tả, tổng, và từng người + số tiền" do
      text = Panchat.external_purchase_text(purchase())

      assert text =~ "Bún chả cô Tâm"
      assert text =~ "50.000đ"
      assert text =~ "An: 30.000đ"
      assert text =~ "Bình: 20.000đ"
    end

    test "@all được gắn qua build_body cho tin chia tiền" do
      body = Panchat.build_body(Panchat.external_purchase_text(purchase()))
      assert [%{"spans" => [%{"type" => "mention", "ref" => %{"type" => "all"}}]} | _] = body["text"]
    end

    test "send_external_purchase lỗi khi thiếu token, không gọi mạng" do
      assert Panchat.send_external_purchase(purchase(), nil) == {:error, :panchat_token_missing}
      assert Panchat.send_external_purchase(purchase(), " ") == {:error, :panchat_token_missing}
    end
  end

  describe "balance_report_text/2 và send_balance_report/3" do
    test "liệt kê từng người + số dư, sắp theo tên" do
      users = [
        %User{name: "Bình", balance: Decimal.new("20000")},
        %User{name: "An", balance: Decimal.new("50000")}
      ]

      text = Panchat.balance_report_text(users, ~D[2026-07-02])

      assert text =~ "Số dư quỹ"
      assert text =~ "An: 50.000đ"
      assert text =~ "Bình: 20.000đ"
      # Sắp theo tên: An đứng trước Bình.
      assert :binary.match(text, "An") < :binary.match(text, "Bình")
    end

    test "send_balance_report lỗi khi thiếu token, không gọi mạng" do
      assert Panchat.send_balance_report([], ~D[2026-07-02], nil) ==
               {:error, :panchat_token_missing}
    end
  end

  describe "balance_report_body/2 — mention con nợ nặng" do
    @uid_a "550e8400-e29b-41d4-a716-446655440000"
    @uid_b "550e8400-e29b-41d4-a716-446655440001"

    defp user_mentions(body) do
      Enum.filter(body["text"], fn p ->
        Enum.any?(p["spans"] || [], fn s ->
          s["type"] == "mention" and get_in(s, ["ref", "type"]) == "user"
        end)
      end)
    end

    test "mention thật ai nợ quá 50k VÀ có panchat_user_id" do
      users = [
        # Nợ 60k + có UUID -> được mention.
        %User{name: "An", balance: Decimal.new("-60000"), panchat_user_id: @uid_a},
        # Nợ 30k (chưa quá 50k) -> bỏ qua dù có UUID.
        %User{name: "Bình", balance: Decimal.new("-30000"), panchat_user_id: @uid_b},
        # Nợ 70k nhưng thiếu UUID -> bỏ qua.
        %User{name: "Cường", balance: Decimal.new("-70000"), panchat_user_id: nil}
      ]

      body = Panchat.balance_report_body(users, ~D[2026-07-02])

      assert [para] = user_mentions(body)
      assert para["content"] == "@An Không donate sớm thì nhịn nhé"

      assert [%{"type" => "mention", "from" => 0, "to" => 3, "ref" => ref}] = para["spans"]
      assert ref == %{"type" => "user", "user_id" => @uid_a}
    end

    test "nợ đúng 50k (biên) không bị tag — chỉ 'quá 50k' mới tag" do
      users = [%User{name: "An", balance: Decimal.new("-50000"), panchat_user_id: @uid_a}]
      assert user_mentions(Panchat.balance_report_body(users, ~D[2026-07-02])) == []
    end

    test "không có con nợ nặng thì body giữ nguyên phần text chung" do
      users = [%User{name: "An", balance: Decimal.new("50000"), panchat_user_id: @uid_a}]
      assert user_mentions(Panchat.balance_report_body(users, ~D[2026-07-02])) == []
    end
  end

  describe "build_body/1" do
    test "dựng RichText SendMessageRequest với @all mention span" do
      body = Panchat.build_body("hello\nworld")

      # text là danh sách paragraph node; @all nằm ở paragraph đầu.
      assert %{"text" => [first | rest]} = body
      assert first["type"] == "paragraph"
      assert first["content"] == "@all hello"

      assert [%{"type" => "mention", "from" => 0, "to" => 4, "ref" => ref}] = first["spans"]
      assert ref == %{"type" => "all", "channel_id" => 11_813}

      # Mỗi dòng tiếp theo là 1 paragraph riêng, không span.
      assert [%{"type" => "paragraph", "content" => "world"}] = rest
    end

    test "gắn link span khi nội dung chứa URL, offset theo UTF-16 code unit" do
      url = "https://dev.pancake.vn:3200/app?group=abc"
      # Dòng có emoji 👉 trước URL -> tính 2 UTF-16 code unit.
      body = Panchat.build_body("Đã chốt (📅 nay)\n6 đơn 👉 #{url}")

      assert [_first, %{"content" => content, "spans" => spans}] = body["text"]

      assert [%{"type" => "link", "from" => from, "to" => to, "url" => ^url}] = spans
      # from = số UTF-16 code unit của "6 đơn 👉 " (👉 = 2) = 9; to = from + len(url).
      assert from == 9
      assert to == from + String.length(url)
      assert content =~ url

      # link_previews KHÔNG gửi ở request — server tự trích từ URL.
      refute Map.has_key?(body, "link_previews")
      refute Map.has_key?(body, "type")
    end

    test "không có link thì không thêm khoá spans cho paragraph thường" do
      body = Panchat.build_body("chỉ có chữ\nkhông link")

      assert [first, second] = body["text"]
      # paragraph đầu chỉ còn mention span, paragraph sau không có khoá spans.
      assert [%{"type" => "mention"}] = first["spans"]
      refute Map.has_key?(second, "spans")
    end
  end

  describe "send_channel_message/2 — HTTP request v2" do
    test "POST /api/v2/channels/:id/messages, workspace_id query, Bearer token, body RichText" do
      test_pid = self()

      Req.Test.stub(FoodStreet.Panchat, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.method, conn.request_path, conn.query_string,
           Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(raw)}
        )

        Req.Test.json(conn, %{"id" => "m1"})
      end)

      assert {:ok, _} = Panchat.send_channel_message("tok123", "xin chào\ndòng 2")

      assert_received {:req, "POST", path, qs, auth, body}
      assert path == "/api/v2/channels/11813/messages"
      assert qs =~ "workspace_id=4"
      assert auth == ["Bearer tok123"]

      assert [
               %{
                 "type" => "paragraph",
                 "content" => "@all xin chào",
                 "spans" => [%{"type" => "mention", "ref" => %{"type" => "all"}}]
               },
               %{"type" => "paragraph", "content" => "dòng 2"}
             ] = body["text"]
    end

    test "HTTP 4xx từ Panchat trả {:error, {:panchat, ...}}" do
      Req.Test.stub(FoodStreet.Panchat, fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"error" => "bad"})
      end)

      assert {:error, {:panchat, "http_422"}} = Panchat.send_channel_message("tok", "hi")
    end
  end
end
