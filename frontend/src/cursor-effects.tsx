import { useEffect } from "react";
import { createFluidCursor } from "./fluid-cursor";
import { createDragonCursor } from "./dragon-cursor";

const ANIMATIONS: Record<string, { total: number; ms: number }> = {
  saber: { total: 2, ms: 150 },
  jinwoo: { total: 11, ms: 200 },
};
const frameCache = new Map<string, Promise<HTMLImageElement[]>>();
const INTERACTIVE = 'button, a[href], select, label, [role="button"], .brand, .chip, .food-card, input:is([type="checkbox"], [type="radio"], [type="range"], [type="button"], [type="submit"], [type="reset"], [type="file"], [type="color"])';
const NATIVE = 'textarea, input:not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="file"]):not([type="color"]), [contenteditable]:not([contenteditable="false"]), :disabled, [aria-disabled="true"]';

type CursorEffect = {
  move: (x: number, y: number, interactive: boolean) => void;
  press?: (x: number, y: number) => void;
  pause: () => void;
  dispose: () => void;
};

function createAnimatedCursor(key: string): CursorEffect {
  const root = document.documentElement;
  const animation = ANIMATIONS[key];
  let frame = 1;
  let timer = 0;
  let lastMove = -Infinity;
  let ready = false;
  let active = false;
  let disposed = false;
  const pause = () => {
    window.clearTimeout(timer);
    timer = 0;
    frame = 1;
    active = false;
    delete root.dataset.cursorFrame;
  };
  const tick = () => {
    if (!active || document.hidden || performance.now() - lastMove > 1000) {
      pause();
      return;
    }
    frame = (frame % animation.total) + 1;
    root.dataset.cursorFrame = String(frame);
    timer = window.setTimeout(tick, animation.ms);
  };
  const wake = () => {
    if (ready && active && !timer) timer = window.setTimeout(tick, animation.ms);
  };
  // Decode trước khi đổi frame; dùng lại cache khi đổi trang hoặc chọn lại bộ cũ.
  if (!frameCache.has(key)) {
    const urls = Array.from({ length: animation.total }, (_, i) => `/cursors/${key}-${i + 1}.png`);
    urls.push(`/cursors/${key}-pointer.png`);
    frameCache.set(key, Promise.all(urls.map(async (url) => {
      const image = new Image();
      image.src = url;
      await image.decode();
      return image;
    })));
  }
  frameCache.get(key)!.then(() => {
    if (disposed) return;
    ready = true;
    wake();
  }).catch(() => frameCache.delete(key));

  return {
    move: (_x, _y, interactive) => {
      if (interactive) {
        pause();
        return;
      }
      lastMove = performance.now();
      active = true;
      wake();
    },
    pause,
    dispose: () => {
      disposed = true;
      pause();
    },
  };
}

export function CursorEffects() {
  useEffect(() => {
    const root = document.documentElement;
    const finePointer = window.matchMedia("(any-hover: hover) and (any-pointer: fine)");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let stop = () => {};
    const sync = () => {
      stop();
      stop = () => {};
      if (!finePointer.matches || reducedMotion.matches) return;
      const key = root.dataset.cursor || "cat";
      const effect: CursorEffect | null = ANIMATIONS[key]
        ? createAnimatedCursor(key)
        : key === "fluid" ? createFluidCursor()
          : key === "dragon" ? createDragonCursor() : null;
      if (!effect) return;

      const onPointer = (event: PointerEvent) => {
        const target = event.target instanceof Element ? event.target : null;
        if (event.pointerType !== "mouse" || document.hidden || target?.closest(NATIVE)) {
          effect.pause();
          return;
        }
        effect.move(event.clientX, event.clientY, !!target?.closest(INTERACTIVE));
        if (event.type === "pointerdown") effect.press?.(event.clientX, event.clientY);
      };
      const onOut = (event: PointerEvent) => {
        if (!event.relatedTarget) effect.pause();
      };
      const onVisibility = () => {
        if (document.hidden) effect.pause();
      };
      const onKey = (event: KeyboardEvent) => {
        if (event.key === "Tab" || event.key === "Escape") effect.pause();
      };
      const events = ["pointermove", "pointerover", "pointerdown"] as const;
      for (const name of events) document.addEventListener(name, onPointer, { passive: true });
      document.addEventListener("pointerout", onOut, { passive: true });
      document.addEventListener("visibilitychange", onVisibility);
      document.addEventListener("keydown", onKey);
      window.addEventListener("blur", effect.pause);
      window.addEventListener("scroll", effect.pause, { passive: true, capture: true });
      stop = () => {
        for (const name of events) document.removeEventListener(name, onPointer);
        document.removeEventListener("pointerout", onOut);
        document.removeEventListener("visibilitychange", onVisibility);
        document.removeEventListener("keydown", onKey);
        window.removeEventListener("blur", effect.pause);
        window.removeEventListener("scroll", effect.pause, true);
        effect.dispose();
      };
    };
    const observer = new MutationObserver(sync);
    observer.observe(root, { attributes: true, attributeFilter: ["data-cursor"] });
    finePointer.addEventListener("change", sync);
    reducedMotion.addEventListener("change", sync);
    sync();
    return () => {
      observer.disconnect();
      finePointer.removeEventListener("change", sync);
      reducedMotion.removeEventListener("change", sync);
      stop();
    };
  }, []);
  return null;
}
