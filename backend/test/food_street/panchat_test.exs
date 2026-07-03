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
