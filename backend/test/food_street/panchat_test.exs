defmodule FoodStreet.PanchatTest do
  use ExUnit.Case, async: true

  alias FoodStreet.Panchat
  alias FoodStreet.Ordering.GroupOrder

  describe "invite_text/1" do
    test "contains @all, title, date and app link" do
      go = %GroupOrder{title: "Ăn sáng thứ 2", order_date: ~D[2026-07-01], note: nil}
      text = Panchat.invite_text(go)

      assert text =~ "@all"
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

  describe "build_body/1" do
    test "builds the Panchat payload (empty attachments, uuid key, @all via text)" do
      body = Panchat.build_body("@all hello")

      assert body.workspace_id == 4
      assert body.channel_id == 11_813
      assert body.channel_thread_id == nil
      assert body.message == "@all hello"
      assert body.attachments == []
      assert is_integer(body.current_time)
      assert {:ok, _} = Ecto.UUID.cast(body.key)
    end
  end
end
