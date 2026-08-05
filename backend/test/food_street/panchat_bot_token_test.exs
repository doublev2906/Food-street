defmodule FoodStreet.PanchatBotTokenTest do
  # async: false — đụng vào Application env `:panchat_bot_token` (toàn cục).
  use ExUnit.Case, async: false

  alias FoodStreet.Panchat

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
end
