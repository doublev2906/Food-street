defmodule FoodStreet.Repo.Migrations.LocalizeMixueImagesAndPrices do
  @moduledoc """
  Chuyển ảnh các món Mixue sang bộ ảnh local trong `frontend/public/items` (được
  nginx/Vite phục vụ tại `/items/...`), thay cho URL remote pancake.vn; đồng thời
  cập nhật giá theo `items/manifest.csv` (price_kvnd × 1.000đ).

  Quy ước với các trường hợp mập mờ trong manifest:
    * Món có 2 size "25/30" → tách thành 2 món M (25.000đ) và L (30.000đ).
    * Topping → giữ nguyên hoàn toàn (ảnh remote + giá hiện tại), không localize.

  Forward-only, idempotent theo tên món (khớp với seeds.exs). `down` chỉ gỡ ảnh
  local về NULL, không khôi phục URL remote cũ và không đụng tới giá.
  """
  use Ecto.Migration

  # {tên món (khớp seeds.exs), file trong /items, giá VND | nil = không đổi giá}
  @items [
    # Kem
    {"Kem ốc quế", "ice_cream_01.png", 10_000},
    {"Lucky sundae O-coco", "ice_cream_02.png", 25_000},
    {"Super Sundae trân châu đường đen", "ice_cream_03.png", 25_000},
    {"Lucky sundae dâu tây", "ice_cream_04.png", 25_000},
    {"Super Sundae kiwi lô hội", "ice_cream_05.png", 25_000},
    {"Super Sundae đào hồng", "ice_cream_06.png", 25_000},
    {"Super Sundae xoài", "ice_cream_07.png", 25_000},
    {"Super Sundae đào vàng", "ice_cream_08.png", 25_000},
    # Trà hoa quả
    {"Nước chanh tươi lạnh", "fruit_tea_01.png", 15_000},
    {"Trà đào dâu tây", "fruit_tea_02.png", 22_000},
    {"Trà xoài chanh leo", "fruit_tea_03.png", 22_000},
    {"Chanh leo bách hương", "fruit_tea_04.png", 22_000},
    {"Trà xanh chanh", "fruit_tea_05.png", 15_000},
    {"Trà xanh kiwi", "fruit_tea_06.png", 22_000},
    {"Trà đào bigsize", "fruit_tea_07.png", 22_000},
    {"Trà xanh hoa đào", "fruit_tea_08.png", 22_000},
    {"Dương chi cam lộ", "fruit_tea_09.png", 28_000},
    # Trà sữa (món có 2 size → tách M 25.000đ / L 30.000đ)
    {"Trà sữa trân châu đường đen", "milk_tea_01.png", 25_000},
    {"Trà sữa Caramel", "milk_tea_02.png", 25_000},
    {"Trà sữa trân châu M", "milk_tea_03.png", 25_000},
    {"Trà sữa trân châu L", "milk_tea_03.png", 30_000},
    {"Sữa thạch Kiwi Kiwi", "milk_tea_04.png", 22_000},
    {"Sữa thạch Dâu tây", "milk_tea_05.png", 22_000},
    {"Trà sữa 2J M", "milk_tea_06.png", 25_000},
    {"Trà sữa 2J L", "milk_tea_06.png", 30_000},
    {"Trà sữa thạch dừa M", "milk_tea_07.png", 25_000},
    {"Trà sữa thạch dừa L", "milk_tea_07.png", 30_000},
    {"Trà sữa đường đen", "milk_tea_08.png", 30_000},
    {"Trà sữa O-coco", "milk_tea_09.png", 28_000},
    # Cà phê
    {"Latte đường đen", "coffee_01.png", 25_000},
    {"Mocha", "coffee_02.png", 25_000},
    {"Latte", "coffee_03.png", 22_000},
    {"Cafe Latte Kem tươi", "coffee_04.png", 25_000},
    {"Cafe Mocha Kem tươi", "coffee_05.png", 25_000},
    {"Cafe Latte Caramel Kem tươi", "coffee_06.png", 25_000},
    # Đặc biệt (banner)
    {"Trà chanh lô hội", "top_banner_01.png", 17_000},
    {"Trà chanh dâu tây", "top_banner_02.png", 25_000},
    {"Trà sữa bá vương", "top_banner_04.png", 30_000},
    {"Hồng trà Latte", "top_banner_05.png", 25_000}
    # Topping: giữ nguyên ảnh remote và giá hiện tại, không đụng tới.
  ]

  def up do
    for {name, file, price} <- @items do
      url = "/items/" <> file

      execute(fn ->
        if is_nil(price) do
          repo().query!("UPDATE menu_items SET image_url = $1 WHERE name = $2", [url, name])
        else
          repo().query!(
            "UPDATE menu_items SET image_url = $1, price = $2 WHERE name = $3",
            [url, price, name]
          )
        end
      end)
    end
  end

  def down do
    names = for {n, _, _} <- @items, do: n

    execute(fn ->
      repo().query!(
        "UPDATE menu_items SET image_url = NULL WHERE name = ANY($1) AND image_url LIKE '/items/%'",
        [names]
      )
    end)
  end
end
