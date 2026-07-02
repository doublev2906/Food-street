defmodule FoodStreet.BalanceReportTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.{BalanceReport, Settings, Accounts}

  # 10:00 UTC = 17:00 giờ VN.
  @at_5pm ~U[2026-07-02 10:00:00Z]
  @before_5pm ~U[2026-07-02 09:00:00Z]

  setup do
    Req.Test.stub(FoodStreet.Panchat, fn conn ->
      Req.Test.json(conn, %{"success" => true, "message" => %{"id" => "m1"}})
    end)

    :ok
  end

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

  test "gửi 1 lần lúc 17:00, idempotent trong ngày" do
    a = make("admin1", "admin", "0")
    Settings.put_panchat_token(a.id, "tok")
    make("usr1", "user", "50000")

    assert {:ok, :sent} = BalanceReport.run_tick(@at_5pm)
    # Gọi lại cùng ngày → không gửi nữa.
    assert {:ok, :skipped, :already_sent} = BalanceReport.run_tick(@at_5pm)
  end

  test "chưa tới 17:00 thì bỏ qua" do
    a = make("admin1", "admin", "0")
    Settings.put_panchat_token(a.id, "tok")

    assert {:ok, :skipped, :too_early} = BalanceReport.run_tick(@before_5pm)
  end

  test "không admin nào có token → bỏ qua" do
    make("admin1", "admin", "0")
    make("usr1", "user", "50000")

    assert {:ok, :skipped, :no_admin_token} = BalanceReport.run_tick(@at_5pm)
  end
end
