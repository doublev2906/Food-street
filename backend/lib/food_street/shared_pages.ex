defmodule FoodStreet.SharedPages do
  @moduledoc """
  Trang HTML chia sẻ: file nằm trong folder `share/` (root repo, có thể chia thư mục con)
  và được backend serve ở `/share/<đường dẫn>` — phải đăng nhập, xem
  `FoodStreetWeb.ShareController`.

  Có 2 đường đưa file lên server:
    * Admin upload qua UI (module này ghi file vào `share_dir`).
    * `make share` dưới máy dev (rsync thẳng folder `share/` lên server).

  Dữ liệu người xem nhập trên trang (input, select, localStorage giả…) lưu trong bảng
  `shared_page_states`, dùng chung cho mọi người, giữ nguyên khi ghi đè file.

  Folder gốc cấu hình qua `config :food_street, :share_dir` (prod: env `SHARE_DIR`).
  """

  import Ecto.Query

  alias FoodStreet.Repo
  alias FoodStreet.SharedPages.State

  @allowed_exts ~w(.html .htm)
  @max_bytes 20 * 1024 * 1024
  @max_name_length 100

  @type entry :: %{
          name: String.t(),
          path: String.t(),
          type: :file | :folder,
          size: non_neg_integer(),
          updated_at: String.t(),
          url: String.t()
        }

  def max_bytes, do: @max_bytes
  def allowed_exts, do: @allowed_exts

  def dir, do: Application.fetch_env!(:food_street, :share_dir)

  # ---------------------------------------------------------------------------
  # Đường dẫn
  # ---------------------------------------------------------------------------

  @doc """
  Chuẩn hoá đường dẫn tương đối (chuỗi `a/b/c.html` hoặc list segment) và trả về đường
  dẫn tuyệt đối trong folder chia sẻ. Chặn `..`, file ẩn, ký tự lạ → `{:error, :not_found}`.
  """
  @spec resolve(String.t() | [String.t()] | nil) ::
          {:ok, %{rel: String.t(), abs: String.t()}} | {:error, :not_found}
  def resolve(nil), do: resolve("")
  def resolve(rel) when is_binary(rel), do: rel |> String.split("/", trim: true) |> resolve()

  def resolve(segments) when is_list(segments) do
    segments = Enum.reject(segments, &(&1 == ""))

    if Enum.all?(segments, &plain_segment?/1) do
      rel = Enum.join(segments, "/")
      {:ok, %{rel: rel, abs: Path.join([dir() | segments])}}
    else
      {:error, :not_found}
    end
  end

  @doc "URL xem (`/share/...`) cho đường dẫn tương đối; thư mục có `/` ở cuối."
  def url_for(rel, type \\ :file) do
    encoded = rel |> String.split("/", trim: true) |> Enum.map_join("/", &encode_segment/1)
    suffix = if type == :folder and encoded != "", do: "/", else: ""
    "/share/" <> encoded <> suffix
  end

  defp encode_segment(seg), do: URI.encode(seg, &URI.char_unreserved?/1)

  # ---------------------------------------------------------------------------
  # Liệt kê / tạo thư mục / upload / xoá
  # ---------------------------------------------------------------------------

  @doc "Nội dung 1 thư mục: thư mục con (A→Z) + file (mới sửa trước), bỏ file ẩn."
  @spec list(String.t() | nil) ::
          {:ok, %{dir: String.t(), folders: [entry()], files: [entry()]}} | {:error, :not_found}
  def list(dir_rel \\ "") do
    with {:ok, %{rel: rel, abs: abs}} <- resolve(dir_rel),
         {:ok, names} <- ls(abs, rel) do
      entries =
        names
        |> Enum.reject(&hidden?/1)
        |> Enum.flat_map(fn name ->
          case entry(join(rel, name)) do
            {:ok, e} -> [e]
            :error -> []
          end
        end)

      {folders, files} = Enum.split_with(entries, &(&1.type == :folder))

      {:ok,
       %{
         dir: rel,
         folders: Enum.sort_by(folders, & &1.name),
         files: Enum.sort_by(files, & &1.updated_at, :desc)
       }}
    end
  end

  # Thư mục gốc chưa tồn tại (chưa ai upload) coi như rỗng.
  defp ls(abs, rel) do
    case File.ls(abs) do
      {:ok, names} -> {:ok, names}
      {:error, :enoent} when rel == "" -> {:ok, []}
      _ -> {:error, :not_found}
    end
  end

  @doc "Thông tin 1 file / thư mục theo đường dẫn tương đối."
  @spec entry(String.t()) :: {:ok, entry()} | :error
  def entry(rel) do
    with {:ok, %{rel: rel, abs: abs}} <- resolve(rel),
         {:ok, %File.Stat{type: type, size: size, mtime: mtime}}
         when type in [:regular, :directory] <-
           File.stat(abs, time: :posix) do
      type = if type == :directory, do: :folder, else: :file

      {:ok,
       %{
         name: Path.basename(rel),
         path: rel,
         type: type,
         size: if(type == :folder, do: 0, else: size),
         updated_at: mtime |> DateTime.from_unix!() |> DateTime.to_iso8601(),
         url: url_for(rel, type)
       }}
    else
      _ -> :error
    end
  end

  @doc "Tạo thư mục con (tên được chuẩn hoá như tên file)."
  @spec create_folder(String.t() | nil, String.t() | nil) :: {:ok, entry()} | {:error, atom()}
  def create_folder(parent_rel, name) do
    with {:ok, %{rel: parent, abs: parent_abs}} <- resolve(parent_rel),
         :ok <- ensure_dir(parent_abs, parent),
         {:ok, folder} <- sanitize_folder_name(name) do
      abs = Path.join(parent_abs, folder)

      case File.mkdir(abs) do
        :ok ->
          inherit_owner(abs)
          entry(join(parent, folder))

        {:error, :eexist} ->
          {:error, :already_exists}

        {:error, _} ->
          {:error, :write_failed}
      end
    end
  end

  @doc """
  Lưu 1 file upload vào thư mục `dir_rel`. Tên file được chuẩn hoá (bỏ dấu, chữ thường,
  chỉ giữ `a-z0-9._-`). Trùng tên: mặc định báo `:already_exists`, `overwrite: true` thì
  ghi đè (dữ liệu người xem đã nhập trên trang vẫn được giữ).
  """
  @spec save(Plug.Upload.t(), String.t() | nil, keyword()) :: {:ok, map()} | {:error, atom()}
  def save(%Plug.Upload{path: tmp_path, filename: filename}, dir_rel \\ "", opts \\ []) do
    with {:ok, %{rel: rel, abs: dir_abs}} <- resolve(dir_rel),
         :ok <- ensure_dir(dir_abs, rel),
         {:ok, name} <- sanitize_name(filename),
         {:ok, %File.Stat{size: size}} <- File.stat(tmp_path),
         :ok <- check_size(size) do
      dest = Path.join(dir_abs, name)
      replaced? = File.exists?(dest)

      if replaced? and not Keyword.get(opts, :overwrite, false) do
        {:error, :already_exists}
      else
        write(tmp_path, dest, join(rel, name), replaced?)
      end
    end
  end

  # Ghi ra file tạm (ẩn) rồi rename để không bao giờ serve file ghi dở.
  defp write(tmp_path, dest, rel, replaced?) do
    tmp_dest =
      Path.join(Path.dirname(dest), ".upload-#{System.unique_integer([:positive])}")

    with :ok <- File.cp(tmp_path, tmp_dest),
         :ok <- File.chmod(tmp_dest, 0o644),
         _ <- inherit_owner(tmp_dest),
         :ok <- File.rename(tmp_dest, dest),
         {:ok, e} <- entry(rel) do
      {:ok, Map.put(e, :replaced, replaced?)}
    else
      _ ->
        File.rm(tmp_dest)
        {:error, :write_failed}
    end
  end

  @doc "Xoá 1 file hoặc cả thư mục (kèm toàn bộ bên trong) + dữ liệu đã nhập trên các trang đó."
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(rel) when is_binary(rel) do
    with {:ok, %{rel: rel, abs: abs}} when rel != "" <- resolve(rel),
         {:ok, %File.Stat{type: type}} <- File.stat(abs) do
      case type do
        :regular ->
          File.rm!(abs)
          Repo.delete_all(from s in State, where: s.page_path == ^rel)
          :ok

        :directory ->
          File.rm_rf!(abs)
          prefix = String.replace(rel, ~r/[\\%_]/, "\\\\\\0") <> "/%"
          Repo.delete_all(from s in State, where: like(s.page_path, ^prefix))
          :ok

        _ ->
          {:error, :not_found}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def delete(_), do: {:error, :not_found}

  # ---------------------------------------------------------------------------
  # Dữ liệu người xem nhập trên trang (dùng chung)
  # ---------------------------------------------------------------------------

  @max_key_length 500
  @max_value_bytes 512 * 1024

  @doc "Dữ liệu đã lưu của 1 trang (map key -> giá trị), chưa có thì `%{}`."
  @spec get_state(String.t()) :: map()
  def get_state(page_path) do
    Repo.one(from s in State, where: s.page_path == ^page_path, select: s.data) || %{}
  end

  @doc """
  Gộp `patch` vào dữ liệu của trang (atomic, ai lưu sau thì thắng theo từng key).
  Giá trị `nil` = xoá key đó.
  """
  @spec merge_state(String.t(), map(), binary() | nil) :: :ok | {:error, :invalid_patch}
  def merge_state(page_path, patch, user_id) when is_map(patch) and map_size(patch) > 0 do
    if Enum.all?(patch, &valid_pair?/1) do
      now = DateTime.utc_now(:second)
      initial = patch |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

      Repo.insert!(
        %State{
          page_path: page_path,
          data: initial,
          updated_by_id: user_id,
          inserted_at: now,
          updated_at: now
        },
        conflict_target: :page_path,
        on_conflict:
          from(s in State,
            update: [
              set: [
                data: fragment("jsonb_strip_nulls(? || ?)", s.data, type(^patch, :map)),
                updated_by_id: ^user_id,
                updated_at: ^now
              ]
            ]
          )
      )

      :ok
    else
      {:error, :invalid_patch}
    end
  end

  def merge_state(_page_path, _patch, _user_id), do: {:error, :invalid_patch}

  defp valid_pair?({k, v}) when is_binary(k) and byte_size(k) <= @max_key_length do
    case v do
      nil -> true
      b when is_boolean(b) -> true
      s when is_binary(s) -> byte_size(s) <= @max_value_bytes
      l when is_list(l) -> Enum.all?(l, &(is_binary(&1) and byte_size(&1) <= @max_value_bytes))
      _ -> false
    end
  end

  defp valid_pair?(_), do: false

  # ---------------------------------------------------------------------------
  # Chuẩn hoá tên
  # ---------------------------------------------------------------------------

  @doc """
  Chuẩn hoá tên file upload thành tên an toàn cho URL.

      iex> FoodStreet.SharedPages.sanitize_name("Báo cáo tháng 11.HTML")
      {:ok, "bao-cao-thang-11.html"}
  """
  @spec sanitize_name(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_extension}
  def sanitize_name(filename) when is_binary(filename) do
    # Trình duyệt cũ có thể gửi kèm đường dẫn Windows (C:\fakepath\a.html).
    base = filename |> String.replace("\\", "/") |> Path.basename()
    ext = base |> Path.extname() |> String.downcase()

    if ext in @allowed_exts do
      stem = base |> Path.rootname() |> slugify()
      {:ok, if(stem == "", do: "page", else: stem) <> ext}
    else
      {:error, :invalid_extension}
    end
  end

  def sanitize_name(_), do: {:error, :invalid_extension}

  @doc """
  Chuẩn hoá tên thư mục.

      iex> FoodStreet.SharedPages.sanitize_folder_name("Báo cáo Q4")
      {:ok, "bao-cao-q4"}
  """
  @spec sanitize_folder_name(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_name}
  def sanitize_folder_name(name) when is_binary(name) do
    case slugify(name) do
      "" -> {:error, :invalid_name}
      slug -> {:ok, slug}
    end
  end

  def sanitize_folder_name(_), do: {:error, :invalid_name}

  defp slugify(str) do
    str
    |> String.replace(["đ", "Đ"], "d")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]+/, "-")
    |> String.replace(~r/-{2,}/, "-")
    |> String.slice(0, @max_name_length)
    # Bỏ dấu chấm/gạch ở đầu-cuối: tránh tạo file ẩn (.abc), "..", hoặc tên xấu.
    |> String.replace(~r/^[.-]+|[.-]+$/, "")
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp check_size(0), do: {:error, :empty_file}
  defp check_size(size) when size > @max_bytes, do: {:error, :file_too_large}
  defp check_size(_), do: :ok

  # Thư mục gốc tự tạo khi cần; thư mục con phải có sẵn (tạo qua create_folder).
  defp ensure_dir(abs, ""), do: File.mkdir_p(abs)

  defp ensure_dir(abs, _rel) do
    if File.dir?(abs), do: :ok, else: {:error, :not_found}
  end

  # Backend (Docker) chạy bằng root: file/thư mục mới cho cùng chủ với folder gốc share/
  # (user deploy trên host) để `make share` (rsync bằng user đó) vẫn ghi đè/ghi vào được.
  defp inherit_owner(path) do
    with {:ok, %File.Stat{uid: uid, gid: gid}} <- File.stat(dir()) do
      File.chown(path, uid)
      File.chgrp(path, gid)
    end

    :ok
  end

  defp join("", name), do: name
  defp join(rel, name), do: rel <> "/" <> name

  defp hidden?(name), do: String.starts_with?(name, ".")

  # 1 segment đường dẫn hợp lệ: không rỗng, không ẩn (".", "..", ".git"…), không chứa
  # dấu phân cách / ký tự NUL.
  defp plain_segment?(seg) do
    seg != "" and not hidden?(seg) and not String.contains?(seg, ["/", "\\", <<0>>])
  end
end
