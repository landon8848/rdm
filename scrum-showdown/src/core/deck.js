// Deck: stable per-session glyph<->member bindings + revealed-set, with
// schema-versioned persistence and the same daily-reset / recovery /
// degrade rules as roster and selection. Pure and UI-agnostic; RNG and
// clock are injected for deterministic tests.

import { GLYPH_POOL } from './glyphs.js';

const DECK_KEY = 'scrum-showdown:deck';
const SCHEMA_VERSION = 1;

function shuffle(arr, random) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    const t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

function load(storage, today) {
  const raw = storage.get(DECK_KEY);
  if (raw == null) return null;
  let p;
  try {
    p = JSON.parse(raw);
  } catch {
    return null;
  }
  if (
    !p ||
    p.version !== SCHEMA_VERSION ||
    p.date !== today ||
    typeof p.bindings !== 'object' ||
    !Array.isArray(p.revealed)
  ) {
    return null;
  }
  return p;
}

export function createDeck({ storage, roster, now, random = Math.random }) {
  let bindings = {}; // memberId -> glyph
  let revealed = new Set();

  function persist() {
    storage.set(
      DECK_KEY,
      JSON.stringify({
        version: SCHEMA_VERSION,
        date: now(),
        bindings,
        revealed: [...revealed],
      }),
    );
  }

  function usedGlyphs() {
    return new Set(Object.values(bindings));
  }

  function freshGlyph(pool) {
    const used = usedGlyphs();
    const unused = pool.filter((x) => !used.has(x));
    if (unused.length > 0) return unused[Math.floor(random() * unused.length)];
    return pool[Object.keys(bindings).length % pool.length];
  }

  function reconcileInto(pool) {
    let changed = false;
    const ids = new Set(roster.list().map((m) => m.id));
    for (const id of Object.keys(bindings)) {
      if (!ids.has(id)) {
        delete bindings[id];
        revealed.delete(id);
        changed = true;
      }
    }
    for (const m of roster.list()) {
      if (bindings[m.id] == null) {
        bindings[m.id] = freshGlyph(pool);
        changed = true;
      }
    }
    return changed;
  }

  function buildFresh() {
    bindings = {};
    revealed = new Set();
    const pool = shuffle(GLYPH_POOL, random);
    roster.list().forEach((m, i) => {
      bindings[m.id] = pool[i % pool.length];
    });
    persist();
  }

  const restored = load(storage, now());
  if (restored) {
    bindings = { ...restored.bindings };
    revealed = new Set(restored.revealed);
    if (reconcileInto(shuffle(GLYPH_POOL, random))) persist();
  } else {
    buildFresh();
  }

  return {
    glyphFor(id) {
      return bindings[id];
    },
    isRevealed(id) {
      return revealed.has(id);
    },
    reveal(id) {
      revealed.add(id);
      persist();
    },
    reconcile() {
      if (reconcileInto(shuffle(GLYPH_POOL, random))) persist();
    },
    regenerate() {
      buildFresh();
    },
  };
}
