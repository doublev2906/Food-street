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
    test "bốc đúng số người từ những người đã đặt (đơn chưa huỷ), không trùng" do
      %{go: go, mi1: mi1} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")
      u3 = user("usr3")

      for u <- [u1, u2, u3] do
        {:ok, _} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      end

      go = Ordering.get_group_order(go.id)
      runners = Ordering.pick_runners(go, 2)

      assert length(runners) == 2
      ids = MapSet.new([u1.id, u2.id, u3.id])
      assert Enum.all?(runners, &MapSet.member?(ids, &1.id))
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
      runners = Ordering.pick_runners(go, 5)
      # Chỉ còn u2 đặt hợp lệ.
      assert [%{id: id}] = runners
      assert id == u2.id
    end

    test "count lớn hơn số người đặt → trả toàn bộ người đặt" do
      %{go: go, mi1: mi1} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")

      for u <- [u1, u2] do
        {:ok, _} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      end

      go = Ordering.get_group_order(go.id)
      assert length(Ordering.pick_runners(go, 10)) == 2
    end

    test "count <= 0 hoặc không phải số nguyên → không bốc ai" do
      %{go: go, mi1: mi1} = setup_group()

      {:ok, _} =
        Ordering.place_order_in_group(user("usr1"), go.id, %{"items" => items([{mi1, 1}])})

      go = Ordering.get_group_order(go.id)
      assert Ordering.pick_runners(go, 0) == []
      assert Ordering.pick_runners(go, nil) == []
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

  describe "aggregate_seller_text/1 (gộp đơn gửi nhà bán)" do
    test "1 đơn nhiều món + ghi chú món + ghi chú chung → đúng format copy FE" do
      %{go: go, mi1: mi1, mi2: mi2} = setup_group()
      u = user("annie")

      {:ok, _} =
        Ordering.place_order_in_group(u, go.id, %{
          "items" => [
            %{"menu_item_id" => mi1.id, "quantity" => 2, "note" => "ít cay"},
            %{"menu_item_id" => mi2.id, "quantity" => 3}
          ],
          "note" => "giao sớm"
        })

      assert {:ok, text} = Ordering.aggregate_seller_text(Ordering.get_group_order(go.id))

      assert text == "2 Xôi ít cay\n3 Bánh mì\n\nGhi chú chung:\n- annie: giao sớm"
    end

    test "gộp cùng tên món qua nhiều đơn (không tiêu đề, không tổng)" do
      %{go: go, mi1: mi1} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")

      {:ok, _} = Ordering.place_order_in_group(u1, go.id, %{"items" => items([{mi1, 2}])})
      {:ok, _} = Ordering.place_order_in_group(u2, go.id, %{"items" => items([{mi1, 1}])})

      assert {:ok, text} = Ordering.aggregate_seller_text(Ordering.get_group_order(go.id))

      # Cả 2 dòng "Xôi" đều có mặt; không phụ thuộc thứ tự giữa 2 đơn.
      assert Enum.sort(String.split(text, "\n")) == ["1 Xôi", "2 Xôi"]
    end

    test "đơn đã huỷ bị loại khỏi tổng hợp" do
      %{go: go, mi1: mi1} = setup_group()
      u = user("usr1")
      {:ok, o} = Ordering.place_order_in_group(u, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.cancel_order(o)

      assert {:error, :no_orders} =
               Ordering.aggregate_seller_text(Ordering.get_group_order(go.id))
    end

    test "đợt chưa có đơn → {:error, :no_orders}" do
      %{go: go} = setup_group()

      assert {:error, :no_orders} =
               Ordering.aggregate_seller_text(Ordering.get_group_order(go.id))
    end
  end

  describe "get_open_group_order_for_category/1" do
    test "lấy đợt mở MỚI NHẤT của danh mục, bỏ đợt đã đóng/huỷ" do
      %{admin: a, cat: cat, go: old_open} = setup_group()

      # Đợt mở mới hơn (order_date muộn hơn) cùng danh mục.
      {:ok, new_open} =
        Ordering.create_group_order(
          %{"title" => "Sáng T3", "order_date" => "2026-07-03", "category_id" => cat.id},
          a
        )

      # Đợt đã đóng (không được chọn) dù order_date muộn nhất.
      {:ok, closed} =
        Ordering.create_group_order(
          %{"title" => "Sáng T4", "order_date" => "2026-07-04", "category_id" => cat.id},
          a
        )

      {:ok, _} = Ordering.update_group_order(closed, %{"status" => "closed"})

      got = Ordering.get_open_group_order_for_category(cat.id)
      assert got.id == new_open.id
      refute got.id == old_open.id
    end

    test "danh mục khác không lẫn; không có đợt mở → nil" do
      %{cat: cat} = setup_group()
      {:ok, other} = Catalog.create_category(%{name: "Ăn trưa"})

      assert Ordering.get_open_group_order_for_category(other.id) == nil
      assert %{} = Ordering.get_open_group_order_for_category(cat.id)
    end
  end

  describe "users_ordering_items/2 (người đã đặt món bị hết)" do
    test "khớp tên món không phân biệt hoa/thường, distinct theo user, loại đơn huỷ" do
      %{go: go, mi1: mi1, mi2: mi2} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")
      u3 = user("usr3")

      # u1 đặt Xôi, u2 đặt Bánh mì, u3 đặt Xôi rồi huỷ.
      {:ok, _} = Ordering.place_order_in_group(u1, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.place_order_in_group(u2, go.id, %{"items" => items([{mi2, 1}])})
      {:ok, o3} = Ordering.place_order_in_group(u3, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.cancel_order(o3)

      go = Ordering.get_group_order(go.id)

      # "xôi" thường → vẫn khớp "Xôi"; chỉ u1 (u3 đã huỷ).
      users = Ordering.users_ordering_items(go, ["xôi"])
      assert [%{id: id}] = users
      assert id == u1.id
    end

    test "nhiều tên món → gộp người đặt bất kỳ món nào, distinct" do
      %{go: go, mi1: mi1, mi2: mi2} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")

      {:ok, _} = Ordering.place_order_in_group(u1, go.id, %{"items" => items([{mi1, 1}])})
      {:ok, _} = Ordering.place_order_in_group(u2, go.id, %{"items" => items([{mi2, 1}])})

      go = Ordering.get_group_order(go.id)
      ids = go |> Ordering.users_ordering_items(["Xôi", "Bánh mì"]) |> Enum.map(& &1.id)
      assert Enum.sort(ids) == Enum.sort([u1.id, u2.id])
    end

    test "danh sách món rỗng → []" do
      %{go: go, mi1: mi1} = setup_group()
      {:ok, _} = Ordering.place_order_in_group(user("usr1"), go.id, %{"items" => items([{mi1, 1}])})

      assert Ordering.users_ordering_items(Ordering.get_group_order(go.id), []) == []
    end
  end

  describe "item_names_in_group/1" do
    test "trả tên món distinct đã đặt (bỏ đơn huỷ), nil → []" do
      %{go: go, mi1: mi1, mi2: mi2} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")

      {:ok, _} = Ordering.place_order_in_group(u1, go.id, %{"items" => items([{mi1, 1}, {mi2, 1}])})
      {:ok, _} = Ordering.place_order_in_group(u2, go.id, %{"items" => items([{mi1, 2}])})

      names = go.id |> Ordering.get_group_order() |> Ordering.item_names_in_group() |> Enum.sort()
      assert names == ["Bánh mì", "Xôi"]
      assert Ordering.item_names_in_group(nil) == []
    end
  end

  describe "set_runners/2 + list_runners/1 (lưu người đi lấy đồ)" do
    test "round-trip giữ đúng thứ tự bốc" do
      %{go: go} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")
      u3 = user("usr3")

      {:ok, _} = Ordering.set_runners(go, [u2, u3, u1])

      go = Ordering.get_group_order(go.id)
      assert go.runner_user_ids == [u2.id, u3.id, u1.id]
      assert Ordering.list_runners(go) |> Enum.map(& &1.id) == [u2.id, u3.id, u1.id]
    end

    test "user đã xoá tự rớt khỏi list_runners, giữ thứ tự còn lại" do
      %{go: go} = setup_group()
      u1 = user("usr1")
      u2 = user("usr2")

      {:ok, _} = Ordering.set_runners(go, [u1, u2])
      {:ok, _} = Accounts.delete_user(u1)

      go = Ordering.get_group_order(go.id)
      assert Ordering.list_runners(go) |> Enum.map(& &1.id) == [u2.id]
    end

    test "chưa bốc ai → []" do
      %{go: go} = setup_group()
      assert Ordering.list_runners(Ordering.get_group_order(go.id)) == []
    end
  end
end
