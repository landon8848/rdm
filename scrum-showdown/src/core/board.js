// Board: pure view-model selector. Partitions the roster into the
// face-down mystery grid, the single current speaker, and the three
// swimlanes, from roster + selection + deck. No DOM.
//
// Classification priority per member:
//   absent            -> lanes.absent   (incl. absent-before-reveal)
//   done              -> lanes.done
//   snoozed           -> lanes.snooze
//   revealed (else)   -> current         (at most one by flow)
//   otherwise         -> mysteryGrid     (face-down: glyph only, NO name)

export function buildBoard({ roster, selection, deck }) {
  const mysteryGrid = [];
  const lanes = { done: [], snooze: [], absent: [] };
  let current = null;

  for (const m of roster.list()) {
    const card = { id: m.id, name: m.name, glyph: deck.glyphFor(m.id) };
    if (m.absent) {
      lanes.absent.push(card);
    } else if (selection.isDone(m.id)) {
      lanes.done.push(card);
    } else if (selection.isSnoozed(m.id)) {
      lanes.snooze.push(card);
    } else if (deck.isRevealed(m.id)) {
      if (!current) current = card;
    } else {
      mysteryGrid.push({ id: m.id, glyph: deck.glyphFor(m.id) });
    }
  }

  return { mysteryGrid, current, lanes };
}
