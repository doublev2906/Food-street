defmodule FoodStreet.PanchatBotTokenTest do
  # async: false — đụng vào Application env `:panchat_bot_token` (toàn cục).
  use ExUnit.Case, async: false

  alias FoodStreet.Panchat
  alias FoodStreet.Ordering.GroupOrder
  alias FoodStreet.Accounts.User

  setup do
    prev = Application.get_env(:food_street, :panchat_bot_token)
    on_exit(fn -> Application.put_env(:food_street, :panchat_bot_token, prev) end)
    %{prev: prev}
  end

  describe "bot_token/0" do
    test "trả token khi đã cấu hình" do
      Application.put_env(:food_street, :panchat_bot_token, "bot-xyz")
      assert Panchat.bot_token() == "bot-xyz"
    end

    test "trả nil khi chưa cấu hình hoặc rỗng" do
      Application.delete_env(:food_street, :panchat_bot_token)
      assert Panchat.bot_token() == nil

      Application.put_env(:food_street, :panchat_bot_token, "")
      assert Panchat.bot_token() == nil
    end
  end

  describe "thiếu token bot" do
    setup do
      Application.delete_env(:food_street, :panchat_bot_token)
      :ok
    end

    test "mọi tin (kể cả tin do admin bấm) trả lỗi, không gọi mạng" do
      go = %GroupOrder{id: "abc", title: "X", order_date: ~D[2026-07-02]}
      users = [%User{name: "An", panchat_user_id: "11111111-1111-1111-1111-111111111111"}]

      assert Panchat.send_breakfast_invite(go, "Vân") == {:error, :panchat_token_missing}

      assert Panchat.send_group_closed_summary(go, 1, Decimal.new("1000"), "Vân") ==
               {:error, :panchat_token_missing}

      assert Panchat.send_group_refunded(go, 1, Decimal.new("1000"), :reopen, "Vân") ==
               {:error, :panchat_token_missing}

      assert Panchat.send_group_deleted(go, "Vân") == {:error, :panchat_token_missing}
      assert Panchat.send_runners_picked(go, users, "Vân") == {:error, :panchat_token_missing}
    end
  end
end
