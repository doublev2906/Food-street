defmodule FoodStreet.FundTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.{Fund, Accounts}
  alias FoodStreet.Accounts.User
  alias FoodStreet.Fund.{FundTransaction, ExternalPurchase}

  defp make(username, role, balance) do
    {:ok, u} =
      Accounts.create_user(%{
        name: username,
        username: username,
        email: "#{username}@example.com",
        password: "password123",
        role: role
      })

    Repo.update!(Ecto.Changeset.change(u, balance: Decimal.new(balance)))
  end

  defp admin, do: make("admin1", "admin", "0")

  defp bal(id), do: Repo.get(User, id).balance
  defp interest_debt(id), do: Repo.get(User, id).interest_debt

  defp set_interest_debt(user, amount) do
    Repo.update!(Ecto.Changeset.change(user, interest_debt: Decimal.new(amount)))
  end

  describe "deposit/4 — trừ nợ lãi trước, phần còn lại vào số dư" do
    test "không nợ lãi → nạp bình thường vào số dư" do
      a = admin()
      u = make("usr1", "user", "-100000")

      {:ok, %{interest_paid: paid}} = Fund.deposit(u, "100000", a)

      assert Decimal.equal?(paid, 0)
      assert Decimal.equal?(bal(u.id), Decimal.new("0"))
      assert Decimal.equal?(interest_debt(u.id), Decimal.new("0"))
    end

    test "nạp đủ lớn: gạt hết nợ lãi, phần còn lại giảm dư nợ gốc" do
      a = admin()
      u = make("usr1", "user", "-100000")
      set_interest_debt(u, "272")
      u = Repo.get(User, u.id)

      {:ok, %{interest_paid: paid}} = Fund.deposit(u, "100000", a)

      # 272 gạt nợ lãi, 99.728 vào số dư → -100.000 + 99.728 = -272.
      assert Decimal.equal?(paid, 272)
      assert Decimal.equal?(interest_debt(u.id), Decimal.new("0"))
      assert Decimal.equal?(bal(u.id), Decimal.new("-272"))
    end

    test "nạp nhỏ hơn nợ lãi: chỉ trừ nợ lãi, số dư không đổi" do
      a = admin()
      u = make("usr1", "user", "-100000")
      set_interest_debt(u, "272")
      u = Repo.get(User, u.id)

      {:ok, %{interest_paid: paid, transaction: tx}} = Fund.deposit(u, "100", a)

      assert Decimal.equal?(paid, 100)
      assert Decimal.equal?(interest_debt(u.id), Decimal.new("172"))
      assert Decimal.equal?(bal(u.id), Decimal.new("-100000"))
      # Giao dịch quỹ ghi phần vào số dư (0đ) + diễn giải trừ lãi.
      assert Decimal.equal?(tx.amount, Decimal.new("0"))
      assert tx.description =~ "nợ lãi"
    end

    test "nạp lớn hơn tổng nợ: trả hết lãi + dư ra cộng số dư" do
      a = admin()
      u = make("usr1", "user", "-100000")
      set_interest_debt(u, "272")
      u = Repo.get(User, u.id)

      {:ok, _} = Fund.deposit(u, "500000", a)

      assert Decimal.equal?(interest_debt(u.id), Decimal.new("0"))
      # -100.000 + (500.000 - 272) = 399.728
      assert Decimal.equal?(bal(u.id), Decimal.new("399728"))
    end
  end

  describe "record_external_purchase/2" do
    test "chia đều: trừ số dư từng người, tạo tx split + external_purchase" do
      a = admin()
      u1 = make("usr1", "user", "100000")
      u2 = make("usr2", "user", "100000")
      u3 = make("usr3", "user", "100000")

      {:ok, p} =
        Fund.record_external_purchase(a, %{
          "description" => "Bún chả cô Tâm",
          "total_amount" => "90000",
          "shares" => [
            %{"user_id" => u1.id, "amount" => "30000"},
            %{"user_id" => u2.id, "amount" => "30000"},
            %{"user_id" => u3.id, "amount" => "30000"}
          ]
        })

      assert Decimal.equal?(bal(u1.id), Decimal.new("70000"))
      assert Decimal.equal?(bal(u2.id), Decimal.new("70000"))
      assert Decimal.equal?(bal(u3.id), Decimal.new("70000"))

      assert Repo.aggregate(ExternalPurchase, :count, :id) == 1
      txs = Repo.all(FundTransaction)
      assert length(txs) == 3
      assert Enum.all?(txs, &(&1.type == "split"))
      assert Enum.all?(txs, &(&1.external_purchase_id == p.id))
      # amount lưu âm (trừ tiền)
      assert Enum.all?(txs, &(Decimal.compare(&1.amount, 0) == :lt))
    end

    test "chia tay (custom) tổng khớp thì OK" do
      a = admin()
      u1 = make("usr1", "user", "100000")
      u2 = make("usr2", "user", "100000")

      {:ok, _} =
        Fund.record_external_purchase(a, %{
          "description" => "Cà phê",
          "total_amount" => "50000",
          "shares" => [
            %{"user_id" => u1.id, "amount" => "20000"},
            %{"user_id" => u2.id, "amount" => "30000"}
          ]
        })

      assert Decimal.equal?(bal(u1.id), Decimal.new("80000"))
      assert Decimal.equal?(bal(u2.id), Decimal.new("70000"))
    end

    test "tổng không khớp -> lỗi, không đổi số dư nào (rollback)" do
      a = admin()
      u1 = make("usr1", "user", "100000")
      u2 = make("usr2", "user", "100000")

      assert {:error, :amount_mismatch} =
               Fund.record_external_purchase(a, %{
                 "description" => "Sai tổng",
                 "total_amount" => "90000",
                 "shares" => [
                   %{"user_id" => u1.id, "amount" => "30000"},
                   %{"user_id" => u2.id, "amount" => "30000"}
                 ]
               })

      assert Decimal.equal?(bal(u1.id), Decimal.new("100000"))
      assert Decimal.equal?(bal(u2.id), Decimal.new("100000"))
      assert Repo.aggregate(ExternalPurchase, :count, :id) == 0
      assert Repo.aggregate(FundTransaction, :count, :id) == 0
    end

    test "admin nằm trong danh sách ăn thì admin cũng bị trừ" do
      a = make("admin1", "admin", "200000")
      u1 = make("usr1", "user", "100000")

      {:ok, _} =
        Fund.record_external_purchase(a, %{
          "description" => "Trà đá",
          "total_amount" => "20000",
          "shares" => [
            %{"user_id" => a.id, "amount" => "10000"},
            %{"user_id" => u1.id, "amount" => "10000"}
          ]
        })

      assert Decimal.equal?(bal(a.id), Decimal.new("190000"))
      assert Decimal.equal?(bal(u1.id), Decimal.new("90000"))
    end

    test "chọn 0 người -> lỗi" do
      a = admin()

      assert {:error, :no_shares} =
               Fund.record_external_purchase(a, %{
                 "description" => "Trống",
                 "total_amount" => "10000",
                 "shares" => []
               })
    end
  end

  describe "list_transactions/1 — lọc" do
    setup do
      a = admin()
      u1 = make("usr1", "user", "0")
      u2 = make("usr2", "user", "0")
      {:ok, _} = Fund.deposit(u1, "100000", a)
      {:ok, _} = Fund.adjust(u1, "-20000", a)
      {:ok, _} = Fund.deposit(u2, "50000", a)
      %{u1: u1, u2: u2}
    end

    test "không filter → trả tất cả" do
      assert Fund.list_transactions().total == 3
    end

    test "lọc theo loại giao dịch" do
      r = Fund.list_transactions(%{"type" => "deposit"})
      assert r.total == 2
      assert Enum.all?(r.entries, &(&1.type == "deposit"))
    end

    test "lọc theo người dùng", %{u1: u1} do
      r = Fund.list_transactions(%{"user_id" => u1.id})
      assert r.total == 2
      assert Enum.all?(r.entries, &(&1.user_id == u1.id))
    end

    test "loại/không hợp lệ bị bỏ qua → trả tất cả" do
      assert Fund.list_transactions(%{"type" => "bogus"}).total == 3
      assert Fund.list_transactions(%{"user_id" => "not-a-uuid"}).total == 3
    end

    test "lọc khoảng ngày: from tương lai loại hết, from quá khứ giữ hết" do
      future = Date.utc_today() |> Date.add(2) |> Date.to_iso8601()
      past = Date.utc_today() |> Date.add(-2) |> Date.to_iso8601()
      assert Fund.list_transactions(%{"from" => future}).total == 0
      assert Fund.list_transactions(%{"from" => past}).total == 3
    end

    test "kết hợp loại + người dùng", %{u1: u1} do
      r = Fund.list_transactions(%{"type" => "adjustment", "user_id" => u1.id})
      assert r.total == 1
      assert [%{type: "adjustment", user_id: uid}] = r.entries
      assert uid == u1.id
    end
  end
end
