// Selection: the round/fairness state machine.
// Pure and UI-agnostic — clock and RNG are injected for deterministic tests.

const ROUND_KEY = 'scrum-showdown:round';
const SCHEMA_VERSION = 1;

// Restore an in-progress round only if it is well-formed, the current
// schema, and stamped with *today's* date. A different date triggers the
// daily reset; corrupt/unknown data degrades to a fresh round.
function loadRound(storage, today) {
  const raw = storage.get(ROUND_KEY);
  if (raw == null) return null;
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (
    !parsed ||
    parsed.version !== SCHEMA_VERSION ||
    parsed.date !== today ||
    !Array.isArray(parsed.done) ||
    !Array.isArray(parsed.snoozed)
  ) {
    return null;
  }
  return parsed;
}

export function createSelection({ roster, storage, now, random = Math.random }) {
  const restored = loadRound(storage, now());
  const doneIds = new Set(restored ? restored.done : []);
  const snoozedIds = new Set(restored ? restored.snoozed : []);

  function persist() {
    storage.set(
      ROUND_KEY,
      JSON.stringify({
        version: SCHEMA_VERSION,
        date: now(),
        done: [...doneIds],
        snoozed: [...snoozedIds],
      }),
    );
  }

  function active() {
    return roster.list().filter((m) => !m.absent);
  }

  return {
    eligible() {
      // Not-done members are the round's remaining pool.
      const remaining = active().filter((m) => !doneIds.has(m.id));
      const awake = remaining.filter((m) => !snoozedIds.has(m.id));
      // All-snoozed fallback: if everyone left is snoozed, return them so
      // standup can still finish.
      return awake.length > 0 ? awake : remaining;
    },
    snooze(id) {
      snoozedIds.add(id);
      persist();
    },
    unsnooze(id) {
      snoozedIds.delete(id);
      persist();
    },
    clearStatus(id) {
      doneIds.delete(id);
      snoozedIds.delete(id);
      persist();
    },
    pick() {
      const pool = this.eligible();
      if (pool.length === 0) return null;
      return pool[Math.floor(random() * pool.length)];
    },
    done(id) {
      doneIds.add(id);
      persist();
    },
    isDone(id) {
      return doneIds.has(id);
    },
    isSnoozed(id) {
      return snoozedIds.has(id);
    },
    isComplete() {
      const members = active();
      return members.length > 0 && members.every((m) => doneIds.has(m.id));
    },
    reset() {
      doneIds.clear();
      snoozedIds.clear();
      persist();
    },
  };
}
