defmodule FoodStreetWeb.ShareController do
  @moduledoc """
  Serve trang HTML chia sẻ ở `/share/<đường dẫn>` (Caddy proxy `/share/*` sang đây).

    * Phải đăng nhập (cookie `fs_share`, xem `FoodStreetWeb.ShareAuth`); chưa thì redirect
      `/login?next=<trang đang mở>`.
    * Thư mục: có `index.html` thì serve file đó, không thì hiện trang danh sách.
    * File `.html`: chèn script tự lưu dữ liệu người xem nhập (`priv/share/inject.js`)
      kèm dữ liệu đã lưu + token để gọi `POST /api/share_state`.
    * Mọi response kèm CSP `sandbox` → JS của trang chạy ở origin riêng, không đọc được
      token đăng nhập (localStorage) của app cùng domain.
  """
  use FoodStreetWeb, :controller

  alias FoodStreet.SharedPages
  alias FoodStreetWeb.{ShareAuth, ShareListing}

  @sandbox "sandbox allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox " <>
             "allow-modals allow-downloads"

  # Đọc lúc compile (Dockerfile COPY priv trước khi compile) -> không đọc đĩa mỗi request.
  @inject_path Path.expand("../../../priv/share/inject.js", __DIR__)
  @external_resource @inject_path
  @inject_js File.read!(@inject_path)

  @state_salt "share state"
  @state_max_age 7 * 24 * 60 * 60

  def state_salt, do: @state_salt
  def state_max_age, do: @state_max_age

  def show(conn, %{"path" => segments}) do
    case ShareAuth.verify(conn) do
      {:ok, user} -> serve(conn, segments, user)
      :error -> redirect_to_login(conn)
    end
  end

  defp redirect_to_login(conn) do
    next =
      conn.request_path <> if(conn.query_string == "", do: "", else: "?" <> conn.query_string)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> redirect(to: "/login?" <> URI.encode_query(%{"next" => next}))
  end

  defp serve(conn, segments, user) do
    with {:ok, %{rel: rel, abs: abs}} <- SharedPages.resolve(segments) do
      case File.stat(abs) do
        {:ok, %File.Stat{type: :directory}} -> serve_dir(conn, rel, abs, user)
        {:ok, %File.Stat{type: :regular}} -> serve_file(conn, rel, abs, user)
        # Folder gốc chưa có (chưa ai upload) -> danh sách rỗng.
        _ when rel == "" -> serve_dir(conn, rel, abs, user)
        _ -> not_found(conn)
      end
    else
      _ -> not_found(conn)
    end
  end

  # URL thư mục luôn có "/" cuối để link tương đối trong index.html đúng chỗ.
  defp serve_dir(conn, rel, abs, user) do
    index = Path.join(abs, "index.html")

    cond do
      not String.ends_with?(conn.request_path, "/") ->
        redirect(conn, to: conn.request_path <> "/")

      File.regular?(index) ->
        serve_file(conn, Path.join([rel, "index.html"]) |> String.trim_leading("/"), index, user)

      true ->
        {:ok, listing} = SharedPages.list(rel)

        conn
        |> secure_headers("; default-src 'none'; style-src 'unsafe-inline'")
        |> put_resp_content_type("text/html")
        |> send_resp(200, ShareListing.render(listing))
    end
  end

  defp serve_file(conn, rel, abs, user) do
    if String.downcase(Path.extname(abs)) in SharedPages.allowed_exts() do
      html = File.read!(abs) |> inject(rel, user)

      conn
      |> secure_headers()
      |> put_resp_content_type("text/html")
      |> send_resp(200, html)
    else
      # File khác (ảnh, css, js… rsync kèm trang) -> trả nguyên.
      conn
      |> secure_headers()
      |> put_resp_content_type(MIME.from_path(abs), nil)
      |> send_file(200, abs)
    end
  end

  defp not_found(conn) do
    conn
    |> secure_headers()
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Không tìm thấy trang.")
  end

  defp secure_headers(conn, extra_csp \\ "") do
    conn
    |> put_resp_header("content-security-policy", @sandbox <> extra_csp)
    |> put_resp_header("x-content-type-options", "nosniff")
    # Luôn hỏi lại server: thấy ngay bản mới / dữ liệu người khác vừa nhập, đăng xuất thì
    # không xem lại được từ cache. private: cấm proxy cache.
    |> put_resp_header("cache-control", "private, no-cache")
  end

  # Chèn ngay sau <head> để storage giả có trước mọi script của trang.
  defp inject(html, rel, user) do
    config = %{
      token:
        Phoenix.Token.sign(FoodStreetWeb.Endpoint, @state_salt, %{"p" => rel, "u" => user.id}),
      saveUrl: "/api/share_state",
      state: SharedPages.get_state(rel)
    }

    snippet =
      "<script>window.__FS_SHARE__=" <>
        Jason.encode!(config, escape: :html_safe) <>
        ";</script><script>" <> @inject_js <> "</script>"

    insert_after(html, [~r/<head\b[^>]*>/i, ~r/<html\b[^>]*>/i, ~r/<!doctype[^>]*>/i], snippet)
  end

  defp insert_after(html, [re | rest], snippet) do
    case Regex.run(re, html, return: :index) do
      [{pos, len}] ->
        {before, after_} = split_bytes(html, pos + len)
        before <> snippet <> after_

      nil ->
        insert_after(html, rest, snippet)
    end
  end

  defp insert_after(html, [], snippet), do: snippet <> html

  defp split_bytes(bin, at),
    do: {binary_part(bin, 0, at), binary_part(bin, at, byte_size(bin) - at)}
end
