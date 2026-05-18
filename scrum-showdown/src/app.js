// Thin glue: wires the pure core (roster + selection + deck + board) to
// the DOM for the mystery-card mechanic. All product logic lives in
// src/core/*; this file only renders state and translates events.
// Hand-validated, per the design spec.

import { createLocalStorage } from './core/storage.js';
import { createRoster } from './core/roster.js';
import { createSelection } from './core/selection.js';
import { createDeck } from './core/deck.js';
import { buildBoard } from './core/board.js';
import { APP_VERSION } from './version.js';

const $ = (s) => document.querySelector(s);
const todayISO = () => new Date().toISOString().slice(0, 10);

const storage = createLocalStorage(window);
const roster = createRoster(storage);
const selection = createSelection({ roster, storage, now: todayISO });
const deck = createDeck({ storage, roster, now: todayISO });

const els = {
  current: $('#current-name'),
  srStatus: $('#sr-status'),
  controls: $('#speaker-controls'),
  done: $('#done'),
  snooze: $('#snooze'),
  absent: $('#absent'),
  grid: $('#grid'),
  banner: $('#round-banner'),
  laneDone: $('#lane-done'),
  laneSnooze: $('#lane-snooze'),
  laneAbsent: $('#lane-absent'),
  reset: $('#reset'),
  resetDialog: $('#reset-dialog'),
  resetYes: $('#reset-yes'),
  resetNo: $('#reset-no'),
  rosterBtn: $('#roster-btn'),
  rosterDialog: $('#roster-dialog'),
  rosterList: $('#roster-list'),
  rosterName: $('#roster-name'),
  rosterAdd: $('#roster-add'),
  rosterClose: $('#roster-close'),
  version: $('#version'),
};

// ---- card builders ----
function mysteryCard(entry, index) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'card card--mystery';
  btn.setAttribute('aria-label', `Face-down card ${index + 1}`);
  const inner = document.createElement('span');
  inner.className = 'card__inner';
  const back = document.createElement('span');
  back.className = 'card__face card__back';
  back.textContent = entry.glyph;
  const front = document.createElement('span');
  front.className = 'card__face card__front';
  inner.append(back, front);
  btn.append(inner);
  btn.addEventListener('click', () => onPick(entry.id));
  return btn;
}

function laneCard(entry) {
  // Face-up by default; click flips between name and glyph (presentation
  // only — never mutates state). Lane cards only.
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'card is-faceup';
  btn.setAttribute('aria-label', entry.name);
  const inner = document.createElement('span');
  inner.className = 'card__inner';
  const back = document.createElement('span');
  back.className = 'card__face card__back';
  back.textContent = entry.glyph;
  const front = document.createElement('span');
  front.className = 'card__face card__front';
  front.textContent = entry.name;
  inner.append(back, front);
  btn.append(inner);
  btn.addEventListener('click', () => btn.classList.toggle('is-faceup'));
  return btn;
}

function renderLane(container, cards) {
  container.replaceChildren();
  for (const c of cards) container.append(laneCard(c));
}

// Single status-move primitive. Every move resets prior status first so
// e.g. SNOOZE->DONE leaves the member cleanly Done (not also Snoozed).
// 'resume' just clears snooze; the member is already revealed, so the
// board re-derives them as the current speaker.
function moveTo(id, target) {
  const before = buildBoard({ roster, selection, deck });
  const m = before.lanes.snooze.find((x) => x.id === id);
  const name = m ? m.name : '';
  selection.clearStatus(id);
  if (target === 'done') selection.done(id);
  els.srStatus.textContent =
    target === 'done' ? `${name} moved to Done` : `${name} resumed`;
  render();
  if (target === 'done' && selection.isComplete()) poof();
}

// SNOOZE-lane card: the flippable face plus explicit Resume / Done
// actions. Resume is disabled while someone is already up (one at a time).
function snoozeCard(entry, resumeDisabled) {
  const wrap = document.createElement('div');
  wrap.className = 'snooze-card';
  const actions = document.createElement('div');
  actions.className = 'card-actions';
  const resume = document.createElement('button');
  resume.type = 'button';
  resume.className = 'btn btn--ghost btn--mini';
  resume.textContent = 'Resume';
  resume.disabled = resumeDisabled;
  resume.addEventListener('click', () => moveTo(entry.id, 'resume'));
  const done = document.createElement('button');
  done.type = 'button';
  done.className = 'btn btn--primary btn--mini';
  done.textContent = 'Done';
  done.addEventListener('click', () => moveTo(entry.id, 'done'));
  actions.append(resume, done);
  wrap.append(laneCard(entry), actions);
  return wrap;
}

function render() {
  const b = buildBoard({ roster, selection, deck });

  els.grid.replaceChildren();
  b.mysteryGrid.forEach((entry, i) => els.grid.append(mysteryCard(entry, i)));

  renderLane(els.laneDone, b.lanes.done);
  els.laneSnooze.replaceChildren();
  for (const c of b.lanes.snooze) els.laneSnooze.append(snoozeCard(c, !!b.current));
  renderLane(els.laneAbsent, b.lanes.absent);

  els.current.textContent = b.current ? b.current.name : '';
  els.controls.hidden = !b.current;
  els.banner.hidden = !selection.isComplete();
}

// ---- interactions ----
function onPick(id) {
  if (buildBoard({ roster, selection, deck }).current) return; // one at a time
  deck.reveal(id);
  render();
}

function resolveCurrent(kind) {
  const b = buildBoard({ roster, selection, deck });
  if (!b.current) return;
  const id = b.current.id;
  const name = b.current.name;
  if (kind === 'done') selection.done(id);
  else if (kind === 'snooze') selection.snooze(id);
  else if (kind === 'absent') roster.setAbsent(id, true);
  const lane = { done: 'Done', snooze: 'Snooze', absent: 'Absent' }[kind];
  els.srStatus.textContent = `${name} moved to ${lane}`;
  render();
  if (kind === 'done' && selection.isComplete()) poof();
}

function poof() {
  const s = document.createElement('div');
  s.className = 'spark';
  document.body.append(s);
  setTimeout(() => s.remove(), 800);
}

// ---- roster modal ----
function renderRoster() {
  els.rosterList.replaceChildren();
  for (const m of roster.list()) {
    const row = document.createElement('li');
    row.className = 'roster-row';
    const name = document.createElement('input');
    name.className = 'roster-row__name';
    name.value = m.name;
    name.setAttribute('aria-label', `Name for ${m.name}`);
    name.addEventListener('change', () => {
      roster.rename(m.id, name.value.trim() || m.name);
    });
    const pto = document.createElement('button');
    pto.type = 'button';
    pto.className = 'btn btn--toggle';
    pto.setAttribute('aria-pressed', String(m.absent));
    pto.textContent = m.absent ? 'PTO' : 'Here';
    pto.addEventListener('click', () => {
      roster.setAbsent(m.id, !m.absent);
      deck.reconcile();
      renderRoster();
      render();
    });
    const rm = document.createElement('button');
    rm.type = 'button';
    rm.className = 'btn btn--danger';
    rm.textContent = 'Remove';
    rm.setAttribute('aria-label', `Remove ${m.name}`);
    rm.addEventListener('click', () => {
      roster.remove(m.id);
      deck.reconcile();
      renderRoster();
      render();
    });
    row.append(name, pto, rm);
    els.rosterList.append(row);
  }
}

function onAddMember() {
  const n = els.rosterName.value.trim();
  if (!n) return;
  roster.add(n);
  deck.reconcile();
  els.rosterName.value = '';
  els.rosterName.focus();
  renderRoster();
  render();
}

function closeDialog(d) {
  if (d.open) d.close();
}

function wire() {
  els.done.addEventListener('click', () => resolveCurrent('done'));
  els.snooze.addEventListener('click', () => resolveCurrent('snooze'));
  els.absent.addEventListener('click', () => resolveCurrent('absent'));

  els.reset.addEventListener('click', () => {
    if (!els.resetDialog.open) els.resetDialog.showModal();
  });
  els.resetYes.addEventListener('click', () => {
    selection.reset();
    deck.regenerate();
    closeDialog(els.resetDialog);
    render();
  });
  els.resetNo.addEventListener('click', () => closeDialog(els.resetDialog));
  els.resetDialog.addEventListener('click', (e) => {
    if (e.target === els.resetDialog) closeDialog(els.resetDialog);
  });

  els.rosterBtn.addEventListener('click', () => {
    renderRoster();
    if (!els.rosterDialog.open) els.rosterDialog.showModal();
  });
  els.rosterClose.addEventListener('click', () => closeDialog(els.rosterDialog));
  els.rosterDialog.addEventListener('click', (e) => {
    if (e.target === els.rosterDialog) closeDialog(els.rosterDialog);
  });
  els.rosterAdd.addEventListener('click', onAddMember);
  els.rosterName.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') onAddMember();
  });

  els.version.textContent = `v${APP_VERSION}`;
}

wire();
render();

// Service worker: on for the real site (installable offline PWA),
// skipped + torn down on localhost so dev iteration never serves stale
// code. (Same guard as the wheel build.)
if ('serviceWorker' in navigator) {
  const isLocalDev = ['localhost', '127.0.0.1', ''].includes(location.hostname);
  window.addEventListener('load', () => {
    if (isLocalDev) {
      navigator.serviceWorker.getRegistrations()
        .then((rs) => rs.forEach((r) => r.unregister())).catch(() => {});
      if (window.caches) {
        caches.keys().then((ks) => ks.forEach((k) => caches.delete(k))).catch(() => {});
      }
    } else {
      navigator.serviceWorker.register('./sw.js').catch(() => {});
    }
  });
}
