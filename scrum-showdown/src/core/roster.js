// Roster: team-member CRUD with persistence through the Storage port.
// Pure and UI-agnostic — no DOM, no platform coupling.

const STORAGE_KEY = 'scrum-showdown:roster';
const SCHEMA_VERSION = 1;

let idSeq = 0;
function nextId() {
  idSeq += 1;
  return `m${Date.now().toString(36)}-${idSeq}`;
}

// Restore members from storage. Unknown schema versions and corrupt JSON
// are treated as "no data" so a bad payload can never crash startup.
function load(storage) {
  const raw = storage.get(STORAGE_KEY);
  if (raw == null) return [];
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!parsed || parsed.version !== SCHEMA_VERSION || !Array.isArray(parsed.members)) {
    return [];
  }
  return parsed.members.map((m) => ({
    id: m.id,
    name: m.name,
    absent: Boolean(m.absent),
  }));
}

export function createRoster(storage) {
  let members = load(storage);

  function persist() {
    storage.set(STORAGE_KEY, JSON.stringify({ version: SCHEMA_VERSION, members }));
  }

  return {
    list() {
      return members.slice();
    },
    add(name) {
      const member = { id: nextId(), name, absent: false };
      members.push(member);
      persist();
      return member;
    },
    remove(id) {
      members = members.filter((m) => m.id !== id);
      persist();
    },
    rename(id, name) {
      const m = members.find((x) => x.id === id);
      if (m) {
        m.name = name;
        persist();
      }
    },
    setAbsent(id, absent) {
      const m = members.find((x) => x.id === id);
      if (m) {
        m.absent = absent;
        persist();
      }
    },
  };
}
