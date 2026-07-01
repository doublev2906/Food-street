defmodule FoodStreet.SchedulingTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.{Scheduling, Settings, Accounts, Catalog}
  alias FoodStreet.Scheduling.DailyOrderSchedule

  # 02:00 UTC = 09:00 giờ Việt Nam (UTC+7).
  @now ~U[2026-07-08 02:00:00Z]
  @vn_weekday Date.day_of_week(Date.add(~D[2026-07-08], 0))

  setup do
    # Không gọi mạng: Panchat trả success qua Req.Test stub.
    Req.Test.stub(FoodStreet.Panchat, fn conn ->
      Req.Test.json(conn, %{"success" => true, "message" => %{"id" => "m1"}})
    end)

    :ok
  end

  defp admin(username) do
    {:ok, u} =
      Accounts.create_user(%{
        name: "Admin #{username}",
        username: username,
        email: "#{username}@example.com",
        password: "password123",
        role: "admin"
      })

    u
  end

  defp category do
    {:ok, c} = Catalog.create_category(%{name: "Ăn sáng"})
    c
  end

  defp save!(attrs) do
    {:ok, s} = Scheduling.upsert_schedule(attrs)
    s
  end

  defp base_attrs(owner, cat, overrides \\ %{}) do
    Map.merge(
      %{
        "enabled" => true,
        "owner_id" => owner.id,
        "category_id" => cat.id,
        "title" => "Ăn sáng",
        "weekdays" => [@vn_weekday],
        "create_time" => ~T[07:00:00],
        "deadline_time" => ~T[08:30:00]
      },
      overrides
    )
  end

  describe "due?/2" do
    setup do
      owner = admin("owner")
      Settings.put_panchat_token(owner.id, "tok")
      %{owner: owner, cat: category()}
    end

    test "true khi đúng ngày, đã qua giờ tạo, chưa chạy hôm nay", %{owner: o, cat: c} do
      s = save!(base_attrs(o, c))
      assert Scheduling.due?(s, @now)
    end

    test "false khi hôm nay không nằm trong weekdays", %{owner: o, cat: c} do
      other = if @vn_weekday == 7, do: 1, else: @vn_weekday + 1
      s = save!(base_attrs(o, c, %{"weekdays" => [other]}))
      refute Scheduling.due?(s, @now)
    end

    test "false khi chưa tới giờ tạo", %{owner: o, cat: c} do
      s =
        save!(base_attrs(o, c, %{"create_time" => ~T[10:00:00], "deadline_time" => ~T[11:00:00]}))

      refute Scheduling.due?(s, @now)
    end

    test "false khi đã chạy hôm nay (last_run_on = ngày VN)", %{owner: o, cat: c} do
      s =
        save!(base_attrs(o, c))
        |> DailyOrderSchedule.ran_changeset(~D[2026-07-08])
        |> Repo.update!()

      refute Scheduling.due?(s, @now)
    end

    test "false khi tắt", %{owner: o, cat: c} do
      s = save!(base_attrs(o, c, %{"enabled" => false}))
      refute Scheduling.due?(s, @now)
    end
  end

  describe "run_tick/1" do
    test "tạo đúng 1 đợt và idempotent trong ngày" do
      o = admin("owner")
      Settings.put_panchat_token(o.id, "tok")
      c = category()
      save!(base_attrs(o, c))

      assert {:ok, :created, go} = Scheduling.run_tick(@now)
      assert go.title == "Ăn sáng"
      assert go.order_date == ~D[2026-07-08]
      assert go.created_by_id == o.id
      # deadline VN 08:30 → 01:30 UTC
      assert DateTime.to_time(go.deadline) == ~T[01:30:00]

      # Gọi lại cùng ngày → không tạo thêm.
      assert {:ok, :skipped, :not_due} = Scheduling.run_tick(@now)
      assert length(list_group_orders()) == 1
    end

    test "bỏ qua khi chủ lịch chưa có token Panchat" do
      o = admin("owner")
      c = category()
      save!(base_attrs(o, c))

      assert {:ok, :skipped, :owner_token_missing} = Scheduling.run_tick(@now)
      assert list_group_orders() == []
    end

    test "bỏ qua khi chưa tới giờ" do
      o = admin("owner")
      Settings.put_panchat_token(o.id, "tok")
      c = category()
      save!(base_attrs(o, c, %{"create_time" => ~T[10:00:00], "deadline_time" => ~T[11:00:00]}))

      assert {:ok, :skipped, :not_due} = Scheduling.run_tick(@now)
      assert list_group_orders() == []
    end
  end

  defp list_group_orders do
    Repo.all(FoodStreet.Ordering.GroupOrder)
  end
end
