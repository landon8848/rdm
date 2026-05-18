// Storage port: a tiny string key/value interface { get, set, clear }.
// Adapters keep the pure core free of any platform/DOM coupling.

/** In-memory adapter — used by tests and as a safe fallback. */
export function createMemoryStorage() {
  const map = new Map();
  return {
    get(key) {
      return map.has(key) ? map.get(key) : null;
    },
    set(key, value) {
      map.set(key, String(value));
    },
    clear() {
      map.clear();
    },
  };
}

/**
 * window.localStorage adapter. Mirrors writes into an in-memory map and
 * serves reads/writes from it whenever the real store is unavailable or
 * throws (Safari private mode, quota, disabled storage) — so a flaky
 * conference-room browser never white-screens the app.
 */
export function createLocalStorage(win) {
  const ls = win && win.localStorage;
  const fallback = createMemoryStorage();
  return {
    get(key) {
      try {
        const v = ls.getItem(key);
        if (v !== null) return v;
      } catch {
        /* fall through to in-memory */
      }
      return fallback.get(key);
    },
    set(key, value) {
      const str = String(value);
      fallback.set(key, str);
      try {
        ls.setItem(key, str);
      } catch {
        /* in-memory copy already holds it */
      }
    },
    clear() {
      fallback.clear();
      try {
        ls.clear();
      } catch {
        /* nothing else to do */
      }
    },
  };
}
