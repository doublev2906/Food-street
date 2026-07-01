# Seed dữ liệu mẫu cho hệ thống đặt đồ ăn sáng.
#
#     mix run priv/repo/seeds.exs
#
# Idempotent: chạy nhiều lần không tạo trùng (dựa theo email / tên / tiêu đề).

import Ecto.Query
alias FoodStreet.{Repo, Accounts, Catalog, Ordering}
alias FoodStreet.Catalog.{MenuItem, Category}
alias FoodStreet.Ordering.GroupOrder

defmodule Seeds do
  def upsert_user(attrs) do
    case Accounts.get_user_by_email(attrs["email"]) do
      nil ->
        {:ok, user} = Accounts.create_user(attrs)
        IO.puts("  + user #{user.email} (#{user.role})")
        user

      user ->
        user
    end
  end

  def upsert_category(name, desc) do
    case Repo.one(from c in Category, where: c.name == ^name) do
      nil ->
        {:ok, c} = Catalog.create_category(%{"name" => name, "description" => desc})
        IO.puts("  + danh mục #{c.name}")
        c

      c ->
        c
    end
  end

  def upsert_menu(attrs) do
    case Repo.one(from m in MenuItem, where: m.name == ^attrs["name"]) do
      nil ->
        {:ok, item} = Catalog.create_menu_item(attrs)
        IO.puts("  + món #{item.name} - #{item.price}")
        item

      item ->
        # cập nhật category / ảnh nếu có thay đổi
        changes =
          %{}
          |> maybe_put("category_id", attrs["category_id"], item.category_id)
          |> maybe_put("image_url", attrs["image_url"], item.image_url)

        if map_size(changes) > 0 do
          {:ok, item} = Catalog.update_menu_item(item, changes)
          item
        else
          item
        end
    end
  end

  defp maybe_put(map, _key, nil, _current), do: map
  defp maybe_put(map, key, value, current) when value == current, do: map
  defp maybe_put(map, key, value, _current), do: Map.put(map, key, value)
end

IO.puts("== Seeding users ==")

admin =
  Seeds.upsert_user(%{
    "name" => "Quản trị viên",
    "username" => "admin",
    "email" => "admin@foodstreet.vn",
    "password" => "admin123",
    "role" => "admin"
  })

# Thành viên channel "Pancake Food Street" (workspace 4 / channel 11813).
users =
  for {name, username, role} <- [
        {"Phan Định - nF", "phan.dinh", "user"},
        {"Quyết Cam", "quyet.cam", "user"},
        {"Quân Pancake", "quan.pancake", "user"},
        {"Huy Bùi", "huy.bui", "user"},
        {"Nguyễn Bá Duy", "nguyen.ba.duy", "user"},
        {"Đức Duy", "duc.duy", "user"},
        {"Vũ Nguyễn Văn", "vu.nguyen.van", "admin"},
        {"An Luu", "an.luu", "user"},
        {"truonght", "truonght", "user"},
        {"Trần Xuân Phong", "tran.xuan.phong", "user"},
        {"Tuấn Lee", "tuan.lee", "admin"},
        {"Đình Hiếu", "dinh.hieu", "admin"},
        {"ThuyThuy", "thuythuy", "user"},
        {"Quốc Đại", "quoc.dai", "user"}
      ] do
    Seeds.upsert_user(%{
      "name" => name,
      "username" => username,
      "email" => "#{username}@foodstreet.vn",
      "password" => if(role == "admin", do: "admin123", else: "user123"),
      "role" => role
    })
  end

IO.puts("== Đã tạo #{length(users)} user — quỹ khởi tạo 0đ (admin nạp sau) ==")

IO.puts("== Seeding danh mục ==")

an_sang = Seeds.upsert_category("Ăn sáng", "Đồ ăn sáng")
mixue = Seeds.upsert_category("Mixue", "Kem & trà sữa Mixue")

IO.puts("== Seeding menu ==")

menu_images = %{
  "Xôi xéo" =>
    "https://content.pancake.vn/2-2607/2026/7/1/71c7707d1d7a8be5dcc9b92efa3dde143027a09f.jpg",
  "Xôi lạc" =>
    "https://content.pancake.vn/2-2607/2026/7/1/3a9d6051a117c6153400ae927264e2e91bfe42a7.jpg",
  "Xôi ngô" =>
    "https://content.pancake.vn/2-2607/2026/7/1/411ac696dfb94be264fae09a6185b244022f9b19.jpg",
  "Xôi trứng ruốc" =>
    "https://content.pancake.vn/2-2607/2026/7/1/cb63605cc49475425ffbd883be026894a35ceffe.jpg",
  "Xôi chả ruốc" =>
    "https://content.pancake.vn/2-2607/2026/7/1/0ab7ede15951e8a02c117ad6d567de2731a16994.jpg",
  "Xôi trứng kho thịt chả" =>
    "https://content.pancake.vn/2-2607/2026/7/1/cbcaa083dd163ffec1704fabf8d41797a9964365.jpg",
  "Bánh mì trứng" =>
    "https://content.pancake.vn/2-2607/2026/7/1/79e5436d8c050b5cae185e3bcd74fc9ed824c8bc.jpg",
  "Bánh mì pate" =>
    "https://content.pancake.vn/2-2607/2026/7/1/87c42355d8f6483d1048830c591d0de53e8602d9.jpg",
  "Bánh mì xá xíu" =>
    "https://content.pancake.vn/2-2607/2026/7/1/834bcb34f2445d3e6721ff0295b64cf60c21219c.jpg",
  "Bánh mì pate ruốc" =>
    "https://content.pancake.vn/2-2607/2026/7/1/82cd7d6fafb70c114fe502a431b1978192c29fd3.jpg",
  "Bánh mì trứng ruốc" =>
    "https://content.pancake.vn/2-2607/2026/7/1/7ab05010e0c1fef7512843361e8b12936207b1be.jpg",
  "Bánh mì pate xá xíu" =>
    "https://content.pancake.vn/2-2607/2026/7/1/7ab05010e0c1fef7512843361e8b12936207b1be.jpg",
  "Bánh mì full topping" =>
    "https://content.pancake.vn/2-2607/2026/7/1/2568c0392a2e1c4ac8b7a218939a1bef05c89cc5.jpg",
  "Sandwich" =>
    "https://content.pancake.vn/2-2607/2026/7/1/d8a484c319846002d7be221a0b09b022a5d10666.jpg",
  "Bánh dày giò" =>
    "https://content.pancake.vn/2-2607/2026/7/1/1eae8549dbfb536578a0a753dc5b5ce799c5e7a6.jpg",
  "Bánh dày" =>
    "https://content.pancake.vn/2-2607/2026/7/1/3f96f5298b20ee21c8727793c6ed7457f5025738.jpg",
  "Bánh giò" =>
    "https://content.pancake.vn/2-2607/2026/7/1/3bf4c5d4dbedc404cb946413c6d065e13105844e.jpg",
  "Bánh khoai" =>
    "https://content.pancake.vn/2-2607/2026/7/1/93e2e49a4fa0ec3a98904de9820d8a1f38dcc738.jpg",
  "Bánh rán" =>
    "https://content.pancake.vn/2-2607/2026/7/1/520d62617c0f186d786cda0152aa6320b326c3b2.jpg",
  "Bánh trôi" =>
    "https://content.pancake.vn/2-2607/2026/7/1/06a3d6b430017079ae8fee0a951ef5923b267dd0.jpg",
  "Bánh tẻ" =>
    "https://content.pancake.vn/2-2607/2026/7/1/ab9d6f4bdc70f61b6caa112a8f7fa4bfcb32e538.jpg",
  "Xôi chè" =>
    "https://content.pancake.vn/2-2607/2026/7/1/d0e9cb46f62827171f54c5a25cf993fc15b7f9d2.jpg",
  "Khoai luộc" =>
    "https://content.pancake.vn/2-2607/2026/7/1/cfdf5c80af7f9488eca656a9196c02e1fcabc20c.jpg",
  "Sắn hấp dừa" =>
    "https://content.pancake.vn/2-2607/2026/7/1/0db6542f2e88de477ac12a65fe0f33ed7ccf7312.jpg",
  "Ngô luộc" =>
    "https://content.pancake.vn/2-2607/2026/7/1/1a55faab71bd16f7a35d913926e33a166639c5f5.jpg",
  "Sữa đậu" =>
    "https://content.pancake.vn/2-2607/2026/7/1/50b481a9c13cfdc72a3278d2ae7f83421514a887.jpg",
  "Nước đậu đen" =>
    "https://content.pancake.vn/2-2607/2026/7/1/371f9d1680356c3758d0d71bbd5f7fb97833a74e.jpg",
  "Cơm cuộn" =>
    "https://content.pancake.vn/2-2607/2026/7/1/c9266fdf4c81de40df6c27bd946354f6984ffb14.jpg",
  "Xôi chả thịt kho" =>
    "https://content.pancake.vn/2-2607/2026/7/1/48abe55d1a5c30429630576badfc9e93f1993071.jpg",
  "Giò cây" =>
    "https://content.pancake.vn/2-2607/2026/7/1/d1fd8f02218725f6b78c625c50bff1b420c221ff.jpg",
  "Kem ốc quế" =>
    "https://content.pancake.vn/2-2607/2026/7/1/fe1ed6588ffe05e186ef308e97fb8b496f20e5ae.jpg",
  "Lucky sundae O-coco" =>
    "https://content.pancake.vn/2-2607/2026/7/1/9212b70eb60465dcf7dc99f49672fb1d6df354ac.jpg",
  "Super Sundae trân châu đường đen" =>
    "https://content.pancake.vn/2-2607/2026/7/1/62a5d8e3a95463d2de7d1b369c2fa972a09df1a7.jpg",
  "Lucky sundae dâu tây" =>
    "https://content.pancake.vn/2-2607/2026/7/1/b91ceb65db756e802d8fe3cc36d3b614e4cce973.jpg",
  "Super Sundae kiwi lô hội" =>
    "https://content.pancake.vn/2-2607/2026/7/1/a93b67211bc48b0d15af38089de7df781b9b4f6a.jpg",
  "Super Sundae đào hồng" =>
    "https://content.pancake.vn/2-2607/2026/7/1/eeb43b50b04d4e78aa6802c3896992aaf0c21a1d.jpg",
  "Super Sundae xoài" =>
    "https://content.pancake.vn/2-2607/2026/7/1/74726045f95d0153ab3fd3dd5f366fe035405ec6.jpg",
  "Super Sundae đào vàng" =>
    "https://content.pancake.vn/2-2607/2026/7/1/eeb43b50b04d4e78aa6802c3896992aaf0c21a1d.jpg",
  "Nước chanh tươi lạnh" =>
    "https://content.pancake.vn/2-2607/2026/7/1/0f4bc7272f02cda69a9bc30b4574ae0c40e43c66.jpg",
  "Trà đào dâu tây" =>
    "https://content.pancake.vn/2-2607/2026/7/1/717ab20d06124cd38e8083a7ae52bf4b1099e296.jpg",
  "Trà xoài chanh leo" =>
    "https://content.pancake.vn/2-2607/2026/7/1/f82ffd14d0ea65879948c863b6a4f383440d5c41.jpg",
  "Chanh leo bách hương" =>
    "https://content.pancake.vn/2-2607/2026/7/1/3f1ba38671736cbd5cee0f355fd03546421cafd4.jpg",
  "Trà xanh chanh" =>
    "https://content.pancake.vn/2-2607/2026/7/1/e98c954d225446421ebfd4de8f03f180cea1eacb.jpg",
  "Trà xanh kiwi" =>
    "https://content.pancake.vn/2-2607/2026/7/1/bf90e6e97096d934797bcefc57224dc3ba501ca1.jpg",
  "Trà đào bigsize" =>
    "https://content.pancake.vn/2-2607/2026/7/1/4dd43b6887331eea929bb5ca0a83770cb423c6b3.jpg",
  "Trà xanh hoa đào" =>
    "https://content.pancake.vn/2-2607/2026/7/1/776483d8d94342dc2b300008452b53d8c95f472e.jpg",
  "Dương chi cam lộ" =>
    "https://content.pancake.vn/2-2607/2026/7/1/b2676e247d4a59fa48a156bd393d87fa2bd72f2b.jpg",
  "Trà sữa trân châu đường đen" =>
    "https://content.pancake.vn/2-2607/2026/7/1/b8763f752369b0c584278a37cf4f9acfb5d8ab17.jpg",
  "Trà sữa Caramel" =>
    "https://content.pancake.vn/2-2607/2026/7/1/76444595c49c6df222e021e8716d7305046e5146.jpg",
  "Trà sữa trân châu" =>
    "https://content.pancake.vn/2-2607/2026/7/1/c7e350303b8b2af58b30a8e4f2528f969ed1b0f3.jpg",
  "Sữa thạch Kiwi Kiwi" =>
    "https://content.pancake.vn/2-2607/2026/7/1/b7be976b0fa53b2fab67792b670536b3789a6ed5.jpg",
  "Sữa thạch Dâu tây" =>
    "https://content.pancake.vn/2-2607/2026/7/1/1a95e4dcdb59ac7059fcf1668dd7402fca9063bb.jpg",
  "Trà sữa 2J" =>
    "https://content.pancake.vn/2-2607/2026/7/1/70df487622ebd99768c93a7974e4d026872f7770.jpg",
  "Trà sữa thạch dừa" =>
    "https://content.pancake.vn/2-2607/2026/7/1/2079ad9fb60e3252270001f0dd2e12710a6f4873.jpg",
  "Trà sữa đường đen" =>
    "https://content.pancake.vn/2-2607/2026/7/1/b8763f752369b0c584278a37cf4f9acfb5d8ab17.jpg",
  "Trà sữa O-coco" =>
    "https://content.pancake.vn/2-2607/2026/7/1/a51476a0c34e8ee9069bdc65f1ebc89abdf0f180.jpg",
  "Latte đường đen" =>
    "https://content.pancake.vn/2-2607/2026/7/1/17feea0360e3764ca9449635731e122b197da154.jpg",
  "Mocha" =>
    "https://content.pancake.vn/2-2607/2026/7/1/f6c7b118fd63b49689350c26a5d55dae9b0c7f97.jpg",
  "Latte" =>
    "https://content.pancake.vn/2-2607/2026/7/1/661b4975e395dccc38fe17681941d1cfd51ddfa4.jpg",
  "Cafe Latte Kem tươi" =>
    "https://content.pancake.vn/2-2607/2026/7/1/e919fac1f1f3f985bb9a9b1c9f4d13fc4b2ba8b7.jpg",
  "Cafe Mocha Kem tươi" =>
    "https://content.pancake.vn/2-2607/2026/7/1/ab40781be69c27ef693008b76ac517a72133ec1c.jpg",
  "Cafe Latte Caramel Kem tươi" =>
    "https://content.pancake.vn/2-2607/2026/7/1/c0c3858dd8a65c8ddddf91e8b24b4802b44dbf93.jpg",
  "Trà chanh lô hội" =>
    "https://content.pancake.vn/2-2607/2026/7/1/1d8c9b286ad773b5fe05001491ae439177a180b4.jpg",
  "Trà chanh dâu tây" =>
    "https://content.pancake.vn/2-2607/2026/7/1/82542903c3bce150482283b6f1d3389757bc2cfc.jpg",
  "Trà sữa bá vương" =>
    "https://content.pancake.vn/2-2607/2026/7/1/c7e350303b8b2af58b30a8e4f2528f969ed1b0f3.jpg",
  "Hồng trà Latte" =>
    "https://content.pancake.vn/2-2607/2026/7/1/e5805eff2cf854396bcbcae0b518651a92b1b8b3.jpg",
  "Topping Trân châu" =>
    "https://content.pancake.vn/2-2607/2026/7/1/9df572e8d2f8fc252931a255f0b6623821d27e34.jpg",
  "Topping Thạch dừa" =>
    "https://content.pancake.vn/2-2607/2026/7/1/c2c300d36ab36bb9ed59b99e135600b618694ee6.jpg",
  "Topping Vụn O-coco" =>
    "https://content.pancake.vn/2-2607/2026/7/1/68118bdf2a91f43a0a60a165fd28ca9d80455903.jpg",
  "Topping Thạch đường đen" =>
    "https://content.pancake.vn/2-2607/2026/7/1/a4b64e8c95915be482fa429bf44ba8bed61c3dc3.jpg",
  "Topping Thạch đào" =>
    "https://content.pancake.vn/2-2607/2026/7/1/59fb470dd5e666876b6f37fbec023ba63e43f5ca.jpg",
  "Topping Lô hội" =>
    "https://content.pancake.vn/2-2607/2026/7/1/1952b3692ff222b6b3996381597aef01cc0f14af.jpg",
  "Topping Vụn ốc quế" =>
    "https://content.pancake.vn/2-2607/2026/7/1/aa71b929cfc4856ee080ef113091aba4c3e10e90.jpg"
}

[
  %{"name" => "Xôi xéo", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi lạc", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi ngô", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi trứng ruốc", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Xôi chả ruốc", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Xôi trứng kho thịt chả", "price" => "35000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì trứng", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì pate", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì xá xíu", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì pate ruốc", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì trứng ruốc", "price" => "25000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì pate xá xíu", "price" => "25000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì full topping", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Sandwich", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh dày giò", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh dày", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh giò", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh khoai", "price" => "12000", "category_id" => an_sang.id},
  %{"name" => "Bánh rán", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh trôi", "price" => "12000", "category_id" => an_sang.id},
  %{"name" => "Bánh tẻ", "price" => "8000", "category_id" => an_sang.id},
  %{"name" => "Xôi chè", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Khoai luộc", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Sắn hấp dừa", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Ngô luộc", "price" => "10000", "category_id" => an_sang.id},
  %{"name" => "Sữa đậu", "price" => "10000", "category_id" => an_sang.id},
  %{"name" => "Nước đậu đen", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Cơm cuộn", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi chả thịt kho", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Giò cây", "price" => "12000", "category_id" => an_sang.id},
  # Mixue — Dòng kem
  %{"name" => "Kem ốc quế", "price" => "10000", "category_id" => mixue.id},
  %{"name" => "Lucky sundae O-coco", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae trân châu đường đen", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Lucky sundae dâu tây", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae kiwi lô hội", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae đào hồng", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae xoài", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae đào vàng", "price" => "25000", "category_id" => mixue.id},
  # Mixue — Trà hoa quả
  %{"name" => "Nước chanh tươi lạnh", "price" => "15000", "category_id" => mixue.id},
  %{"name" => "Trà đào dâu tây", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà xoài chanh leo", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Chanh leo bách hương", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà xanh chanh", "price" => "15000", "category_id" => mixue.id},
  %{"name" => "Trà xanh kiwi", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà đào bigsize", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà xanh hoa đào", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Dương chi cam lộ", "price" => "28000", "category_id" => mixue.id},
  # Mixue — Trà sữa
  %{"name" => "Trà sữa trân châu đường đen", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa Caramel", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa trân châu", "price" => "30000", "category_id" => mixue.id},
  %{"name" => "Sữa thạch Kiwi Kiwi", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Sữa thạch Dâu tây", "price" => "25000", "category_id" => mixue.id},
  %{
    "name" => "Trà sữa 2J",
    "description" => "Chọn 2 topping",
    "price" => "30000",
    "category_id" => mixue.id
  },
  %{"name" => "Trà sữa thạch dừa", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa đường đen", "price" => "30000", "category_id" => mixue.id},
  %{"name" => "Trà sữa O-coco", "price" => "28000", "category_id" => mixue.id},
  # Mixue — Cà phê
  %{"name" => "Latte đường đen", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Mocha", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Latte", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Cafe Latte Kem tươi", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Cafe Mocha Kem tươi", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Cafe Latte Caramel Kem tươi", "price" => "25000", "category_id" => mixue.id},
  # Mixue — Đặc biệt (banner)
  %{"name" => "Trà chanh lô hội", "price" => "17000", "category_id" => mixue.id},
  %{"name" => "Trà chanh dâu tây", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa bá vương", "price" => "30000", "category_id" => mixue.id},
  %{"name" => "Hồng trà Latte", "price" => "25000", "category_id" => mixue.id},
  # Mixue — Topping (bán như món thường, +3.000đ)
  %{"name" => "Topping Trân châu", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Thạch dừa", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Vụn O-coco", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Thạch đường đen", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Thạch đào", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Lô hội", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Vụn ốc quế", "price" => "3000", "category_id" => mixue.id}
]
|> Enum.each(fn attrs ->
  attrs
  |> Map.put("image_url", menu_images[attrs["name"]])
  |> Seeds.upsert_menu()
end)

IO.puts("== Seeding đợt đặt nhóm mẫu ==")

today = Date.utc_today()

unless Repo.one(
         from g in GroupOrder, where: g.order_date == ^today and g.category_id == ^an_sang.id
       ) do
  {:ok, go} =
    Ordering.create_group_order(
      %{
        "title" => "Ăn sáng hôm nay",
        "order_date" => Date.to_iso8601(today),
        "category_id" => an_sang.id,
        "note" => "Chốt đơn lúc 8h sáng"
      },
      admin
    )

  IO.puts("  + đợt: #{go.title} (#{go.order_date}) - danh mục Ăn sáng")
end

IO.puts("\n✅ Seed xong.")
IO.puts("   Admin:  admin@foodstreet.vn / admin123  (+ các admin khác / admin123)")
IO.puts("   User:   <username>@foodstreet.vn / user123")
