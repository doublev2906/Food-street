// Chèn vào đầu mọi trang HTML chia sẻ (/share) bởi FoodStreetWeb.ShareController.
// Trang chạy trong CSP sandbox (origin riêng) nên không có localStorage/cookie thật.
// Script này:
//   1. Tự lưu giá trị người xem nhập (input, select, textarea, checkbox, radio,
//      contenteditable) lên server — dùng chung cho mọi người — và khôi phục khi mở lại.
//   2. Giả lập localStorage (lưu lên server, dùng chung) + sessionStorage (trong bộ nhớ)
//      để trang tự lưu bằng localStorage vẫn chạy được.
// Cấu hình server nhúng sẵn: window.__FS_SHARE__ = { token, saveUrl, state }.
(function () {
  "use strict";
  var cfg = window.__FS_SHARE__ || {};
  var state = cfg.state || {};
  var pending = {};
  var timer = null;
  var retryTimer = null;
  var restoring = false;
  var badge = null;

  // ---------------------------------------------------------------- lưu server
  function queue(key, value) {
    pending[key] = value;
    if (value === null) delete state[key];
    else state[key] = value;
    clearTimeout(timer);
    setStatus("saving");
    timer = setTimeout(flush, 600);
  }

  function flush(keepalive) {
    var patch = pending;
    pending = {};
    if (!Object.keys(patch).length) return;
    fetch(cfg.saveUrl, {
      method: "POST",
      // text/plain -> "simple request", không cần preflight CORS từ origin sandbox.
      body: JSON.stringify({ token: cfg.token, patch: patch }),
      keepalive: !!keepalive,
    })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        setStatus(Object.keys(pending).length ? "saving" : "saved");
      })
      .catch(function () {
        // Trả lại hàng đợi (giá trị mới hơn nếu có thì giữ), thử lại sau 5s.
        for (var k in patch) if (!(k in pending)) pending[k] = patch[k];
        setStatus("error");
        clearTimeout(retryTimer);
        retryTimer = setTimeout(flush, 5000);
      });
  }

  window.addEventListener("pagehide", function () {
    clearTimeout(timer);
    flush(true);
  });

  // ---------------------------------------------------------------- badge trạng thái
  var LABELS = {
    saving: ["#b45309", "● Đang lưu…"],
    saved: ["#15803d", "✓ Đã lưu"],
    error: ["#b91c1c", "⚠ Chưa lưu được, đang thử lại…"],
  };
  var hideTimer = null;

  function setStatus(kind) {
    if (!document.body) return;
    if (!badge) {
      badge = document.createElement("div");
      badge.setAttribute("data-fs-share", "");
      badge.style.cssText =
        "position:fixed;right:12px;bottom:12px;z-index:2147483647;padding:4px 10px;" +
        "border-radius:999px;font:12px/1.4 system-ui,sans-serif;color:#fff;" +
        "pointer-events:none;transition:opacity .3s;opacity:0";
      document.body.appendChild(badge);
    }
    badge.style.background = LABELS[kind][0];
    badge.textContent = LABELS[kind][1];
    badge.style.opacity = "0.9";
    clearTimeout(hideTimer);
    if (kind === "saved")
      hideTimer = setTimeout(function () {
        badge.style.opacity = "0";
      }, 1500);
  }

  // ---------------------------------------------------------------- storage giả
  function makeStorage(prefix, persist) {
    var data = {};
    if (persist)
      for (var k in state)
        if (k.indexOf(prefix) === 0) data[k.slice(prefix.length)] = String(state[k]);
    var has = function (k) {
      return Object.prototype.hasOwnProperty.call(data, k);
    };
    var api = {
      getItem: function (k) {
        k = String(k);
        return has(k) ? data[k] : null;
      },
      setItem: function (k, v) {
        k = String(k);
        v = String(v);
        if (data[k] === v) return;
        data[k] = v;
        if (persist) queue(prefix + k, v);
      },
      removeItem: function (k) {
        k = String(k);
        if (!has(k)) return;
        delete data[k];
        if (persist) queue(prefix + k, null);
      },
      clear: function () {
        Object.keys(data).forEach(function (k) {
          api.removeItem(k);
        });
      },
      key: function (i) {
        var keys = Object.keys(data);
        return i >= 0 && i < keys.length ? keys[i] : null;
      },
    };
    // configurable: Proxy.ownKeys bắt buộc liệt kê mọi key non-configurable của target.
    Object.defineProperty(api, "length", {
      configurable: true,
      get: function () {
        return Object.keys(data).length;
      },
    });
    // Hỗ trợ cả kiểu localStorage.foo = "x" / Object.keys(localStorage).
    return new Proxy(api, {
      get: function (t, p) {
        if (p in t) return t[p];
        return typeof p === "string" && has(p) ? data[p] : undefined;
      },
      set: function (t, p, v) {
        t.setItem(p, v);
        return true;
      },
      deleteProperty: function (t, p) {
        t.removeItem(p);
        return true;
      },
      has: function (t, p) {
        return p in t || has(p);
      },
      ownKeys: function () {
        return Object.keys(data);
      },
      getOwnPropertyDescriptor: function (_t, p) {
        if (!has(p)) return undefined;
        return { value: data[p], enumerable: true, configurable: true, writable: true };
      },
    });
  }

  function storageBlocked() {
    try {
      return !window.localStorage;
    } catch (e) {
      return true;
    }
  }

  function install(target, name, desc) {
    try {
      Object.defineProperty(target, name, Object.assign({ configurable: true }, desc));
    } catch (e) {
      /* trình duyệt không cho ghi đè: bỏ qua */
    }
  }

  if (storageBlocked()) {
    var ls = makeStorage("ls:", true);
    var ss = makeStorage("ss:", false);
    install(window, "localStorage", { get: function () { return ls; } });
    install(window, "sessionStorage", { get: function () { return ss; } });
    var jar = "";
    install(document, "cookie", {
      get: function () { return jar; },
      set: function (v) { jar = String(v).split(";")[0]; },
    });
  }

  // ---------------------------------------------------------------- ô nhập liệu
  var SKIP = { password: 1, file: 1, hidden: 1, submit: 1, button: 1, reset: 1, image: 1 };

  function editableHost(el) {
    var host = el && el.closest && el.closest("[contenteditable]");
    return host && host.isContentEditable ? host : null;
  }

  function isField(el) {
    if (!el || !el.tagName) return false;
    var tag = el.tagName;
    if (tag === "SELECT" || tag === "TEXTAREA") return true;
    if (tag === "INPUT") return !SKIP[(el.type || "text").toLowerCase()];
    return false;
  }

  function domPath(el) {
    var parts = [];
    while (el && el.nodeType === 1 && el !== document.documentElement) {
      if (el.id) {
        parts.unshift("#" + el.id);
        break;
      }
      var i = 1;
      for (var s = el.previousElementSibling; s; s = s.previousElementSibling)
        if (s.tagName === el.tagName) i++;
      parts.unshift(el.tagName.toLowerCase() + ":" + i);
      el = el.parentElement;
    }
    return parts.join(">");
  }

  // Khoá định danh ô: id > name (+value cho checkbox, +thứ tự nếu trùng name) > vị trí DOM.
  function keyOf(el) {
    if (!isField(el)) return "ce:" + domPath(el);
    var type = (el.type || "").toLowerCase();
    if (type === "radio" && el.name) return "r:" + el.name;
    if (el.id) return "f:#" + el.id;
    if (el.name) {
      // Checkbox cùng name phân biệt theo value; còn trùng nữa thì thêm thứ tự.
      var same = Array.prototype.filter.call(document.getElementsByName(el.name), function (o) {
        return type !== "checkbox" || o.value === el.value;
      });
      var base = "f:n:" + el.name + (type === "checkbox" ? "=" + el.value : "");
      return same.length > 1 ? base + ":" + same.indexOf(el) : base;
    }
    return "f:p:" + domPath(el);
  }

  function read(el) {
    if (!isField(el)) return el.innerHTML;
    var type = (el.type || "").toLowerCase();
    if (type === "radio" && el.name) return el.value;
    if (type === "checkbox" || type === "radio") return el.checked;
    if (el.tagName === "SELECT" && el.multiple)
      return Array.prototype.filter
        .call(el.options, function (o) { return o.selected; })
        .map(function (o) { return o.value; });
    return el.value;
  }

  function write(el, v) {
    if (!isField(el)) {
      if (el.innerHTML !== v) el.innerHTML = v;
      return;
    }
    var type = (el.type || "").toLowerCase();
    if (type === "radio" && el.name) el.checked = el.value === v;
    else if (type === "checkbox" || type === "radio") el.checked = !!v;
    else if (el.tagName === "SELECT" && el.multiple)
      Array.prototype.forEach.call(el.options, function (o) {
        o.selected = Array.isArray(v) && v.indexOf(o.value) >= 0;
      });
    else el.value = v;
  }

  // Khôi phục 1 ô (chỉ ô người xem chưa đụng tới) rồi bắn input/change để logic của
  // trang (tính tổng, ẩn/hiện…) chạy lại như khi người dùng tự nhập.
  var touched = new WeakSet();
  function restore(el) {
    if (touched.has(el)) return;
    var k = keyOf(el);
    if (!(k in state)) return;
    var before = read(el);
    write(el, state[k]);
    if (JSON.stringify(before) === JSON.stringify(read(el))) return;
    restoring = true;
    try {
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    } finally {
      restoring = false;
    }
  }

  var SELECTOR = "input,select,textarea,[contenteditable]";
  function restoreIn(root) {
    if (root.nodeType !== 1) return;
    if (root.matches(SELECTOR)) restoreTarget(root);
    root.querySelectorAll(SELECTOR).forEach(restoreTarget);
  }
  function restoreTarget(el) {
    if (isField(el)) restore(el);
    else if (editableHost(el) === el && !editableHost(el.parentElement)) restore(el);
  }

  function onEdit(e) {
    if (restoring) return;
    var el = e.target;
    if (!isField(el)) el = editableHost(el);
    if (!el) return;
    // Contenteditable lồng nhau: lưu theo host ngoài cùng.
    while (!isField(el) && editableHost(el.parentElement)) el = editableHost(el.parentElement);
    touched.add(el);
    queue(keyOf(el), read(el));
  }
  document.addEventListener("input", onEdit, true);
  document.addEventListener("change", onEdit, true);

  function start() {
    restoreIn(document.documentElement);
    // Trang tự sinh ô / thêm option bằng JS sau khi tải: khôi phục khi chúng xuất hiện.
    new MutationObserver(function (list) {
      list.forEach(function (m) {
        m.addedNodes.forEach(function (n) {
          if (n.nodeType !== 1) return;
          if (n.tagName === "OPTION" && n.parentElement) restoreIn(n.parentElement.closest("select") || n);
          else restoreIn(n);
        });
      });
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
