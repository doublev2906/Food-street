defmodule FoodStreet.OrderingTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.{Ordering, Accounts, Catalog}

  defp admin do
    {:ok, a} =
      Accounts.create_user(%{
        name: "Admin",
        username: "admin1",
        email: "admin1@example.com",
        password: "password123",
        role: "admin"
      })

    a
  end

  defp user(username) do
    {:ok, u} =
      Accounts.create_user(%{
        name: username,
        username: username,
        email: "#{username}@example.com",
        password: "password123",
        role: "user"
      })

    u
  end

  defp setup_group do
    a = admin()
    {:ok, cat} = Catalog.create_category(%{name: "Ăn sáng"})

    {:ok, mi1} =
      Catalog.create_menu_item(%{
        name: "Xôi",
        price: "20000",
        category_id: cat.id,
        available: true
      })

    {:ok, mi2} =
      Catalog.create_menu_item(%{
        name: "Bánh mì",
        price: "15000",
        category_id: cat.id,
        available: true
      })

    {:ok, go} =
      Ordering.create_group_order(
        %{"title" => "Sáng T2", "order_date" => "2026-07-02", "category_id" => cat.id},
        a
      )

    %{admin: a, cat: cat, mi1: mi1, mi2: mi2, go: go}
  end

  defp items(pairs),
    do: Enum.map(pairs, fn {mi, q} -> %{"menu_item_id" => mi.id, "quantity" => q} end)

  describe "sửa đơn khi chưa chốt (place_order_in_group upsert)" do
    test "user đặt rồi sửa lại khi pending → đổi món/tổng" do
      %{go: go, mi1: mi1, mi2: mi2} = setup_group()
      u = user("usr1")

      {:ok, o1} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      assert Decimal.equal?(o1.total_amount, Decimal.new("20000"))

      {:ok, o2} =
        Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}, {mi2, 2}])})

      assert o2.id == o1.id
      assert Decimal.equal?(o2.total_amount, Decimal.new("50000"))
    end

    test "không sửa được đơn đã chốt (confirmed)" do
      %{admin: a, go: go, mi1: mi1} = setup_group()
      u = user("usr1")

      {:ok, o} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.confirm_order(o, a)

      assert {:error, :order_not_editable} =
               Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 2}])})
    end

    test "huỷ đơn rồi đặt lại → tái dùng dòng cũ về pending, không kẹt đơn đã huỷ" do
      %{go: go, mi1: mi1, mi2: mi2} = setup_group()
      u = user("usr1")

      {:ok, o1} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, cancelled} = Ordering.cancel_order(o1)
      assert cancelled.status == "cancelled"

      # Đơn "đang hoạt động" phải là nil sau khi huỷ → FE hiện form đặt mới, trống.
      assert Ordering.get_user_order_in_group(u.id, go.id) == nil

      # Đặt lại: tái dùng chính dòng cũ (tôn trọng unique index), về pending,
      # món mới thay hẳn món của đơn đã huỷ.
      {:ok, o2} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi2, 2}])})
      assert o2.id == o1.id
      assert o2.status == "pending"
      assert Decimal.equal?(o2.total_amount, Decimal.new("30000"))
      assert [%{item_name: "Bánh mì", quantity: 2}] = o2.items
    end
  end

  describe "pick_runners/2 (bốc người đi lấy đồ)" do
    test "bốc đúng số người từ những người đã đặt (đơn chưa huỷ)" do
      %{go: go, mi1: mi1} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")
      u3 = user("usr3")

      for u <- [u1, u2, u3] do
        {:ok, _} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      end

      go = Ordering.get_group_order(go.id)
      {:ok, runners} = Ordering.pick_runners(go, 2)

      assert length(runners) == 2
      ids = MapSet.new([u1.id, u2.id, u3.id])
      assert Enum.all?(runners, &MapSet.member?(ids, &1.id))
      # Không trùng người.
      assert runners |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 2
    end

    test "bỏ qua đơn đã huỷ khi đếm người đặt" do
      %{go: go, mi1: mi1} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")

      {:ok, o1} = Ordering.place_order_in_group(u1, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.place_order_in_group(u2, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.cancel_order(o1)

      go = Ordering.get_group_order(go.id)
      # Chỉ còn 1 người đặt hợp lệ → không đủ để bốc.
      assert {:error, :not_enough_orderers} = Ordering.pick_runners(go, 1)
    end

    test "count phải nhỏ hơn số người đặt và >= 1" do
      %{go: go, mi1: mi1} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")

      for u <- [u1, u2] do
        {:ok, _} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      end

      go = Ordering.get_group_order(go.id)
      assert {:error, :count_too_large} = Ordering.pick_runners(go, 2)
      assert {:error, :invalid_count} = Ordering.pick_runners(go, 0)
      assert {:error, :invalid_count} = Ordering.pick_runners(go, nil)
      assert {:ok, [_]} = Ordering.pick_runners(go, 1)
    end

    test "ít hơn 2 người đặt → không đủ" do
      %{go: go, mi1: mi1} = setup_group()
      u1 = user("usr1")
      {:ok, _} = Ordering.place_order_in_group(u1, go.id, %{"items" => items([{mi1, 1}])})

      go = Ordering.get_group_order(go.id)
      assert {:error, :not_enough_orderers} = Ordering.pick_runners(go, 1)
    end
  end

  describe "update_order/2 (admin sửa đơn người khác)" do
    test "sửa đơn pending → items/total cập nhật" do
      %{go: go, mi1: mi1, mi2: mi2} = setup_group()
      u = user("usr1")
      {:ok, o} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})

      {:ok, updated} =
        Ordering.update_order(o, %{"items" => items([{mi2, 3}]), "note" => "ít cay"})

      assert updated.id == o.id
      assert Decimal.equal?(updated.total_amount, Decimal.new("45000"))
      assert updated.note == "ít cay"
      assert [%{item_name: "Bánh mì", quantity: 3}] = updated.items
    end

    test "đơn đã chốt → không sửa được" do
      %{admin: a, go: go, mi1: mi1} = setup_group()
      u = user("usr1")
      {:ok, o} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, confirmed} = Ordering.confirm_order(o, a)

      assert {:error, :order_not_editable} =
               Ordering.update_order(confirmed, %{"items" => items([{mi1, 2}])})
    end

    test "đợt đã đóng → không sửa được" do
      %{admin: a, go: go, mi1: mi1} = setup_group()
      u = user("usr1")
      {:ok, o} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.close_group_order(go, a)

      # Sau khi đóng đợt, đơn đã confirmed → chặn.
      fresh = Ordering.get_order(o.id)

      assert {:error, :order_not_editable} =
               Ordering.update_order(fresh, %{"items" => items([{mi1, 2}])})
    end
  end
end
