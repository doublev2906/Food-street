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
