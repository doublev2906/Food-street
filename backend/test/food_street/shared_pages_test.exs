defmodule FoodStreet.SharedPagesTest do
  # Dùng chung 1 folder tạm (config/test.exs :share_dir) nên không chạy async.
  use FoodStreet.DataCase, async: false

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

  defp read(rel), do: File.read!(Path.join(SharedPages.dir(), rel))

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
      assert SharedPages.sanitize_name("x.html.php") == {:error, :invalid_extension}
      assert SharedPages.sanitize_name(nil) == {:error, :invalid_extension}
    end

    test "cắt tên quá dài" do
      {:ok, name} = SharedPages.sanitize_name(String.duplicate("a", 300) <> ".html")
      assert String.length(name) <= 105
    end
  end

  describe "resolve/1" do
    test "chặn .., file ẩn, NUL; nhận tên có dấu/khoảng trắng (rsync lên)" do
      assert {:ok, %{rel: "a/b c/đ.html"}} = SharedPages.resolve("a/b c/đ.html")
      assert {:ok, %{rel: ""}} = SharedPages.resolve(nil)
      assert {:ok, %{rel: "a/b"}} = SharedPages.resolve("/a//b/")
      assert SharedPages.resolve("../x.html") == {:error, :not_found}
      assert SharedPages.resolve("a/../../x") == {:error, :not_found}
      assert SharedPages.resolve(".git/config") == {:error, :not_found}
      assert SharedPages.resolve(["a", "b\\c"]) == {:error, :not_found}
      assert SharedPages.resolve("a/\0b") == {:error, :not_found}
    end
  end

  describe "thư mục + upload" do
    test "tạo thư mục (chuẩn hoá tên), upload vào thư mục, list theo thư mục" do
      assert {:ok, %{path: "bao-cao-q4", type: :folder, url: "/share/bao-cao-q4/"}} =
               SharedPages.create_folder("", "Báo cáo Q4")

      assert SharedPages.create_folder("", "bao cao q4") == {:error, :already_exists}
      assert SharedPages.create_folder("", "...") == {:error, :invalid_name}
      assert SharedPages.create_folder("khong-co", "x") == {:error, :not_found}

      assert {:ok, %{path: "bao-cao-q4/tuan-1", type: :folder}} =
               SharedPages.create_folder("bao-cao-q4", "Tuần 1")

      assert {:ok, %{path: "bao-cao-q4/ke-hoach.html", url: "/share/bao-cao-q4/ke-hoach.html"}} =
               SharedPages.save(upload("Kế hoạch.html", "<p>x</p>"), "bao-cao-q4")

      assert {:ok, %{dir: "", folders: [%{name: "bao-cao-q4"}], files: []}} = SharedPages.list("")

      assert {:ok, %{folders: [%{name: "tuan-1"}], files: [%{name: "ke-hoach.html"}]}} =
               SharedPages.list("bao-cao-q4")

      assert SharedPages.list("khong-co") == {:error, :not_found}
      assert SharedPages.save(upload("a.html", "x"), "khong-co") == {:error, :not_found}
    end

    test "trùng tên: mặc định báo đã tồn tại, overwrite: true mới ghi đè" do
      assert {:ok, %{replaced: false}} = SharedPages.save(upload("a.html", "v1"))
      assert SharedPages.save(upload("a.html", "v2")) == {:error, :already_exists}
      assert read("a.html") == "v1"

      assert {:ok, %{replaced: true}} =
               SharedPages.save(upload("a.html", "v2"), "", overwrite: true)

      assert read("a.html") == "v2"
    end

    test "list bỏ file ẩn, URL encode tên lạ" do
      File.mkdir_p!(SharedPages.dir())
      File.write!(Path.join(SharedPages.dir(), ".gitkeep"), "")
      File.write!(Path.join(SharedPages.dir(), "tên có dấu.html"), "x")

      assert {:ok, %{files: [%{name: "tên có dấu.html", url: url}]}} = SharedPages.list()
      assert url == "/share/t%C3%AAn%20c%C3%B3%20d%E1%BA%A5u.html"
    end

    test "từ chối file rỗng / sai đuôi" do
      assert SharedPages.save(upload("a.html", "")) == {:error, :empty_file}
      assert SharedPages.save(upload("a.txt", "x")) == {:error, :invalid_extension}
    end
  end

  describe "delete/1" do
    test "xoá file / cả thư mục kèm dữ liệu đã nhập, không cho thoát ra ngoài, không xoá gốc" do
      {:ok, _} = SharedPages.create_folder("", "dir")
      {:ok, _} = SharedPages.save(upload("a.html", "x"), "dir")
      {:ok, _} = SharedPages.save(upload("b.html", "x"))
      :ok = SharedPages.merge_state("dir/a.html", %{"k" => "1"}, nil)
      :ok = SharedPages.merge_state("b.html", %{"k" => "2"}, nil)
      :ok = SharedPages.merge_state("dir_x/a.html", %{"k" => "3"}, nil)

      outside = Path.join(Path.dirname(SharedPages.dir()), "outside-share-test.html")
      File.write!(outside, "keep")
      on_exit(fn -> File.rm(outside) end)

      assert SharedPages.delete("../outside-share-test.html") == {:error, :not_found}
      assert SharedPages.delete("") == {:error, :not_found}
      assert SharedPages.delete("missing.html") == {:error, :not_found}
      assert File.exists?(outside)

      assert SharedPages.delete("b.html") == :ok
      assert SharedPages.get_state("b.html") == %{}

      assert SharedPages.delete("dir") == :ok
      assert {:ok, %{folders: [], files: []}} = SharedPages.list()
      assert SharedPages.get_state("dir/a.html") == %{}
      # "_" trong LIKE được escape: thư mục "dir" không xoá nhầm "dir_x/..."
      assert SharedPages.get_state("dir_x/a.html") == %{"k" => "3"}
    end
  end

  describe "merge_state/3" do
    test "gộp theo key, nil = xoá key, giữ nguyên khi ghi đè file" do
      assert SharedPages.get_state("a.html") == %{}

      :ok =
        SharedPages.merge_state("a.html", %{"f:#ten" => "An", "f:#ok" => true, "x" => nil}, nil)

      :ok = SharedPages.merge_state("a.html", %{"f:#ten" => "Bình", "r:size" => "L"}, nil)
      :ok = SharedPages.merge_state("a.html", %{"f:#ok" => nil, "f:#nhieu" => ["a", "b"]}, nil)

      assert SharedPages.get_state("a.html") ==
               %{"f:#ten" => "Bình", "r:size" => "L", "f:#nhieu" => ["a", "b"]}

      {:ok, _} = SharedPages.save(upload("a.html", "v1"))
      {:ok, _} = SharedPages.save(upload("a.html", "v2"), "", overwrite: true)
      assert SharedPages.get_state("a.html")["f:#ten"] == "Bình"
    end

    test "từ chối patch sai kiểu" do
      assert SharedPages.merge_state("a.html", %{"k" => %{"nested" => 1}}, nil) ==
               {:error, :invalid_patch}

      assert SharedPages.merge_state("a.html", %{"k" => 1}, nil) == {:error, :invalid_patch}
      assert SharedPages.merge_state("a.html", %{}, nil) == {:error, :invalid_patch}
      assert SharedPages.merge_state("a.html", "x", nil) == {:error, :invalid_patch}
    end
  end
end
