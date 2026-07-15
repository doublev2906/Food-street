defmodule FoodStreet.InterestTest do
  use FoodStreet.DataCase, async: true

  alias FoodStreet.{Interest, Accounts, Scheduling}
  alias FoodStreet.Accounts.User
  alias FoodStreet.Fund.FundTransaction
  alias FoodStreet.Interest.InterestCharge

  # accrual_hour mặc định = 2 (giờ VN). VN = UTC+7.
  # 03:00Z = 10:00 VN (đã qua giờ chạy) · 17:00Z = 00:00 VN hôm sau (chưa tới giờ).
  @accrual_time ~U[2026-07-02 03:00:00Z]
  @too_early ~U[2026-07-02 17:00:00Z]
  @vn_date ~D[2026-07-02]

  defp make(username, balance) do
    {:ok, u} =
      Accounts.create_user(%{
        name: username,
        username: username,
        email: "#{username}@example.com",
        password: "password123",
        role: "user"
      })

    Repo.update!(Ecto.Changeset.change(u, balance: Decimal.new(balance)))
  end

  defp reload(id), do: Repo.get(User, id)

  describe "compute_interest/1 (làm tròn LÊN, số nguyên)" do
    test "gốc ≤ 0 → không có lãi" do
      assert Decimal.equal?(Interest.compute_interest(Decimal.new("0")), 0)
    end

    test "gốc nhỏ → áp sàn 150đ" do
      # 10.000 × 99/36500 = 27,12 → làm tròn lên 28 → nhưng < sàn → 150.
      assert Decimal.equal?(Interest.compute_interest(Decimal.new("10000")), 150)
      # 50.000 × 99/36500 = 135,6 → 136 → vẫn < sàn → 150.
      assert Decimal.equal?(Interest.compute_interest(Decimal.new("50000")), 150)
    end

    test "gốc lớn → tính theo %/ngày, LÀM TRÒN LÊN" do
      # 100.000 × 99/36500 = 271,23 → làm tròn lên → 272
      assert Decimal.equal?(Interest.compute_interest(Decimal.new("100000")), 272)
      # 200.000 × 99/36500 = 542,46 → 543
      assert Decimal.equal?(Interest.compute_interest(Decimal.new("200000")), 543)
    end
  end

  describe "run_tick/1" do
    test "chưa tới giờ chạy → bỏ qua" do
      make("no1", "-100000")
      assert {:ok, :skipped, :too_early} = Interest.run_tick(@too_early)
    end

    test "cộng lãi vào nợ lãi (KHÔNG đụng balance), ghi sổ cái quỹ lãi" do
      u = make("no1", "-100000")

      assert {:ok, :accrued, %{count: 1, total: total}} = Interest.run_tick(@accrual_time)
      assert Decimal.equal?(total, 272)

      after_ = reload(u.id)
      # Balance KHÔNG đổi; lãi vào interest_debt.
      assert Decimal.equal?(after_.balance, Decimal.new("-100000"))
      assert Decimal.equal?(after_.interest_debt, Decimal.new("272"))

      # KHÔNG tạo giao dịch quỹ (fund_transactions) khi tính lãi.
      assert Repo.aggregate(FundTransaction, :count, :id) == 0

      # Sổ cái quỹ lãi: 1 dòng, gốc + nợ lãi sau + ngày.
      charge = Repo.get_by!(InterestCharge, user_id: u.id, charged_on: @vn_date)
      assert Decimal.equal?(charge.amount, Decimal.new("272"))
      assert Decimal.equal?(charge.base_amount, Decimal.new("100000"))
      assert Decimal.equal?(charge.interest_debt_after, Decimal.new("272"))
    end

    test "idempotent trong ngày → gọi lại không tính trùng" do
      make("no1", "-100000")

      assert {:ok, :accrued, %{count: 1}} = Interest.run_tick(@accrual_time)
      assert {:ok, :skipped, :already_done} = Interest.run_tick(@accrual_time)
      assert Repo.aggregate(InterestCharge, :count, :id) == 1
    end

    test "chỉ tính cho người còn nợ; người dương/bằng 0 không bị đụng" do
      neg = make("no1", "-100000")
      pos = make("ok1", "80000")
      zero = make("zero1", "0")

      assert {:ok, :accrued, %{count: 1}} = Interest.run_tick(@accrual_time)

      assert Decimal.compare(reload(neg.id).interest_debt, Decimal.new("0")) == :gt
      assert Decimal.equal?(reload(pos.id).interest_debt, Decimal.new("0"))
      assert Decimal.equal?(reload(zero.id).interest_debt, Decimal.new("0"))
      assert Repo.aggregate(InterestCharge, :count, :id) == 1
    end
  end

  describe "accrue_for_date/1 — lãi kép nhiều ngày" do
    test "chạy 2 ngày liên tiếp: gốc tính lãi gồm cả nợ lãi cũ (lãi kép)" do
      u = make("no1", "-100000")

      Interest.accrue_for_date(~D[2026-07-02])
      day1 = reload(u.id).interest_debt
      assert Decimal.equal?(day1, Decimal.new("272"))

      Interest.accrue_for_date(~D[2026-07-03])
      day2 = reload(u.id).interest_debt
      # Ngày 2 tính trên gốc 100.000 + 272 → nợ lãi to hơn ngày 1.
      assert Decimal.compare(day2, day1) == :gt
      # Balance vẫn nguyên.
      assert Decimal.equal?(reload(u.id).balance, Decimal.new("-100000"))
      assert Repo.aggregate(InterestCharge, :count, :id) == 2
    end

    test "gọi lại cùng ngày → không tính trùng (count 0)" do
      make("no1", "-100000")

      assert %{count: 1} = Interest.accrue_for_date(@vn_date)
      assert %{count: 0, total: total} = Interest.accrue_for_date(@vn_date)
      assert Decimal.equal?(total, 0)
    end
  end

  describe "accrue_today/0 và báo cáo quỹ" do
    test "chạy thủ công bỏ qua chặn giờ" do
      make("no1", "-100000")
      assert %{count: 1} = Interest.accrue_today(@too_early)
    end

    test "fund_summary tổng hợp đúng" do
      make("no1", "-100000")
      make("no2", "-200000")
      make("ok1", "50000")

      Interest.accrue_for_date(@vn_date)
      s = Interest.fund_summary(@accrual_time)

      # 272 + 543 = 815 cộng dồn vào quỹ; chưa ai trả → thu thực = 0.
      assert Decimal.equal?(s.fund_total, Decimal.new("815"))
      assert Decimal.equal?(s.outstanding_interest, Decimal.new("815"))
      assert Decimal.equal?(s.collected_total, Decimal.new("0"))
      assert s.charge_count == 2
      assert s.debtor_count == 2
      assert Decimal.equal?(s.today_total, Decimal.new("815"))
      assert Decimal.equal?(s.annual_rate_percent, Decimal.new("99"))
    end
  end

  test "job_runs được đánh dấu sau khi chạy" do
    make("no1", "-100000")
    assert Scheduling.job_ran_on("interest_accrual") == nil
    Interest.run_tick(@accrual_time)
    assert Scheduling.job_ran_on("interest_accrual") == @vn_date
  end
end
