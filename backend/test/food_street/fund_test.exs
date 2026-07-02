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
end
