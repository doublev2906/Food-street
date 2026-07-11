import { useSearchParams } from "react-router-dom";

/**
 * Giữ tab đang chọn trong query URL (`?tab=...`) để F5 không reset về tab đầu.
 *
 * - `keys`: danh sách tab hợp lệ; giá trị lạ trong URL sẽ rơi về `fallback`.
 * - `clearOnChange`: các query param cần xoá khi đổi tab (vd deep-link `group`)
 *   để không kẹt state cũ của tab trước.
 *
 * Dùng `replace: true` để chuyển tab không làm phình lịch sử trình duyệt.
 */
export function useTabParam<T extends string>(
  keys: readonly T[],
  fallback: T,
  clearOnChange: string[] = []
): [T, (tab: T) => void] {
  const [params, setParams] = useSearchParams();
  const raw = params.get("tab");
  const tab = (keys as readonly string[]).includes(raw ?? "") ? (raw as T) : fallback;

  const setTab = (next: T) =>
    setParams(
      (prev) => {
        const sp = new URLSearchParams(prev);
        sp.set("tab", next);
        clearOnChange.forEach((k) => sp.delete(k));
        return sp;
      },
      { replace: true }
    );

  return [tab, setTab];
}
