defmodule FoodStreet.SharedPagesTest do
  # Dùng chung 1 folder tạm (config/test.exs :share_dir) nên không chạy async.
  use ExUnit.Case, async: false

  alias FoodStreet.SharedPages

  doctest FoodStreet.SharedPages

  setup do
    File.rm_rf!(SharedPages.dir())
    on_exit(fn -> File.rm_rf!(SharedPages.dir()) end)
    :ok
  end

  defp upload(filename, content) do
    path = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: filename, content_type: "text/html"}
  end

  describe "sanitize_name/1" do
    test "bỏ dấu tiếng Việt, chữ thường, thay ký tự lạ bằng gạch" do
      assert SharedPages.sanitize_name("Đơn hàng  (bản cuối)!.html") ==
               {:ok, "don-hang-ban-cuoi.html"}
    end

    test "chặn path traversal và file ẩn" do
      assert SharedPages.sanitize_name("../../etc/evil.html") == {:ok, "evil.html"}
      assert SharedPages.sanitize_name("C:\\fakepath\\report.htm") == {:ok, "report.htm"}
      assert SharedPages.sanitize_name(".hidden.html") == {:ok, "hidden.html"}
      assert SharedPages.sanitize_name("...html") == {:ok, "page.html"}
    end

    test "chỉ nhận .html / .htm" do
      assert SharedPages.sanitize_name("script.js") == {:error, :invalid_extension}
      assert SharedPages.sanitize_name("noext") == {:error, :invalid_extension}
      assert SharedPages.sanitize_name("x.html.php") == {:error, :invalid_extension}
      assert SharedPages.sanitize_name(nil) == {:error, :invalid_extension}
    end

    test "cắt tên quá dài" do
      {:ok, name} = SharedPages.sanitize_name(String.duplicate("a", 300) <> ".html")
      assert String.length(name) <= 105
    end
  end

  describe "save/1, list/0, delete/1" do
    test "lưu file, liệt kê kèm URL, ghi đè khi trùng tên" do
      assert {:ok, page} = SharedPages.save(upload("Báo cáo.html", "<h1>v1</h1>"))
      assert %{name: "bao-cao.html", url: "/share/bao-cao.html", size: 11, replaced: false} = page
      assert File.read!(Path.join(SharedPages.dir(), "bao-cao.html")) == "<h1>v1</h1>"

      assert {:ok, %{replaced: true}} = SharedPages.save(upload("bao-cao.html", "<h1>v2</h1>"))
      assert File.read!(Path.join(SharedPages.dir(), "bao-cao.html")) == "<h1>v2</h1>"

      assert [%{name: "bao-cao.html"}] = SharedPages.list()
    end

    test "list bỏ qua file ẩn và thư mục con, URL encode tên file lạ (rsync lên)" do
      File.mkdir_p!(Path.join(SharedPages.dir(), "assets"))
      File.write!(Path.join(SharedPages.dir(), ".gitkeep"), "")
      File.write!(Path.join(SharedPages.dir(), "tên có dấu.html"), "x")

      assert [%{name: "tên có dấu.html", url: url}] = SharedPages.list()
      assert url == "/share/t%C3%AAn%20c%C3%B3%20d%E1%BA%A5u.html"
    end

    test "từ chối file rỗng / sai đuôi" do
      assert SharedPages.save(upload("a.html", "")) == {:error, :empty_file}
      assert SharedPages.save(upload("a.txt", "x")) == {:error, :invalid_extension}
      assert SharedPages.list() == []
    end

    test "delete chỉ xoá file trong folder, không cho thoát ra ngoài" do
      {:ok, _} = SharedPages.save(upload("a.html", "x"))
      outside = Path.join(Path.dirname(SharedPages.dir()), "outside-share-test.html")
      File.write!(outside, "keep")
      on_exit(fn -> File.rm(outside) end)

      assert SharedPages.delete("../outside-share-test.html") == {:error, :not_found}
      assert SharedPages.delete(".") == {:error, :not_found}
      assert SharedPages.delete("missing.html") == {:error, :not_found}
      assert File.exists?(outside)

      assert SharedPages.delete("a.html") == :ok
      assert SharedPages.list() == []
    end
  end
end
