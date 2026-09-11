defmodule FoodStreet.Repo.Migrations.UpdateMixuePrices do
  @moduledoc """
  Cập nhật menu Mixue theo bảng giá mới (menu hè). Với mỗi món trong @items:
  giá đã có thì update, món chưa có (món mới / bản tách size M/L) thì tạo mới
  trong danh mục "Mixue".

  Các món không còn trong menu mới (@discontinued) được ẩn đi bằng
  `available = false` thay vì xoá, để không vỡ khoá ngoại với đơn hàng cũ.

  Không đụng tới ảnh (image_url). Forward-only, idempotent theo tên món
  (khớp với seeds.exs). `down` là no-op vì không lưu lại trạng thái cũ.
  """
  use Ecto.Migration

  # {tên món (khớp seeds.exs), giá VND, mô tả | nil}
  @items [
    # Kem
    {"Kem ốc quế", 10_000, nil},
    {"Super Sundae trân châu đường đen", 25_000, nil},
    {"Super Sundae xoài", 25_000, nil},
    {"Super Sundae đào hồng", 25_000, nil},
    {"Super Sundae đào vàng", 25_000, nil},
    {"Lucky sundae O-coco", 25_000, nil},
    {"Lucky sundae dâu tây", 25_000, nil},
    # Trà hoa quả
    {"Liên minh cam xoài", 25_000, nil},
    {"Nước chanh tươi lạnh", 15_000, nil},
    {"Trà xanh chanh", 17_000, nil},
    {"Trà chanh lô hội", 20_000, nil},
    {"Chanh leo bách hương", 25_000, nil},
    {"Trà xanh hoa đào", 22_000, nil},
    {"Trà cam dâu tây", 25_000, nil},
    {"Trà đào bigsize", 22_000, nil},
    {"Trà xoài chanh leo", 25_000, nil},
    {"Trà đào dâu tây", 22_000, nil},
    {"Trà cam vàng 9999", 25_000, nil},
    # Trà sữa (món có 2 size → tách M 25.000đ / L 30.000đ)
    {"Trà sữa trân châu đường đen", 25_000, nil},
    {"Trà sữa O-coco", 28_000, nil},
    {"Trà sữa 2J M", 25_000, "Chọn 2 topping"},
    {"Trà sữa 2J L", 30_000, "Chọn 2 topping"},
    {"Trà sữa Caramel", 25_000, nil},
    {"Trà sữa hoa nhài", 20_000, nil},
    {"Trà sữa trân châu M", 25_000, nil},
    {"Trà sữa trân châu L", 30_000, nil},
    {"Trà sữa thạch dừa M", 25_000, nil},
    {"Trà sữa thạch dừa L", 30_000, nil},
    {"Trà sữa thạch đường đen M", 25_000, nil},
    {"Trà sữa thạch đường đen L", 30_000, nil},
    {"Dương chi cam lộ", 25_000, nil},
    {"Sữa thạch Dâu tây", 22_000, nil},
    # Cà phê
    {"Americano kem", 28_000, nil},
    {"Cafe Latte Kem tươi", 30_000, nil},
    {"Americano", 22_000, nil},
    {"Cafe Latte", 28_000, nil},
    {"Cafe latte caramel hạt dẻ", 28_000, nil},
    {"Americano chanh", 28_000, nil},
    {"Americano cam", 28_000, nil},
    # Đặc biệt (banner)
    {"Trà sữa bá vương", 30_000, nil}
  ]

  # Món cũ không còn trong menu mới → ẩn (available = false), không xoá.
  @discontinued [
    "Super Sundae kiwi lô hội",
    "Trà xanh kiwi",
    "Sữa thạch Kiwi Kiwi",
    "Trà sữa đường đen",
    "Latte đường đen",
    "Mocha",
    "Latte",
    "Cafe Mocha Kem tươi",
    "Cafe Latte Caramel Kem tươi",
    "Trà chanh dâu tây",
    "Hồng trà Latte"
  ]

  def up do
    execute(fn ->
      mixue_id =
        case repo().query!("SELECT id FROM categories WHERE name = 'Mixue' LIMIT 1") do
          %{rows: [[id]]} -> id
          _ -> raise "Không tìm thấy danh mục 'Mixue'"
        end

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for {name, price, desc} <- @items do
        price = Decimal.new(price)

        %{num_rows: n} =
          repo().query!(
            "UPDATE menu_items SET price = $1, updated_at = $2 WHERE name = $3",
            [price, now, name]
          )

        if n == 0 do
          repo().query!(
            """
            INSERT INTO menu_items
              (id, name, description, price, available, category_id, inserted_at, updated_at)
            VALUES ($1, $2, $3, $4, true, $5, $6, $6)
            """,
            [Ecto.UUID.bingenerate(), name, desc, price, mixue_id, now]
          )
        end
      end

      repo().query!(
        "UPDATE menu_items SET available = false, updated_at = $1 WHERE name = ANY($2)",
        [now, @discontinued]
      )
    end)
  end

  def down do
    :ok
  end
end
