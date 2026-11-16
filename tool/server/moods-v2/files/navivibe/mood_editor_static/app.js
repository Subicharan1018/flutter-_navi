// Song Moods editor (moods-v2). No build step. The page keeps only the sign-in token
// (sessionStorage), never the password.
"use strict";

const MOODS = ["sad", "romantic", "happy", "energetic", "calm", "devotional", "angry", "gym"];
const KEY = "navivibe.moods.session";
const PAGE = 50;
const $ = (id) => document.getElementById(id);
const title = (m) => m.charAt(0).toUpperCase() + m.slice(1);

let session = null;               // {token, username, is_admin}
let query = { q: "", mood: "", filter: "" };
let nextOffset = 0, loading = false, generation = 0, coverBase = "";
const rows = new Map();           // id -> song item as the server last sent it

// ── sign-in ──────────────────────────────────────────────────────────────────
function loadSession() {
  try { session = JSON.parse(sessionStorage.getItem(KEY) || "null"); } catch (_) { session = null; }
}
function saveSession() {
  try { session ? sessionStorage.setItem(KEY, JSON.stringify(session)) : sessionStorage.removeItem(KEY); } catch (_) {}
}
function showSignIn(message) {
  session = null; saveSession();
  $("app").hidden = true; $("signin").hidden = false;
  const err = $("signin-error");
  err.hidden = !message; err.textContent = message || "";
  $("user").focus();
}
async function signIn(ev) {
  ev.preventDefault();
  const btn = $("signin-btn"), err = $("signin-error");
  const username = $("user").value.trim(), password = $("pass").value;
  btn.disabled = true; err.hidden = true;
  try {
    const r = await fetch("/moods/editor/login", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    const body = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(body.error || "Couldn't sign in. Try again.");
    session = { token: body.token, username: body.username, is_admin: !!body.is_admin };
    saveSession();
    $("pass").value = "";
    start();
  } catch (e) {
    err.textContent = e.message || "Couldn't sign in. Try again.";
    err.hidden = false;
  } finally {
    btn.disabled = false;
  }
}

// ── API ──────────────────────────────────────────────────────────────────────
class ApiError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}
async function api(method, path, body) {
  let r;
  try {
    r = await fetch(path, {
      method,
      headers: { Authorization: "Bearer " + session.token, ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (_) {
    throw new ApiError("Can't reach the server. Check your connection.", 0);
  }
  const data = await r.json().catch(() => ({}));
  if (r.status === 401) { showSignIn("Your sign-in expired. Sign in again."); throw new ApiError("Signed out", 401); }
  if (!r.ok) throw new ApiError(data.error || "The server couldn't do that right now.", r.status);
  return data;
}

// ── list ─────────────────────────────────────────────────────────────────────
function filterButtons() {
  const nav = $("filters");
  nav.textContent = "";
  const opts = [["All", "", ""], ["No mood", "none", ""], ["Flagged", "", "flagged"], ["Set by admin", "", "admin"],
                ...MOODS.map((m) => [title(m), m, ""])];
  for (const [label, mood, filter] of opts) {
    const b = document.createElement("button");
    b.className = "filter"; b.textContent = label; b.type = "button";
    b.setAttribute("aria-pressed", String(query.mood === mood && query.filter === filter));
    b.addEventListener("click", () => { query.mood = mood; query.filter = filter; filterButtons(); reload(); });
    nav.appendChild(b);
  }
}
function reload() {
  generation++; nextOffset = 0; rows.clear();
  $("list").textContent = ""; $("count").textContent = "";
  loadMore();
}
async function loadMore() {
  if (!session || loading || nextOffset === null) return;
  loading = true;
  const gen = generation;
  const state = $("list-state");
  state.textContent = "Loading…";
  const p = new URLSearchParams({ offset: nextOffset, limit: PAGE });
  if (query.q) p.set("q", query.q);
  if (query.mood) p.set("mood", query.mood);
  if (query.filter) p.set("filter", query.filter);
  try {
    const data = await api("GET", "/moods/songs?" + p);
    if (gen !== generation) return;
    coverBase = data.cover_base || "";
    if (session.is_admin !== data.is_admin) { session.is_admin = data.is_admin; saveSession(); roleNote(); }
    for (const it of data.items) { rows.set(it.id, it); $("list").appendChild(renderRow(it)); }
    nextOffset = data.next_offset;
    $("count").textContent = `${data.total} ${data.total === 1 ? "song" : "songs"}`;
    state.textContent = data.total === 0 ? "No songs match. Try another search or filter." : "";
  } catch (e) {
    if (gen !== generation || e.status === 401) return;
    state.textContent = "";
    const retry = document.createElement("button");
    retry.className = "link"; retry.textContent = "Couldn't load songs. Try Again";
    retry.addEventListener("click", () => { state.textContent = ""; loadMore(); });
    state.appendChild(retry);
  } finally {
    if (gen === generation) loading = false;
  }
}
function coverUrl(id) {
  if (!coverBase || !session) return "";
  const p = new URLSearchParams({ id, size: "96", u: session.username, jwt: session.token, v: "1.16.1", c: "navivibe-moods" });
  return `${coverBase}/rest/getCoverArt?${p}`;
}
function renderRow(it) {
  const li = document.createElement("li");
  li.className = "row"; li.dataset.id = it.id; li.tabIndex = 0;
  li.setAttribute("role", "button");
  const img = document.createElement("img");
  img.className = "art"; img.alt = ""; img.loading = "lazy"; img.decoding = "async";
  const url = coverUrl(it.id);
  if (url) img.src = url;
  img.addEventListener("error", () => {      // no cover: a plain square, never a broken-image glyph
    const blank = document.createElement("div");
    blank.className = "art";
    img.replaceWith(blank);
  });
  const meta = document.createElement("div");
  meta.className = "meta";
  const t = document.createElement("div"); t.className = "title"; t.textContent = it.title || "Untitled";
  const s = document.createElement("div"); s.className = "sub";
  s.textContent = [it.artist, it.film || it.album].filter(Boolean).join(" · ");
  meta.append(t, s, renderTags(it));
  li.append(img, meta);
  li.addEventListener("click", () => openSheet(it.id));
  li.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openSheet(it.id); } });
  return li;
}
function renderTags(it) {
  const box = document.createElement("div");
  box.className = "tags";
  if (!it.moods.length) {
    const n = document.createElement("span"); n.className = "tag none"; n.textContent = "No mood"; box.appendChild(n);
  }
  it.moods.forEach((m, i) => {
    const tag = document.createElement("span");
    tag.className = "tag" + (i === 0 ? " first" : "");
    tag.textContent = title(m);
    box.appendChild(tag);
  });
  const note = document.createElement("span");
  note.className = "note";
  if (it.source === "admin") note.textContent = `Set by ${it.by || "admin"}${it.at ? " · " + it.at.slice(0, 10) : ""}`;
  else if (it.flags.length) { note.className = "note flag"; note.textContent = it.flags.join("; "); }
  if (it.not && it.not.length) note.textContent += `${note.textContent ? " · " : ""}Not ${it.not.map(title).join(", ")} for you`;
  if (note.textContent) box.appendChild(note);
  return box;
}
function replaceRow(it) {
  rows.set(it.id, it);
  const old = document.querySelector(`.row[data-id="${CSS.escape(it.id)}"]`);
  if (old) old.replaceWith(renderRow(it));
}

// ── the mood selector ────────────────────────────────────────────────────────
let editing = null;     // {id, picked: [..]}
function openSheet(id) {
  const it = rows.get(id);
  if (!it) return;
  editing = { id, picked: [...it.moods] };
  $("sheet-title").textContent = it.title || "Untitled";
  $("sheet-sub").textContent = [it.artist, it.film || it.album].filter(Boolean).join(" · ");
  $("sheet-error").hidden = true;
  $("sheet-llm").textContent = it.source === "admin"
    ? `The labeller said: ${it.llm.length ? it.llm.map(title).join(", ") : "no mood"}.`
    : (it.flags.length ? `Flagged: ${it.flags.join("; ")}` : "");
  $("sheet-save").hidden = !session.is_admin;
  $("sheet-reset").hidden = !session.is_admin || it.source !== "admin";
  $("sheet-hint").textContent = session.is_admin
    ? "Tap up to 2 moods, most fitting first. Saved for everyone; a relabel never changes it."
    : "Tap a mood to mark it Not this mood for you. Only an admin can add moods.";
  renderChips();
  $("sheet").hidden = false;
  $("chips").querySelector("button:not(:disabled)")?.focus();
}
function closeSheet() { $("sheet").hidden = true; editing = null; }
function renderChips() {
  const box = $("chips"), it = rows.get(editing.id);
  box.textContent = "";
  for (const m of MOODS) {
    const b = document.createElement("button");
    b.type = "button"; b.className = "chip"; b.textContent = title(m);
    if (session.is_admin) {
      const i = editing.picked.indexOf(m);
      b.setAttribute("aria-pressed", String(i >= 0));
      if (i >= 0) {
        const o = document.createElement("span"); o.className = "order"; o.textContent = String(i + 1);
        o.setAttribute("aria-label", i === 0 ? "first" : "second"); b.appendChild(o);
      }
      b.addEventListener("click", () => toggleAdmin(m));
    } else {
      const has = it.moods.includes(m), marked = (it.not || []).includes(m);
      b.setAttribute("aria-pressed", String(has));
      if (marked) { b.classList.add("struck"); b.setAttribute("aria-label", `${title(m)}, marked not this mood`); }
      b.disabled = !has && !marked;
      b.addEventListener("click", () => toggleNot(m, marked));
    }
    box.appendChild(b);
  }
  $("sheet-save").disabled = sameList(editing.picked, it.moods) && it.source === "admin";
}
function sameList(a, b) { return a.length === b.length && a.every((x, i) => x === b[i]); }
function sheetError(msg) { const e = $("sheet-error"); e.textContent = msg; e.hidden = !msg; }
function toggleAdmin(m) {
  const i = editing.picked.indexOf(m);
  if (i >= 0) editing.picked.splice(i, 1);
  else if (editing.picked.length >= 2) { sheetError("Pick at most 2 moods. Tap one to remove it first."); return; }
  else editing.picked.push(m);
  sheetError("");
  renderChips();
}

// Admin: save for everyone, optimistic, with Undo.
async function saveAdmin(id, moods, { undoable = true } = {}) {
  const before = rows.get(id);
  const optimistic = { ...before, moods: [...moods], source: "admin", by: session.username, flags: [] };
  replaceRow(optimistic);
  markPending(id, true);
  try {
    const res = await api("PUT", `/moods/songs/${encodeURIComponent(id)}`, { moods });
    replaceRow(res.song);
    if (undoable) toast(`Saved: ${moods.length ? moods.map(title).join(", ") : "no mood"}`, () => restore(id, before));
    return true;
  } catch (e) {
    replaceRow(before);
    if (e.status !== 401) toast(e.message, null, true);
    return false;
  }
}
async function resetAdmin(id, { undoable = true } = {}) {
  const before = rows.get(id);
  markPending(id, true);
  try {
    const res = await api("DELETE", `/moods/songs/${encodeURIComponent(id)}`);
    replaceRow(res.song);
    if (undoable) toast("Back to the labeller's moods", () => restore(id, before));
    return true;
  } catch (e) {
    replaceRow(before);
    if (e.status !== 401) toast(e.message, null, true);
    return false;
  }
}
function restore(id, before) {
  return before.source === "admin" ? saveAdmin(id, before.moods, { undoable: false }) : resetAdmin(id, { undoable: false });
}
function markPending(id, on) {
  document.querySelector(`.row[data-id="${CSS.escape(id)}"]`)?.classList.toggle("pending", on);
}

// Everyone: "Not this mood" for yourself, optimistic, with Undo.
async function toggleNot(mood, marked, { undoable = true } = {}) {
  const id = editing ? editing.id : null;
  if (!id) return;
  await setNot(id, mood, !marked, undoable);
  if (editing && editing.id === id) renderChips();
}
async function setNot(id, mood, on, undoable) {
  const before = rows.get(id);
  const not = new Set(before.not || []);
  on ? not.add(mood) : not.delete(mood);
  const moods = on ? before.moods.filter((m) => m !== mood) : before.moods;
  replaceRow({ ...before, not: [...not], moods });
  try {
    const res = await api(on ? "POST" : "DELETE", "/moods/not-this", { song_id: id, mood });
    const it = rows.get(id);
    replaceRow({ ...it, not: res.not || [...not], moods: res.moods || it.moods });
    if (undoable) toast(on ? `Not ${title(mood)} for you` : `${title(mood)} again for you`, () => setNot(id, mood, !on, false));
  } catch (e) {
    replaceRow(before);
    if (e.status !== 401) toast(e.message, null, true);
  }
}

// ── toast ────────────────────────────────────────────────────────────────────
let toastTimer = 0;
function toast(text, undo, bad = false) {
  const el = $("toast"), btn = $("toast-undo");
  $("toast-text").textContent = text;
  el.classList.toggle("bad", bad);
  btn.hidden = !undo;
  btn.onclick = undo ? () => { el.hidden = true; undo(); } : null;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, undo ? 6000 : 4000);
}

// ── start ────────────────────────────────────────────────────────────────────
function roleNote() {
  $("who").textContent = session.username;
  $("role-note").textContent = session.is_admin
    ? "You're an admin: your changes become every listener's moods."
    : "Your changes only affect you: tap a mood to mark it Not this mood.";
}
function start() {
  $("signin").hidden = true; $("app").hidden = false;
  roleNote(); filterButtons(); reload();
}
function init() {
  $("signin-form").addEventListener("submit", signIn);
  $("signout").addEventListener("click", () => showSignIn(""));
  let t = 0;
  $("search").addEventListener("input", (e) => {
    clearTimeout(t);
    t = setTimeout(() => { query.q = e.target.value.trim(); reload(); }, 250);
  });
  $("sheet-close").addEventListener("click", closeSheet);
  $("sheet").addEventListener("click", (e) => { if (e.target === $("sheet")) closeSheet(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("sheet").hidden) closeSheet(); });
  $("sheet-save").addEventListener("click", () => { const { id, picked } = editing; closeSheet(); saveAdmin(id, picked); });
  $("sheet-reset").addEventListener("click", () => { const { id } = editing; closeSheet(); resetAdmin(id); });
  new IntersectionObserver((entries) => { if (entries.some((x) => x.isIntersecting)) loadMore(); },
                           { rootMargin: "600px" }).observe($("sentinel"));
  loadSession();
  session && session.token ? start() : showSignIn("");
}
document.addEventListener("DOMContentLoaded", init);
