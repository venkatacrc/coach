'use strict';

const $ = (sel) => document.querySelector(sel);

function h(tag, attrs = {}, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
        if (v == null || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'style' && typeof v === 'object') {
            for (const [p, val] of Object.entries(v)) p.startsWith('--') ? el.style.setProperty(p, val) : (el.style[p] = val);
        }
        else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
        else if (typeof v === 'boolean') el[k] = v;
        else if (k === 'value') el.value = v;
        else el.setAttribute(k, v);
    }
    for (const c of children.flat(Infinity)) {
        if (c == null || c === false) continue;
        el.append(c instanceof Node ? c : String(c));
    }
    return el;
}

// ---- Dates ----

const pad = (n) => String(n).padStart(2, '0');
const keyOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const WD = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
const wdOf = (d) => WD[d.getDay()];
const mondayOf = (d) => addDays(d, -((d.getDay() + 6) % 7));
const quarterOf = (d) => `${d.getFullYear()}-Q${Math.floor(d.getMonth() / 3) + 1}`;
const toMin = (s) => { const [hh, mm] = s.split(':').map(Number); return hh * 60 + mm; };
const nowMin = () => { const n = new Date(); return n.getHours() * 60 + n.getMinutes(); };
const todayKey = () => keyOf(new Date());

function isoWeek(d) {
    const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
    t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
    const year = t.getUTCFullYear();
    const week = Math.ceil(((t - Date.UTC(year, 0, 1)) / 86400000 + 1) / 7);
    return `${year}-W${pad(week)}`;
}

function clock(min) {
    const hh = Math.floor(min / 60), mm = min % 60;
    return `${((hh + 11) % 12) + 1}:${pad(mm)}${hh < 12 ? 'am' : 'pm'}`;
}

function duration(min) {
    if (min < 60) return `${min} min`;
    const hh = Math.floor(min / 60), mm = min % 60;
    return mm ? `${hh} h ${mm} min` : `${hh} h`;
}

const longDate = (d) => d.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
const shortDate = (d) => d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });

// ---- Saved state ----
// The same shape as the Mac app's state.json, so backups move between devices.

const STATE_KEY = 'coach.state';
const UI_KEY = 'coach.ui';

function emptyCustom() {
    return { blocks: {}, steps: {}, addedBlocks: {}, addedSteps: {}, habits: {}, updated: 0 };
}

function emptyState() {
    return { version: 1, days: {}, lessons: {}, weeks: {}, goals: {}, settings: { family: {}, updated: 0 }, custom: emptyCustom() };
}

function loadState() {
    try {
        const s = JSON.parse(localStorage.getItem(STATE_KEY));
        return s ? Object.assign(emptyState(), s) : emptyState();
    } catch {
        return emptyState();
    }
}

let state = loadState();
const saveState = () => localStorage.setItem(STATE_KEY, JSON.stringify(state));

const ui = Object.assign({ tab: 'today', review: 'day', planDay: null, openTracks: [] },
    (() => { try { return JSON.parse(localStorage.getItem(UI_KEY)) ?? {}; } catch { return {}; } })());
const saveUi = () => localStorage.setItem(UI_KEY, JSON.stringify(ui));

function dayLog(k) {
    const d = state.days[k] ?? {};
    return {
        done: d.done ?? [],
        mood: d.mood ?? null,
        energy: d.energy ?? null,
        wins: d.wins ?? ['', '', ''],
        gratitude: d.gratitude ?? '',
        note: d.note ?? '',
        focus: d.focus ?? ['', '', ''],
        focusDone: d.focusDone ?? [false, false, false],
    };
}

function editDay(k, fn) {
    const d = Object.assign(dayLog(k), state.days[k]);
    fn(d);
    d.updated = Date.now();
    state.days[k] = d;
    saveState();
}

function editWeek(k, fn) {
    const w = state.weeks[k] ?? {};
    fn(w);
    w.updated = Date.now();
    state.weeks[k] = w;
    saveState();
}

function setLesson(id, patch) {
    const l = Object.assign({}, state.lessons[id], patch, { updated: Date.now() });
    state.lessons[id] = l;
    saveState();
}

function saveGoal(goal) {
    state.goals[goal.id] = Object.assign({}, goal, { updated: Date.now() });
    saveState();
}

/** Newer record wins, per day, lesson, week and goal. */
function mergeState(incoming) {
    let changed = 0;
    for (const coll of ['days', 'lessons', 'weeks', 'goals']) {
        for (const [k, v] of Object.entries(incoming[coll] ?? {})) {
            const mine = state[coll][k];
            if (!mine || (v.updated ?? 0) > (mine.updated ?? 0)) {
                state[coll][k] = v;
                changed++;
            }
        }
    }
    for (const one of ['settings', 'custom']) {
        if ((incoming[one]?.updated ?? 0) > (state[one]?.updated ?? 0)) {
            state[one] = incoming[one];
            changed++;
        }
    }
    saveState();
    return changed;
}

/** Your changes to the plan: block and step overrides (by-weekday maps), added blocks and steps, habit settings. */
const custom = () => Object.assign(emptyCustom(), state.custom);

function editCustom(fn) {
    const c = structuredClone(custom());
    fn(c);
    c.updated = Date.now();
    state.custom = c;
    saveState();
}

const habitOn = (id) => !custom().habits[id]?.off;
const habitTarget = (id) => custom().habits[id]?.target ?? null;

/** Days you're expected to do a habit: every planned day, or its weekly target scaled to the window. */
function expected(habit, s, days) {
    const t = habitTarget(habit);
    return t ? Math.min(s.planned, Math.ceil((t * days) / 7)) : s.planned;
}

// ---- Content ----

let content = null;
let trackById = {}, lessonById = {}, appById = {}, areaById = {}, habitById = {};

function indexContent() {
    trackById = Object.fromEntries(content.tracks.map((t) => [t.id, t]));
    lessonById = {};
    for (const t of content.tracks) for (const l of t.lessons) lessonById[l.id] = { ...l, track: t.id };
    appById = Object.fromEntries(content.apps.map((a) => [a.id, a]));
    areaById = Object.fromEntries(content.rhythm.areas.map((a) => [a.id, a]));
    habitById = Object.fromEntries(content.rhythm.habits.map((x) => [x.id, x]));
}

const areaColor = (id) => areaById[id]?.color ?? '#868e96';

function familyName(id) {
    const custom = state.settings?.family?.[id]?.trim();
    return custom || content.rhythm.family.find((f) => f.id === id)?.name || null;
}

function fill(text, vars = {}) {
    return text.replace(/\{(\w+)\}/g, (m, id) => (id in vars ? vars[id] : familyName(id) ?? m));
}

function resolve(value, wd) {
    if (value && typeof value === 'object' && !Array.isArray(value)) return value[wd] ?? value.default ?? null;
    return value ?? null;
}

const templateIdFor = (d) => content.rhythm.days[wdOf(d)];
const templateFor = (d) => content.rhythm.templates[templateIdFor(d)];
const templateDays = (tid) => Object.keys(content.rhythm.days).filter((wd) => content.rhythm.days[wd] === tid);

/** An override value of "" means "none" (no app, no habit); null means "not overridden". */
const pick = (override, fallback) => (override != null ? override || null : fallback ?? null);

/** The day's plan: the template plus your changes. `all` keeps skipped blocks and steps (for the editor). */
function blocksFor(d, { all = false } = {}) {
    const wd = wdOf(d), tid = templateIdFor(d), c = custom();
    const specs = [
        ...templateFor(d).blocks.map((b) => ({ ...b, custom: false })),
        ...(c.addedBlocks[tid] ?? []).filter((b) => !b.days?.length || b.days.includes(wd)).map((b) => ({ ...b, steps: [], custom: true })),
    ];
    const out = [];
    for (const b of specs) {
        const o = c.blocks[`${tid}/${b.id}`] ?? {};
        const hidden = !!resolve(o.hidden, wd);
        if (hidden && !all) continue;
        const steps = [];
        for (const s of b.steps) {
            const so = c.steps[`${tid}/${b.id}/${s.id}`] ?? {};
            const sHidden = !!resolve(so.hidden, wd);
            if (sHidden && !all) continue;
            const text = resolve(so.text, wd) || resolve(s.text, wd);
            if (!text) continue;
            steps.push(makeStep(b.id, s.id, {
                text, app: pick(resolve(so.app, wd), resolve(s.app, wd)), habit: pick(resolve(so.habit, wd), s.habit),
                track: resolve(s.track, wd), practice: s.practice, action: s.action, hidden: sHidden, custom: false,
            }));
        }
        for (const s of c.addedSteps[`${tid}/${b.id}`] ?? []) {
            if (s.days?.length && !s.days.includes(wd)) continue;
            steps.push(makeStep(b.id, s.id, { text: s.text, app: s.app || null, habit: s.habit || null, hidden: false, custom: true, days: s.days ?? null }));
        }
        out.push({
            id: b.id,
            title: resolve(o.title, wd) || b.title,
            area: resolve(o.area, wd) || b.area,
            why: b.why ?? null,
            start: toMin(resolve(o.start, wd) || b.start),
            end: toMin(resolve(o.end, wd) || b.end),
            hidden,
            custom: b.custom,
            days: b.days ?? null,
            steps,
        });
    }
    return out.sort((a, b) => a.start - b.start);
}

function makeStep(blockId, sid, s) {
    return {
        key: `${blockId}.${sid}`,
        sid,
        text: fill(s.text),
        habit: s.habit && habitById[s.habit] && habitOn(s.habit) ? s.habit : null,
        app: s.app && appById[s.app] ? s.app : null,
        track: s.track ?? null,
        practice: s.practice ?? null,
        action: s.action ?? null,
        hidden: s.hidden,
        custom: s.custom,
        days: s.days ?? null,
    };
}

function plannedHabits(d) {
    const set = new Set();
    for (const b of blocksFor(d)) for (const s of b.steps) if (s.habit) set.add(s.habit);
    return set;
}

function doneHabits(d) {
    const done = new Set(state.days[keyOf(d)]?.done ?? []);
    const set = new Set();
    for (const b of blocksFor(d)) for (const s of b.steps) if (s.habit && done.has(s.key)) set.add(s.habit);
    return set;
}

/** Days before the first one you touched don't count against you. */
function firstDayKey() {
    const keys = Object.keys(state.days).sort();
    return keys[0] ?? null;
}

/** Habit counts over the n days before `end` (end itself not included). */
function habitStats(end, n) {
    const first = firstDayKey();
    const stats = {};
    const moods = [], energies = [];
    let days = 0;
    for (let i = n; i >= 1; i--) {
        const d = addDays(end, -i);
        const k = keyOf(d);
        if (!first || k < first) continue;
        days++;
        const planned = plannedHabits(d), done = doneHabits(d);
        for (const x of planned) {
            const s = (stats[x] ??= { planned: 0, done: 0 });
            s.planned++;
            if (done.has(x)) s.done++;
        }
        const log = state.days[k];
        if (log?.mood) moods.push(log.mood);
        if (log?.energy) energies.push(log.energy);
    }
    return { stats, days, moods, energies };
}

/** Consecutive planned days done, counting back from today (today only counts once it's done). */
function streak(habit, today) {
    const first = firstDayKey();
    if (!first) return 0;
    let count = 0;
    for (let i = 0; i < 400; i++) {
        const d = addDays(today, -i);
        if (keyOf(d) < first) break;
        if (!plannedHabits(d).has(habit)) continue;
        if (doneHabits(d).has(habit)) count++;
        else if (i > 0) break;
    }
    return count;
}

const avg = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
const weekHasReview = (d) => Object.keys(state.weeks[isoWeek(d)] ?? {}).some((k) => k !== 'updated');

function coachMessages(today) {
    const byRule = Object.fromEntries(content.coach.messages.map((m) => [m.rule, m]));
    const msg = (rule, vars) => {
        const m = byRule[rule];
        return { icon: m.icon, title: fill(m.title, vars), text: fill(m.text, vars) };
    };
    const out = [];
    if (wdOf(today) === 'sun' && !weekHasReview(today)) out.push(msg('weekly'));

    const { stats, days, moods, energies } = habitStats(today, 7);
    if (days < 3) {
        out.push(msg('welcome'));
        return out;
    }
    const rate = (...ids) => {
        let e = 0, d = 0;
        for (const x of ids) {
            if (!stats[x]) continue;
            const ex = expected(x, stats[x], days);
            e += ex;
            d += Math.min(stats[x].done, ex);
        }
        return e ? d / e : 1;
    };
    const problems = [];
    if (rate('sleep') < 0.6) problems.push('sleep');
    if (moods.length >= 3 && avg(moods) < 3) problems.push('mood');
    if (energies.length >= 3 && avg(energies) < 3) problems.push('energy');
    if (rate('build') < 0.5) problems.push('build');
    if (rate('family', 'oneone') < 0.6) problems.push('family');
    if (stats.gig?.planned && !stats.gig.done) problems.push('gig');
    if (rate('lead') < 0.4) problems.push('lead');
    if (rate('reflect') < 0.5) problems.push('reflect');
    if (rate('sadhana') < 0.5) problems.push('sadhana');
    out.push(...problems.slice(0, 2).map((r) => msg(r)));

    const skipped = skippedSteps(today)[0];
    if (skipped) {
        out.push({
            ...msg('adjust', { step: skipped.text.length > 60 ? skipped.text.slice(0, 57) + '…' : skipped.text, missed: skipped.planned - skipped.done, planned: skipped.planned }),
            action: () => openBlockEditor(skipped.day, skipped.block),
        });
    }
    if (!problems.length) {
        const up = levelUps(today)[0];
        if (up) out.push(msg('levelup', { habit: habitById[up.id].title, pct: up.pct }));
    }

    let best = null;
    for (const x of content.rhythm.habits) {
        const n = streak(x.id, today);
        if (n >= 5 && (!best || n > best.n)) best = { id: x.id, n };
    }
    if (best) out.push(msg('streak', { days: best.n, habit: habitById[best.id].title }));

    if (!problems.length) {
        const total = Object.values(stats).reduce((a, s) => a + s.planned, 0);
        const done = Object.values(stats).reduce((a, s) => a + s.done, 0);
        out.push(msg('strong', { done, total }));
    }
    return out;
}

/**
 * Habit steps and your own steps you keep skipping on days you otherwise used the plan
 * (3+ ticks), over the last two weeks. Worst first.
 */
function skippedSteps(today, n = 14) {
    const first = firstDayKey();
    const counts = {};
    for (let i = 1; i <= n; i++) {
        const d = addDays(today, -i), k = keyOf(d);
        if (!first || k < first) continue;
        const done = new Set(state.days[k]?.done ?? []);
        if (done.size < 3) continue;
        for (const b of blocksFor(d)) {
            for (const s of b.steps) {
                if (!s.habit && !s.custom) continue;
                const c = (counts[s.key] ??= { key: s.key, text: s.text, block: b.id, day: d, planned: 0, done: 0 });
                c.planned++;
                if (done.has(s.key)) c.done++;
            }
        }
    }
    return Object.values(counts)
        .filter((c) => c.planned >= 5 && c.done <= c.planned * 0.2)
        .sort((a, b) => (b.planned - b.done) - (a.planned - a.done));
}

/** Habits done on 90%+ of their expected days for three weeks. */
function levelUps(today) {
    const { stats, days } = habitStats(today, 21);
    return Object.entries(stats).map(([id, s]) => {
        const e = expected(id, s, days);
        return { id, e, pct: e ? Math.round((Math.min(s.done, e) / e) * 100) : 0 };
    }).filter((x) => x.e >= 10 && x.pct >= 90).sort((a, b) => b.pct - a.pct);
}

function wisdomFor(d) {
    const start = new Date(d.getFullYear(), 0, 0);
    const doy = Math.round((startOfDay(d) - start) / 86400000);
    return content.wisdom[doy % content.wisdom.length];
}

const lessonDone = (id) => !!state.lessons[id]?.done;
const nextLesson = (trackId) => trackById[trackId]?.lessons.find((l) => !lessonDone(l.id)) ?? null;
const appUrl = (a) => a.web ?? `https://github.com/venkatacrc/${a.repo}`;

// ---- View state ----

let viewDate = startOfDay(new Date());
let followToday = true;
const openBlocks = new Set();
let openBlocksFor = null;

function setViewDate(d) {
    viewDate = startOfDay(d);
    followToday = keyOf(viewDate) === todayKey();
    render(false);
}

// ---- Rendering ----

function render(keepScroll = true) {
    const main = $('#view');
    const top = main.scrollTop;
    const views = { today: renderToday, grow: renderGrow, review: renderReview, plan: renderPlan };
    main.replaceChildren(views[ui.tab]());
    main.scrollTop = keepScroll ? top : 0;
    for (const b of document.querySelectorAll('#tabs button')) b.classList.toggle('on', b.dataset.tab === ui.tab);
    const dated = ui.tab === 'today' || (ui.tab === 'review' && ui.review !== 'stats');
    $('#datenav').hidden = !dated;
    if (dated) {
        if (ui.tab === 'review' && ui.review === 'week') {
            const mon = mondayOf(viewDate);
            $('#date-label').textContent = `${shortDate(mon)} – ${shortDate(addDays(mon, 6))}`;
        } else {
            const k = keyOf(viewDate), t = todayKey();
            $('#date-label').textContent = k === t ? 'Today'
                : k === keyOf(addDays(new Date(), -1)) ? 'Yesterday'
                    : k === keyOf(addDays(new Date(), 1)) ? 'Tomorrow'
                        : viewDate.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
        }
    }
}

function section(title, ...children) {
    return h('section', { class: 'section' }, title && h('h4', {}, title), children);
}

function checkbox(checked, onchange, color) {
    return h('input', { type: 'checkbox', class: 'check', checked, onchange, style: color ? { '--c': color } : null });
}

// -- Today --

function renderToday() {
    const k = keyOf(viewDate);
    const isToday = k === todayKey();
    const log = dayLog(k);
    const blocks = blocksFor(viewDate);
    const now = nowMin();
    const current = isToday ? blocks.find((b) => now >= b.start && now < b.end) : null;
    const next = isToday ? blocks.find((b) => b.start > now) : null;

    if (openBlocksFor !== k) {
        openBlocks.clear();
        const first = current?.steps.length ? current
            : isToday ? blocks.find((b) => b.start >= (current?.end ?? now) && b.steps.length) : null;
        if (first) openBlocks.add(first.id);
        openBlocksFor = k;
    }

    const planned = plannedHabits(viewDate), done = doneHabits(viewDate);
    const frag = h('div', { class: 'stack' });

    // Hero
    let nowLine = null;
    if (current) {
        const pct = Math.round(((now - current.start) / (current.end - current.start)) * 100);
        nowLine = h('div', { class: 'now', style: { '--c': areaColor(current.area) } },
            h('div', { class: 'now-row' },
                h('span', { class: 'pill' }, 'Now'),
                h('strong', {}, current.title),
                h('span', { class: 'muted' }, `${duration(current.end - now)} left`)),
            h('div', { class: 'bar' }, h('span', { style: { width: pct + '%' } })),
            next && h('div', { class: 'muted small' }, `Next at ${clock(next.start)}: ${next.title}`));
    } else if (isToday && next) {
        nowLine = h('div', { class: 'now', style: { '--c': areaColor(next.area) } },
            h('div', { class: 'now-row' }, h('span', { class: 'pill' }, 'Next'), h('strong', {}, next.title),
                h('span', { class: 'muted' }, `at ${clock(next.start)}`)));
    } else if (isToday) {
        nowLine = h('div', { class: 'now' }, h('div', { class: 'now-row' }, h('span', { class: 'pill' }, 'Rest'),
            h('strong', {}, 'Day complete. Sleep well.')));
    }
    const pct = planned.size ? Math.round((done.size / planned.size) * 100) : 0;
    frag.append(h('div', { class: 'card hero' },
        h('div', { class: 'hero-top' },
            h('div', {},
                h('div', { class: 'greet' }, isToday ? greeting(now) : templateFor(viewDate).title),
                h('div', { class: 'muted' }, `${longDate(viewDate)} · ${templateFor(viewDate).title} plan`)),
            h('div', { class: 'ring', style: { '--p': pct } }, h('span', {}, `${done.size}/${planned.size}`))),
        nowLine,
        h('div', { class: 'habit-row' }, [...planned].map((x) =>
            h('span', { class: 'habit-dot' + (done.has(x) ? ' on' : ''), title: habitById[x].title, style: { '--c': areaColor(habitById[x].area) } },
                habitById[x].icon)))));

    // Top 3
    frag.append(h('div', { class: 'card' },
        h('h3', {}, 'Top 3 today'),
        [0, 1, 2].map((i) => h('div', { class: 'focus-row' },
            checkbox(log.focusDone[i], (e) => { editDay(k, (d) => { d.focusDone[i] = e.target.checked; }); }),
            h('input', {
                type: 'text', class: 'line', value: log.focus[i], placeholder: ['The one thing that matters most', 'Second', 'Third'][i],
                oninput: (e) => editDay(k, (d) => { d.focus[i] = e.target.value; }),
            })))));

    // Coach
    const w = wisdomFor(viewDate);
    frag.append(h('div', { class: 'card coach' },
        h('h3', {}, 'Coach'),
        coachMessages(viewDate).map((m) => h('div', { class: 'msg' },
            h('span', { class: 'msg-icon' }, m.icon),
            h('div', {}, h('strong', {}, m.title), h('p', {}, m.text),
                m.action && h('button', { class: 'chip', onclick: m.action }, '🔧 Adjust')))),
        h('blockquote', { class: 'wisdom' },
            h('p', { class: w.meaning ? 'verse' : '' }, w.text),
            w.meaning && h('p', {}, w.meaning),
            h('cite', {}, w.source))));

    // Timeline
    const doneSet = new Set(log.done);
    frag.append(h('h4', { class: 'list-title' }, 'Your day'));
    for (const b of blocks) {
        const phase = current?.id === b.id ? 'now' : isToday && b.end <= now ? 'past' : '';
        if (!b.steps.length) {
            frag.append(h('div', { class: `quiet ${phase}`, style: { '--c': areaColor(b.area) } },
                h('span', { class: 'time' }, clock(b.start)),
                h('div', { class: 'grow' }, h('strong', {}, b.title, phase === 'now' && h('span', { class: 'pill' }, 'Now')),
                    b.why && h('small', {}, b.why)),
                h('button', { class: 'icon-btn sm', 'aria-label': `Adjust ${b.title}`, onclick: () => openBlockEditor(viewDate, b.id) }, '✎')));
            continue;
        }
        const n = b.steps.filter((s) => doneSet.has(s.key)).length;
        const open = openBlocks.has(b.id);
        frag.append(h('section', { class: `block ${phase} ${open ? 'open' : ''}`, style: { '--c': areaColor(b.area) } },
            h('button', {
                class: 'block-head', onclick: () => { open ? openBlocks.delete(b.id) : openBlocks.add(b.id); render(); },
            },
                h('span', { class: 'time' }, clock(b.start), h('br'), h('small', {}, clock(b.end))),
                h('span', { class: 'block-title' }, b.title, phase === 'now' && h('span', { class: 'pill' }, 'Now')),
                h('span', { class: 'count' + (n === b.steps.length ? ' all' : '') }, `${n}/${b.steps.length}`),
                h('span', { class: 'chev' }, '›')),
            open && h('div', { class: 'block-body' },
                b.why && h('p', { class: 'why' }, b.why),
                b.steps.map((s) => renderStep(k, s, doneSet.has(s.key))),
                h('button', { class: 'link adjust', onclick: () => openBlockEditor(viewDate, b.id) }, '✎ Adjust this block'))));
    }
    frag.append(h('button', { class: 'btn add-block', onclick: () => openBlockEditor(viewDate, null) }, '+ Add a block to this day'));
    return frag;
}

function greeting(min) {
    const g = content.coach.greetings;
    if (min < 6 * 60) return g.early;
    if (min < 12 * 60) return g.morning;
    if (min < 17 * 60 + 30) return g.afternoon;
    if (min < 21 * 60) return g.evening;
    return g.night;
}

function renderStep(k, s, isDone) {
    const extras = [];
    if (s.app && appById[s.app]) {
        const a = appById[s.app];
        extras.push(h('a', { class: 'chip', href: appUrl(a), target: '_blank', rel: 'noopener' }, h('span', {}, a.icon), a.name, ' ↗'));
    }
    if (s.track) {
        const l = nextLesson(s.track);
        const t = trackById[s.track];
        extras.push(l
            ? h('button', { class: 'chip lesson', onclick: () => openLesson(l.id) }, h('span', {}, t.icon), l.title)
            : h('span', { class: 'chip' }, `${t.icon} ${t.title}: all lessons done 🎉`));
    }
    if (s.practice) {
        const cur = currentPracticeLesson(s.practice);
        if (cur) extras.push(h('button', { class: 'practice', onclick: () => openLesson(cur.id) }, h('b', {}, 'This week: '), cur.practice));
    }
    if (s.action) {
        extras.push(h('button', {
            class: 'chip', onclick: () => {
                ui.tab = 'review'; ui.review = s.action === 'week' ? 'week' : 'day'; saveUi(); render(false);
            },
        }, s.action === 'week' ? '🗓 Open weekly review' : '📓 Open evening review'));
    }
    const habit = s.habit && habitById[s.habit];
    return h('div', { class: 'step' + (isDone ? ' done' : '') },
        h('label', {},
            checkbox(isDone, (e) => {
                editDay(k, (d) => {
                    const set = new Set(d.done);
                    e.target.checked ? set.add(s.key) : set.delete(s.key);
                    d.done = [...set];
                });
                render();
            }),
            h('span', {}, s.text, habit && h('span', { class: 'tag', title: 'Counts toward this habit' }, habit.icon))),
        extras.length && h('div', { class: 'extras' }, extras));
}

/** The most recently opened lesson in a track, or the next one: what you're practising this week. */
function currentPracticeLesson(trackId) {
    const t = trackById[trackId];
    const done = t.lessons.filter((l) => lessonDone(l.id))
        .sort((a, b) => (state.lessons[b.id].doneOn ?? '').localeCompare(state.lessons[a.id].doneOn ?? ''));
    const recent = done[0];
    if (recent && state.lessons[recent.id].doneOn >= keyOf(addDays(new Date(), -7))) return recent;
    return nextLesson(trackId);
}

// -- Grow --

function renderGrow() {
    const frag = h('div', { class: 'stack' });
    const total = Object.keys(lessonById).length;
    const doneN = Object.keys(lessonById).filter(lessonDone).length;
    frag.append(h('div', { class: 'card' },
        h('h3', {}, 'Grow'),
        h('p', { class: 'muted' }, `Five tracks, ${total} lessons. Each lesson has one idea, one practice for the week, and one question. ${doneN} done so far.`),
        h('div', { class: 'bar big' }, h('span', { style: { width: (total ? (doneN / total) * 100 : 0) + '%' } }))));
    for (const t of content.tracks) {
        const n = t.lessons.filter((l) => lessonDone(l.id)).length;
        const open = ui.openTracks.includes(t.id);
        const next = nextLesson(t.id);
        frag.append(h('section', { class: 'card track', style: { '--c': areaColor(t.area) } },
            h('button', {
                class: 'track-head', onclick: () => {
                    ui.openTracks = open ? ui.openTracks.filter((x) => x !== t.id) : [...ui.openTracks, t.id];
                    saveUi(); render();
                },
            },
                h('span', { class: 'track-icon' }, t.icon),
                h('span', { class: 'grow' }, h('strong', {}, t.title), h('small', {}, t.subtitle)),
                h('span', { class: 'count' }, `${n}/${t.lessons.length}`)),
            h('div', { class: 'bar' }, h('span', { style: { width: (n / t.lessons.length) * 100 + '%' } })),
            next && !open && h('button', { class: 'up-next', onclick: () => openLesson(next.id) }, h('small', {}, 'Up next'), next.title),
            open && h('ol', { class: 'lessons' }, t.lessons.map((l) => h('li', {},
                h('button', { class: lessonDone(l.id) ? 'done' : '', onclick: () => openLesson(l.id) },
                    h('span', { class: 'tick' }, lessonDone(l.id) ? '✓' : ''), l.title,
                    state.lessons[l.id]?.note && h('span', { class: 'tag' }, '✎')))))));
    }
    return frag;
}

function openLesson(id) {
    const l = lessonById[id];
    const t = trackById[l.track];
    const dlg = $('#lesson-dialog');
    const idx = t.lessons.findIndex((x) => x.id === id);
    const nextL = t.lessons[idx + 1];
    const saved = state.lessons[id] ?? {};
    dlg.replaceChildren(h('div', { class: 'dialog-body lesson', style: { '--c': areaColor(t.area) } },
        h('div', { class: 'eyebrow' }, `${t.icon} ${t.title} · ${idx + 1} of ${t.lessons.length}`),
        h('h2', {}, l.title),
        h('p', { class: 'idea' }, fill(l.idea)),
        h('div', { class: 'callout' }, h('h5', {}, 'Practice this week'), h('p', {}, fill(l.practice))),
        h('div', { class: 'callout ask' }, h('h5', {}, 'Ask yourself'), h('p', {}, fill(l.ask))),
        l.read?.length && h('div', { class: 'reading' }, h('h5', {}, 'Read'),
            h('ul', {}, l.read.map((r) => h('li', {}, r.url ? h('a', { href: r.url, target: '_blank', rel: 'noopener' }, r.title) : h('em', {}, r.title),
                r.by && h('span', { class: 'muted' }, ` · ${r.by}`))))),
        h('h5', {}, 'My notes'),
        h('textarea', {
            placeholder: 'What you tried, what happened, what you\'ll do differently…', value: saved.note ?? '',
            oninput: (e) => setLesson(id, { note: e.target.value }),
        })),
    h('div', { class: 'dialog-actions' },
        h('button', {
            class: 'btn ' + (saved.done ? '' : 'primary'), onclick: () => {
                setLesson(id, saved.done ? { done: false, doneOn: null } : { done: true, doneOn: todayKey() });
                if (!saved.done) toast('Lesson done. Now try the practice.');
                openLesson(id); render();
            },
        }, saved.done ? '✓ Done (undo)' : 'Mark done'),
        nextL && h('button', { class: 'btn', onclick: () => openLesson(nextL.id) }, 'Next ›'),
        h('button', { class: 'btn', onclick: () => dlg.close() }, 'Close')));
    if (!dlg.open) dlg.showModal();
    dlg.scrollTop = 0;
}

// -- Review --

const MOODS = ['😞', '😕', '😐', '🙂', '😄'];
const ENERGY = ['1', '2', '3', '4', '5'];

function renderReview() {
    const frag = h('div', { class: 'stack' });
    frag.append(h('div', { class: 'segmented' }, [['day', 'Evening'], ['week', 'Week'], ['stats', 'Progress']].map(([v, label]) =>
        h('button', { class: ui.review === v ? 'on' : '', onclick: () => { ui.review = v; saveUi(); render(false); } }, label))));
    if (ui.review === 'day') frag.append(renderDayReview());
    else if (ui.review === 'week') frag.append(renderWeekReview());
    else frag.append(renderStats());
    return frag;
}

function scale(values, current, onpick, cls) {
    return h('div', { class: 'scale ' + cls }, values.map((v, i) =>
        h('button', { class: current === i + 1 ? 'on' : '', onclick: () => onpick(current === i + 1 ? null : i + 1) }, v)));
}

function renderDayReview() {
    const k = keyOf(viewDate);
    const log = dayLog(k);
    const tomorrow = keyOf(addDays(viewDate, 1));
    const tlog = dayLog(tomorrow);
    const done = doneHabits(viewDate), planned = plannedHabits(viewDate);
    const missed = [...planned].filter((x) => !done.has(x)).map((x) => habitById[x].title);
    return h('div', { class: 'stack' },
        h('div', { class: 'card' },
            h('h3', {}, `Evening review · ${longDate(viewDate)}`),
            h('p', { class: 'muted' }, `${done.size} of ${planned.size} habits done.` + (missed.length ? ` Not today: ${missed.join(', ')}. That's fine; tomorrow is a new day.` : ' A full day. Well done.')),
            h('h5', {}, 'Mood'),
            scale(MOODS, log.mood, (v) => { editDay(k, (d) => { d.mood = v; }); render(); }, 'mood'),
            h('h5', {}, 'Energy'),
            scale(ENERGY, log.energy, (v) => { editDay(k, (d) => { d.energy = v; }); render(); }, 'energy'),
            h('h5', {}, 'Three wins (small ones count)'),
            [0, 1, 2].map((i) => h('input', {
                type: 'text', class: 'line', value: log.wins[i], placeholder: `Win ${i + 1}`,
                oninput: (e) => editDay(k, (d) => { d.wins[i] = e.target.value; }),
            })),
            h('h5', {}, 'One gratitude'),
            h('input', { type: 'text', class: 'line', value: log.gratitude, placeholder: 'Today I\'m grateful for…', oninput: (e) => editDay(k, (d) => { d.gratitude = e.target.value; }) }),
            h('h5', {}, 'Notes'),
            h('textarea', { value: log.note, placeholder: 'What drained you? What did you learn? What would you do differently?', oninput: (e) => editDay(k, (d) => { d.note = e.target.value; }) })),
        h('div', { class: 'card' },
            h('h3', {}, `Top 3 for ${addDays(viewDate, 1).toLocaleDateString(undefined, { weekday: 'long' })}`),
            h('p', { class: 'muted' }, 'These appear at the top of tomorrow\'s plan.'),
            [0, 1, 2].map((i) => h('input', {
                type: 'text', class: 'line', value: tlog.focus[i], placeholder: ['The one thing that matters most', 'Second', 'Third'][i],
                oninput: (e) => editDay(tomorrow, (d) => { d.focus[i] = e.target.value; }),
            }))));
}

const WEEK_FIELDS = [
    ['wins', 'Wins this week', 'What went well, at work and at home?'],
    ['learned', 'What I learned', 'From lessons, labs, mistakes and people'],
    ['drained', 'What drained my energy', 'And what can I change about it?'],
    ['family', 'Family highlight', 'A moment with the kids or with your wife'],
    ['stop', 'One thing to stop', 'A commitment, a habit, or a meeting'],
];
const BIG3 = [['craft', '🛠 Craft'], ['lead', '🧭 Leadership'], ['gig', '🚀 Gig'], ['family', '🏡 Family']];

function renderWeekReview() {
    const mon = mondayOf(viewDate);
    const wk = isoWeek(viewDate);
    const w = state.weeks[wk] ?? {};
    const end = addDays(mon, 7);
    const { stats, moods, energies } = habitStats(end, 7);
    const lessonsDone = Object.entries(state.lessons).filter(([, v]) => v.done && v.doneOn >= keyOf(mon) && v.doneOn < keyOf(end));
    const byArea = {};
    for (const [id, s] of Object.entries(stats)) {
        const a = habitById[id].area;
        const x = (byArea[a] ??= { planned: 0, done: 0 });
        x.planned += s.planned; x.done += s.done;
    }
    return h('div', { class: 'stack' },
        h('div', { class: 'card' },
            h('h3', {}, `Week ${wk.split('-W')[1]} · ${shortDate(mon)} – ${shortDate(addDays(mon, 6))}`),
            h('div', { class: 'area-bars' }, Object.entries(byArea).map(([a, x]) => h('div', { class: 'area-bar', style: { '--c': areaColor(a) } },
                h('span', {}, `${areaById[a].icon} ${areaById[a].title}`),
                h('div', { class: 'bar' }, h('span', { style: { width: (x.planned ? (x.done / x.planned) * 100 : 0) + '%' } })),
                h('small', {}, `${x.done}/${x.planned}`)))),
            h('p', { class: 'muted small' },
                `Mood ${avg(moods)?.toFixed(1) ?? '–'} · Energy ${avg(energies)?.toFixed(1) ?? '–'} · Lessons done ${lessonsDone.length}`)),
        h('div', { class: 'card' },
            h('h3', {}, 'Look back'),
            WEEK_FIELDS.map(([key, label, ph]) => [h('h5', {}, label),
                h('textarea', { class: 'short', value: w[key] ?? '', placeholder: ph, oninput: (e) => editWeek(wk, (x) => { x[key] = e.target.value; }) })])),
        h('div', { class: 'card' },
            h('h3', {}, 'Next week\'s Big 3'),
            h('p', { class: 'muted' }, 'One outcome per area. Small and specific beats ambitious and vague.'),
            BIG3.map(([key, label]) => h('div', { class: 'big3' }, h('span', {}, label),
                h('input', {
                    type: 'text', class: 'line', value: w.big3?.[key] ?? '',
                    oninput: (e) => editWeek(wk, (x) => { x.big3 = Object.assign({}, x.big3, { [key]: e.target.value }); }),
                })))));
}

function renderStats() {
    const today = startOfDay(new Date());
    const first = firstDayKey();
    const N = 28;
    const days = Array.from({ length: N }, (_, i) => addDays(today, i - N + 1));
    const { stats, days: counted } = habitStats(addDays(today, 1), N);
    const rows = content.rhythm.habits.filter((x) => habitOn(x.id)).map((x) => {
        const s = stats[x.id] ?? { planned: 0, done: 0 };
        const e = expected(x.id, s, counted);
        const target = habitTarget(x.id);
        return h('div', { class: 'stat-row', style: { '--c': areaColor(x.area) } },
            h('div', { class: 'stat-label' }, h('span', {}, x.icon), h('span', { class: 'grow' }, x.title, target && h('small', {}, ` · ${target}/week`)),
                h('small', {}, `🔥 ${streak(x.id, today)} · ${e ? Math.round((Math.min(s.done, e) / e) * 100) : 0}%`)),
            h('div', { class: 'dots' }, days.map((d) => {
                const k = keyOf(d);
                let cls = 'blank';
                if (first && k >= first) {
                    if (!plannedHabits(d).has(x.id)) cls = 'off';
                    else cls = doneHabits(d).has(x.id) ? 'yes' : 'no';
                }
                return h('i', { class: cls, title: `${shortDate(d)}` });
            })));
    });
    const moodBars = days.map((d) => {
        const log = state.days[keyOf(d)];
        return h('div', { class: 'mbar', title: shortDate(d) },
            h('i', { class: 'm', style: { height: ((log?.mood ?? 0) / 5) * 100 + '%' } }),
            h('i', { class: 'e', style: { height: ((log?.energy ?? 0) / 5) * 100 + '%' } }));
    });
    const lessonsN = Object.values(state.lessons).filter((l) => l.done).length;
    return h('div', { class: 'stack' },
        h('div', { class: 'card' },
            h('h3', {}, 'Last 4 weeks'),
            h('p', { class: 'muted small' }, 'Each dot is a day: filled = done, ring = planned but missed, faint = not planned that day. 🔥 is the current streak.'),
            rows),
        h('div', { class: 'card' },
            h('h3', {}, 'Mood and energy'),
            h('div', { class: 'mood-chart' }, moodBars),
            h('p', { class: 'muted small' }, h('span', { class: 'key m' }), ' mood  ', h('span', { class: 'key e' }), ' energy'),
            h('p', { class: 'muted small' }, `${lessonsN} lessons done in total.`)));
}

// -- Plan --

function renderPlan() {
    const frag = h('div', { class: 'stack' });
    frag.append(renderGoals());
    const adjust = renderAdjust();
    if (adjust) frag.append(adjust);
    frag.append(renderRhythm());
    frag.append(renderHabits());
    frag.append(renderApps());
    return frag;
}

/** What two to three weeks of ticks say about the plan. */
function renderAdjust() {
    const today = startOfDay(new Date());
    const skipped = skippedSteps(today).slice(0, 4);
    const ups = levelUps(today).slice(0, 3);
    if (!skipped.length && !ups.length) return null;
    return h('div', { class: 'card' },
        h('h3', {}, '🔧 Adjust to your practice'),
        h('p', { class: 'muted small' }, 'From the last 2–3 weeks of ticks. A plan you follow beats a perfect plan you skip.'),
        skipped.map((s) => h('div', { class: 'adjust-row' },
            h('div', { class: 'grow' }, h('strong', {}, s.text), h('small', {}, `Done ${s.done} of ${s.planned} days`)),
            h('button', { class: 'chip', onclick: () => openBlockEditor(s.day, s.block) }, 'Adjust'))),
        ups.map((u) => h('div', { class: 'adjust-row' },
            h('div', { class: 'grow' }, h('strong', {}, `${habitById[u.id].icon} ${habitById[u.id].title}`), h('small', {}, `${u.pct}% for 3 weeks: ready for a bigger step?`)))));
}

function renderHabits() {
    const c = custom();
    const setHabit = (id, patch) => editCustom((x) => {
        const v = { ...x.habits[id], ...patch };
        if (!v.off) delete v.off;
        if (!v.target) delete v.target;
        if (Object.keys(v).length) x.habits[id] = v; else delete x.habits[id];
    });
    const changed = Object.keys(c.blocks).length + Object.keys(c.steps).length + Object.keys(c.habits).length
        + Object.values(c.addedBlocks).flat().length + Object.values(c.addedSteps).flat().length;
    return h('div', { class: 'card' },
        h('h3', {}, 'Habits'),
        h('p', { class: 'muted small' }, 'Turn off a habit you aren\'t practising now; its steps stay in the plan but stop counting. A weekly target means fewer days still count as 100%.'),
        content.rhythm.habits.map((x) => {
            const on = habitOn(x.id);
            return h('div', { class: 'habit-row' + (on ? '' : ' off'), style: { '--c': areaColor(x.area) } },
                checkbox(on, (e) => { setHabit(x.id, { off: !e.target.checked }); render(); }, areaColor(x.area)),
                h('span', { class: 'grow' }, `${x.icon} ${x.title}`),
                h('select', {
                    class: 'compact', disabled: !on, 'aria-label': `${x.title} target`,
                    onchange: (e) => { setHabit(x.id, { target: Number(e.target.value) || null }); render(); },
                }, h('option', { value: '' }, 'Every planned day'),
                [1, 2, 3, 4, 5, 6].map((n) => h('option', { value: n, selected: habitTarget(x.id) === n }, `${n}× a week`))));
        }),
        changed > 0 && h('div', { class: 'row-buttons' },
            h('span', { class: 'muted small grow' }, `${changed} change${changed === 1 ? '' : 's'} to the default plan.`),
            h('button', {
                class: 'btn bad', onclick: () => {
                    if (!confirm('Undo all your changes to blocks, steps and habits, and go back to the default plan? Your ticks and reviews stay.')) return;
                    editCustom((x) => Object.assign(x, emptyCustom()));
                    render();
                },
            }, 'Reset plan')));
}

const WD_NAME = { mon: 'Monday', tue: 'Tuesday', wed: 'Wednesday', thu: 'Thursday', fri: 'Friday', sat: 'Saturday', sun: 'Sunday' };

/** Writes one override field for a scope ('default' or a weekday), dropping it when it matches what it overrides. */
function setOverride(o, field, scope, value, base) {
    const m = { ...(o[field] ?? {}) };
    if (scope === 'default') {
        for (const k of Object.keys(m)) delete m[k];
        if (value !== base) m.default = value;
    } else if (value === (m.default ?? base)) delete m[scope];
    else m[scope] = value;
    if (Object.keys(m).length) o[field] = m; else delete o[field];
}

/** Edit one block of the day `d` (or add one when `blockId` is null). */
function openBlockEditor(d, blockId) {
    d = startOfDay(d);
    const dlg = $('#block-dialog');
    const wd = wdOf(d), tid = templateIdFor(d), tpl = content.rhythm.templates[tid];
    const tdays = templateDays(tid);
    const key = blockId && `${tid}/${blockId}`;
    const isNew = !blockId;
    const spec = blockId && tpl.blocks.find((b) => b.id === blockId);
    const added = blockId && !spec ? (custom().addedBlocks[tid] ?? []).find((b) => b.id === blockId) : null;
    const cur = blockId && blocksFor(d, { all: true }).find((b) => b.id === blockId);
    if (blockId && !cur) return;
    const isCustom = isNew || !!added;

    const scopeAll = h('input', { type: 'radio', name: 'scope', checked: isCustom ? !added?.days?.length : true });
    const scopeOne = h('input', { type: 'radio', name: 'scope', checked: isCustom ? !!added?.days?.length : false });
    const scope = () => (tdays.length > 1 && scopeOne.checked ? wd : 'default');
    const title = h('input', { type: 'text', class: 'line', value: cur?.title ?? '', placeholder: 'e.g. Evening walk' });
    const hhmm = (m) => `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;
    const start = h('input', { type: 'time', class: 'line compact', value: cur ? hhmm(cur.start) : '19:30' });
    const end = h('input', { type: 'time', class: 'line compact', value: cur ? hhmm(cur.end) : '20:00' });
    const area = h('select', {}, content.rhythm.areas.map((a) =>
        h('option', { value: a.id, selected: a.id === (cur?.area ?? 'health') }, `${a.icon} ${a.title}`)));
    const skip = h('input', { type: 'checkbox', checked: !!cur?.hidden });

    const appOptions = (v) => [h('option', { value: '' }, 'No app'),
        ...content.apps.map((a) => h('option', { value: a.id, selected: a.id === v }, `${a.icon} ${a.name}`))];
    const habitOptions = (v) => [h('option', { value: '' }, 'No habit'),
        ...content.rhythm.habits.map((x) => h('option', { value: x.id, selected: x.id === v }, `${x.icon} ${x.title}`))];

    const rows = [];
    const stepList = h('div', { class: 'step-edit-list' });
    const addRow = (s) => {
        const row = {
            s,
            text: h('input', { type: 'text', class: 'line', value: s?.text ?? '', placeholder: 'What will you do?' }),
            app: h('select', { class: 'compact' }, appOptions(s?.app ?? '')),
            habit: h('select', { class: 'compact' }, habitOptions(rawHabit(s))),
            hide: h('input', { type: 'checkbox', checked: !!s?.hidden }),
            removed: false,
        };
        const el = h('div', { class: 'step-edit' }, row.text,
            h('div', { class: 'edit-row' }, row.app, row.habit,
                s && !s.custom
                    ? h('label', { class: 'small' }, row.hide, ' skip')
                    : h('button', { class: 'link bad', onclick: () => { row.removed = true; el.remove(); } }, 'Remove')));
        rows.push(row);
        stepList.append(el);
        return row;
    };
    // The habit select shows a habit even while it's turned off, so it isn't lost on save.
    const rawHabit = (s) => {
        if (!s) return '';
        if (s.custom) return (custom().addedSteps[key] ?? []).find((x) => x.id === s.sid)?.habit ?? '';
        const so = custom().steps[`${key}/${s.sid}`] ?? {};
        return pick(resolve(so.habit, wd), spec.steps.find((x) => x.id === s.sid)?.habit) ?? '';
    };
    for (const s of cur?.steps ?? []) addRow(s);

    const save = () => {
        const t = title.value.trim();
        if (!t) { title.focus(); return; }
        if (!start.value || !end.value || toMin(end.value) <= toMin(start.value)) { toast('End time must be after the start.'); return; }
        const sc = scope();
        editCustom((c) => {
            let bid = blockId;
            if (isCustom) {
                const list = [...(c.addedBlocks[tid] ?? [])];
                bid ??= `c${Date.now().toString(36)}`;
                const rec = { id: bid, start: start.value, end: end.value, title: t, area: area.value, days: sc === 'default' ? null : [wd] };
                const i = list.findIndex((b) => b.id === bid);
                if (i >= 0) list[i] = rec; else list.push(rec);
                c.addedBlocks[tid] = list;
            } else {
                const o = { ...c.blocks[key] };
                const base = { title: spec.title, start: spec.start, end: spec.end, area: spec.area, hidden: false };
                const now = { title: cur.title, start: hhmm(cur.start), end: hhmm(cur.end), area: cur.area, hidden: cur.hidden };
                const next = { title: t, start: start.value, end: end.value, area: area.value, hidden: skip.checked };
                for (const f of Object.keys(base)) if (next[f] !== now[f]) setOverride(o, f, sc, next[f], base[f]);
                if (Object.keys(o).length) c.blocks[key] = o; else delete c.blocks[key];
            }
            const bkey = `${tid}/${bid}`;
            const addedSteps = [...(c.addedSteps[bkey] ?? [])];
            for (const r of rows) {
                const text = r.text.value.trim();
                if (!r.s || r.s.custom) {
                    const i = r.s ? addedSteps.findIndex((x) => x.id === r.s.sid) : -1;
                    if (r.removed || !text) { if (i >= 0) addedSteps.splice(i, 1); continue; }
                    const rec = { id: r.s?.sid ?? `c${Date.now().toString(36)}${rows.indexOf(r)}`, text, app: r.app.value, habit: r.habit.value,
                        days: r.s ? r.s.days : (sc === 'default' ? null : [wd]) };
                    if (i >= 0) addedSteps[i] = rec; else addedSteps.push(rec);
                    continue;
                }
                const sspec = spec.steps.find((x) => x.id === r.s.sid);
                const skey = `${key}/${r.s.sid}`;
                const o = { ...c.steps[skey] };
                const base = { text: fill(resolve(sspec.text, wd) ?? ''), app: resolve(sspec.app, wd) ?? '', habit: sspec.habit ?? '', hidden: false };
                const now = { text: r.s.text, app: r.s.app ?? '', habit: rawHabit(r.s), hidden: r.s.hidden };
                const next = { text: text || now.text, app: r.app.value, habit: r.habit.value, hidden: r.hide.checked };
                for (const f of Object.keys(base)) if (next[f] !== now[f]) setOverride(o, f, sc, next[f], base[f]);
                if (Object.keys(o).length) c.steps[skey] = o; else delete c.steps[skey];
            }
            if (addedSteps.length) c.addedSteps[bkey] = addedSteps; else delete c.addedSteps[bkey];
        });
        dlg.close();
        render();
        toast('Plan updated.');
    };

    const reset = () => {
        if (!confirm('Put this block back the way it was, on every day?')) return;
        editCustom((c) => {
            delete c.blocks[key];
            delete c.addedSteps[key];
            for (const k of Object.keys(c.steps)) if (k.startsWith(key + '/')) delete c.steps[k];
        });
        dlg.close(); render();
    };
    const remove = () => {
        if (!confirm('Delete this block?')) return;
        editCustom((c) => {
            c.addedBlocks[tid] = (c.addedBlocks[tid] ?? []).filter((b) => b.id !== blockId);
            if (!c.addedBlocks[tid].length) delete c.addedBlocks[tid];
            delete c.addedSteps[key];
        });
        dlg.close(); render();
    };
    const hasChanges = key && (custom().blocks[key] || custom().addedSteps[key]
        || Object.keys(custom().steps).some((k) => k.startsWith(key + '/')));

    dlg.replaceChildren(h('div', { class: 'dialog-body' },
        h('h2', {}, isNew ? 'New block' : 'Adjust block'),
        tdays.length > 1 && h('div', { class: 'scope' },
            h('label', {}, scopeAll, ` Every ${tpl.title.toLowerCase()} (${tdays.map((x) => x[0].toUpperCase() + x.slice(1)).join(', ')})`),
            h('label', {}, scopeOne, ` Only ${WD_NAME[wd]}s`)),
        tdays.length === 1 && h('p', { class: 'muted small' }, `Applies to every ${WD_NAME[wd]}.`),
        h('h5', {}, 'Block'), title,
        h('div', { class: 'edit-row' }, h('label', { class: 'small' }, 'From ', start), h('label', { class: 'small' }, ' to ', end), area),
        !isCustom && h('label', { class: 'small' }, skip, tdays.length > 1 ? ' Skip this block (for the days chosen above)' : ' Skip this block'),
        h('h5', {}, 'Steps'),
        h('p', { class: 'muted small' }, 'Link a step to a habit to count it, or to an app to open it from Today.'),
        stepList,
        h('button', { class: 'btn', onclick: () => addRow(null).text.focus() }, '+ Add step')),
    h('div', { class: 'dialog-actions' },
        h('button', { class: 'btn primary', onclick: save }, 'Save'),
        !isCustom && hasChanges && h('button', { class: 'btn', onclick: reset }, 'Reset to default'),
        added && h('button', { class: 'btn bad', onclick: remove }, 'Delete block'),
        h('button', { class: 'btn', onclick: () => dlg.close() }, 'Cancel')));
    dlg.showModal();
}

function goalsForQuarter(q) {
    return Object.values(state.goals).filter((g) => g.quarter === q && !g.deleted)
        .sort((a, b) => (a.created ?? 0) - (b.created ?? 0));
}

function renderGoals() {
    const q = ui.quarter ?? quarterOf(new Date());
    const goals = goalsForQuarter(q);
    const used = new Set(goals.map((g) => g.from).filter(Boolean));
    const suggestions = content.goals.filter((g) => !used.has(g.id));
    const shiftQ = (n) => {
        const [y, qq] = q.split('-Q').map(Number);
        const idx = y * 4 + (qq - 1) + n;
        ui.quarter = `${Math.floor(idx / 4)}-Q${(idx % 4) + 1}`;
        saveUi(); render();
    };
    return h('div', { class: 'card' },
        h('div', { class: 'card-head' },
            h('h3', {}, `Goals · ${q.replace('-', ' ')}`),
            h('button', { class: 'icon-btn sm', onclick: () => shiftQ(-1), 'aria-label': 'Previous quarter' }, '‹'),
            h('button', { class: 'icon-btn sm', onclick: () => shiftQ(1), 'aria-label': 'Next quarter' }, '›')),
        !goals.length && h('p', { class: 'muted' }, 'Pick 3 to 5 goals for the quarter, at most one or two per area. Start from a suggestion below or write your own.'),
        goals.map((g) => {
            const n = g.milestones.filter((m) => m.done).length;
            return h('div', { class: 'goal', style: { '--c': areaColor(g.area) } },
                h('div', { class: 'goal-head' },
                    h('span', {}, areaById[g.area]?.icon),
                    h('strong', { class: 'grow' }, g.title),
                    h('button', { class: 'link', onclick: () => editGoal(g) }, 'Edit')),
                h('div', { class: 'bar' }, h('span', { style: { width: (g.milestones.length ? (n / g.milestones.length) * 100 : 0) + '%' } })),
                g.milestones.map((m, i) => h('label', { class: 'milestone' + (m.done ? ' done' : '') },
                    checkbox(m.done, (e) => {
                        const ms = g.milestones.map((x, j) => (j === i ? { ...x, done: e.target.checked } : x));
                        saveGoal({ ...g, milestones: ms }); render();
                    }, areaColor(g.area)),
                    m.text)));
        }),
        h('div', { class: 'row-buttons' },
            h('button', { class: 'btn', onclick: () => editGoal({ id: `g${Date.now()}`, quarter: q, area: 'career', title: '', milestones: [], created: Date.now() }, true) }, '+ New goal')),
        suggestions.length > 0 && h('details', { class: 'suggest' },
            h('summary', {}, `Suggestions (${suggestions.length})`),
            suggestions.map((s) => h('div', { class: 'suggestion', style: { '--c': areaColor(s.area) } },
                h('span', {}, areaById[s.area]?.icon),
                h('span', { class: 'grow' }, s.title),
                h('button', {
                    class: 'link', onclick: () => {
                        saveGoal({ id: `g${Date.now()}`, from: s.id, quarter: q, area: s.area, title: s.title, milestones: s.milestones.map((t) => ({ text: t, done: false })), created: Date.now() });
                        render();
                    },
                }, 'Add')))));
}

function editGoal(goal, isNew = false) {
    const dlg = $('#goal-dialog');
    const title = h('input', { type: 'text', class: 'line', value: goal.title, placeholder: 'What will be true at the end of the quarter?' });
    const area = h('select', {}, content.rhythm.areas.filter((a) => a.id !== 'rest').map((a) =>
        h('option', { value: a.id, selected: a.id === goal.area }, `${a.icon} ${a.title}`)));
    const ms = h('textarea', { value: goal.milestones.map((m) => m.text).join('\n'), placeholder: 'One milestone per line' });
    dlg.replaceChildren(h('div', { class: 'dialog-body' },
        h('h2', {}, isNew ? 'New goal' : 'Edit goal'),
        h('h5', {}, 'Goal'), title,
        h('h5', {}, 'Area'), area,
        h('h5', {}, 'Milestones'), ms),
    h('div', { class: 'dialog-actions' },
        h('button', {
            class: 'btn primary', onclick: () => {
                if (!title.value.trim()) { title.focus(); return; }
                const old = Object.fromEntries(goal.milestones.map((m) => [m.text, m.done]));
                const milestones = ms.value.split('\n').map((t) => t.trim()).filter(Boolean).map((t) => ({ text: t, done: !!old[t] }));
                saveGoal({ ...goal, title: title.value.trim(), area: area.value, milestones });
                dlg.close(); render();
            },
        }, 'Save'),
        !isNew && h('button', {
            class: 'btn bad', onclick: () => {
                if (!confirm('Delete this goal?')) return;
                saveGoal({ ...goal, deleted: true }); dlg.close(); render();
            },
        }, 'Delete'),
        h('button', { class: 'btn', onclick: () => dlg.close() }, 'Cancel')));
    dlg.showModal();
}

function renderRhythm() {
    const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    const day = ui.planDay ?? wdOf(new Date());
    const mon = mondayOf(new Date());
    const d = addDays(mon, days.indexOf(day));
    return h('div', { class: 'card' },
        h('h3', {}, 'Weekly rhythm'),
        h('p', { class: 'muted' }, content.rhythm.summary
            ?? `Up at ${clock(toMin(content.rhythm.wake))}, lights out at ${clock(toMin(content.rhythm.sleep))}.`),
        h('p', { class: 'muted small' }, 'Tap ✎ to change a block\'s time, steps or apps to match how you actually practise.'),
        h('div', { class: 'day-chips' }, days.map((x) => h('button', {
            class: x === day ? 'on' : '', onclick: () => { ui.planDay = x; saveUi(); render(); },
        }, x[0].toUpperCase() + x.slice(1)))),
        h('div', { class: 'rhythm' }, blocksFor(d, { all: true }).map((b) => h('div', {
            class: 'rhythm-row' + (b.hidden ? ' skipped' : '') + (b.steps.some((s) => !s.hidden) ? '' : ' quiet-row'),
            style: { '--c': areaColor(b.area) },
        },
            h('span', { class: 'time' }, clock(b.start)),
            h('div', { class: 'grow' }, h('strong', {}, b.title, b.hidden && h('small', {}, ' · skipped'), b.custom && h('small', {}, ' · yours')),
                !b.steps.some((s) => !s.hidden) && b.why && h('small', { class: 'quiet-why' }, b.why),
                h('ul', {}, b.steps.filter((s) => !s.hidden && (s.habit || s.app || s.track || s.custom)).map((s) => h('li', {}, s.text)))),
            h('button', { class: 'icon-btn sm', 'aria-label': `Adjust ${b.title}`, onclick: () => openBlockEditor(d, b.id) }, '✎')))),
        h('div', { class: 'row-buttons' },
            h('button', { class: 'btn', onclick: () => openBlockEditor(d, null) }, '+ Add block')));
}

function renderApps() {
    return h('div', { class: 'card' },
        h('h3', {}, 'My apps'),
        content.categories.map((c) => [h('h5', {}, c.title),
            content.apps.filter((a) => a.category === c.id).map((a) => h('a', {
                class: 'app-row', href: appUrl(a), target: '_blank', rel: 'noopener',
            },
                h('span', { class: 'app-icon' }, a.icon),
                h('span', { class: 'grow' }, h('strong', {}, a.name), h('small', {}, a.about)),
                h('span', { class: 'muted small' }, a.web ? 'Open ↗' : 'Mac · repo ↗')))]));
}

// ---- Drawer, backup, settings ----

function renderDrawer() {
    const body = $('#drawer-body');
    body.replaceChildren(
        h('h4', {}, 'Family names'),
        h('p', { class: 'muted small' }, 'Used in the plan and the coach\'s messages. Saved only on this device.'),
        h('div', { class: 'panel' }, content.rhythm.family.map((f) => h('div', { class: 'row' },
            h('label', { class: 'grow' }, f.name),
            h('input', {
                type: 'text', class: 'line compact', value: state.settings?.family?.[f.id] ?? '', placeholder: f.name,
                oninput: (e) => {
                    state.settings = { family: { ...state.settings?.family, [f.id]: e.target.value }, updated: Date.now() };
                    saveState();
                },
                onchange: () => render(),
            })))),
        h('h4', {}, 'Backup and sync'),
        h('p', { class: 'muted small' }, 'Progress is saved on each device. Export here and import on the Mac (File → Import Backup) or another phone. Importing merges: the newer entry wins.'),
        h('div', { class: 'panel' },
            h('button', { class: 'menu-btn', onclick: exportBackup }, '⬇︎ Export backup'),
            h('button', { class: 'menu-btn', onclick: () => $('#import-file').click() }, '⬆︎ Import backup…')),
        h('h4', {}, 'About'),
        h('p', { class: 'muted small' }, `Content ${content.version} · ${Object.keys(lessonById).length} lessons · works offline once opened.`),
        h('div', { class: 'panel' },
            locked && h('button', { class: 'menu-btn', onclick: lockNow }, '🔒 Lock now (forget the passcode on this device)'),
            h('a', { class: 'menu-btn', href: 'https://github.com/venkatacrc/coach', target: '_blank', rel: 'noopener' }, 'Source on GitHub ↗'),
            h('button', {
                class: 'menu-btn danger', onclick: () => {
                    if (!confirm('Erase all progress, reviews and goals on this device? Export a backup first if unsure.')) return;
                    state = emptyState(); saveState(); closeDrawer(); render(false);
                },
            }, 'Erase all data on this device…')));
}

function exportBackup() {
    const blob = new Blob([JSON.stringify(state, null, 1)], { type: 'application/json' });
    const a = h('a', { href: URL.createObjectURL(blob), download: `coach-backup-${todayKey()}.json` });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

$('#import-file').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;
    try {
        const incoming = JSON.parse(await file.text());
        if (!incoming || typeof incoming !== 'object' || !('days' in incoming)) throw new Error('not a Coach backup');
        const n = mergeState(incoming);
        closeDrawer();
        render(false);
        toast(`Imported: ${n} entries updated.`);
    } catch (err) {
        toast(`Import failed: ${err.message}`);
    }
});

function openDrawer() {
    renderDrawer();
    $('#drawer').classList.add('open');
    $('#drawer').setAttribute('aria-hidden', 'false');
    $('#backdrop').hidden = false;
}

function closeDrawer() {
    $('#drawer').classList.remove('open');
    $('#drawer').setAttribute('aria-hidden', 'true');
    $('#backdrop').hidden = true;
}

let toastTimer = null;
function toast(text) {
    const t = $('#toast');
    t.textContent = text;
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, 2600);
}

// ---- Wiring ----

$('#open-drawer').addEventListener('click', openDrawer);
$('#close-drawer').addEventListener('click', closeDrawer);
$('#backdrop').addEventListener('click', closeDrawer);
$('#prev-day').addEventListener('click', () => setViewDate(addDays(viewDate, ui.tab === 'review' && ui.review === 'week' ? -7 : -1)));
$('#next-day').addEventListener('click', () => setViewDate(addDays(viewDate, ui.tab === 'review' && ui.review === 'week' ? 7 : 1)));
$('#date-label').addEventListener('click', () => setViewDate(new Date()));
for (const b of document.querySelectorAll('#tabs button')) {
    b.addEventListener('click', () => { ui.tab = b.dataset.tab; saveUi(); render(false); });
}
for (const dlg of document.querySelectorAll('dialog')) {
    dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close(); });
}

function tick() {
    if (!content) return;
    if (followToday && keyOf(viewDate) !== todayKey()) viewDate = startOfDay(new Date());
    const typing = document.activeElement?.matches?.('input, textarea, select');
    const dialogOpen = [...document.querySelectorAll('dialog')].some((d) => d.open);
    if (ui.tab === 'today' && !typing && !dialogOpen) render();
}
setInterval(tick, 60 * 1000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });

// ---- Passcode lock ----
// The public site only has content.enc (tools/lock.mjs): "CCH1" | salt 16 | iv 12 | AES-GCM,
// key from PBKDF2-SHA256 with 250,000 iterations. Local dev serves the plain content.json.

const PASS_KEY = 'coach.passcode';
const isLocal = ['localhost', '127.0.0.1', ''].includes(location.hostname);
const locked = !isLocal || new URLSearchParams(location.search).has('locked');

async function decryptContent(buf, pass) {
    const bytes = new Uint8Array(buf);
    if (new TextDecoder().decode(bytes.subarray(0, 4)) !== 'CCH1') throw new Error('not a sealed coach file');
    const salt = bytes.subarray(4, 20), iv = bytes.subarray(20, 32);
    const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(pass), 'PBKDF2', false, ['deriveKey']);
    const key = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 250000, hash: 'SHA-256' }, base,
        { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, bytes.subarray(32));
    return JSON.parse(new TextDecoder().decode(plain));
}

const savedPass = () => localStorage.getItem(PASS_KEY) ?? sessionStorage.getItem(PASS_KEY);

function lockNow() {
    localStorage.removeItem(PASS_KEY);
    sessionStorage.removeItem(PASS_KEY);
    location.reload();
}

function askPasscode(buf) {
    const gate = $('#gate'), input = $('#gate-pass'), err = $('#gate-error'), go = $('#gate-go');
    $('#app').hidden = true;
    gate.hidden = false;
    input.focus();
    return new Promise((done) => {
        gate.onsubmit = async (e) => {
            e.preventDefault();
            err.hidden = true;
            go.disabled = true;
            go.textContent = 'Unlocking…';
            try {
                const c = await decryptContent(buf, input.value);
                (($('#gate-remember').checked) ? localStorage : sessionStorage).setItem(PASS_KEY, input.value);
                gate.hidden = true;
                $('#app').hidden = false;
                input.value = '';
                done(c);
            } catch {
                err.textContent = 'That passcode didn\'t work.';
                err.hidden = false;
                input.select();
            } finally {
                go.disabled = false;
                go.textContent = 'Unlock';
            }
        };
    });
}

async function loadContent() {
    if (!locked) {
        const res = await fetch('content.json', { cache: 'no-cache' });
        if (!res.ok) throw new Error(`content.json: ${res.status}`);
        return res.json();
    }
    const res = await fetch('content.enc', { cache: 'no-cache' });
    if (!res.ok) throw new Error(`content.enc: ${res.status}`);
    const buf = await res.arrayBuffer();
    const pass = savedPass();
    if (pass) {
        try { return await decryptContent(buf, pass); } catch { lockNow(); return new Promise(() => {}); }
    }
    return askPasscode(buf);
}

async function start() {
    try {
        content = await loadContent();
        indexContent();
        render(false);
    } catch (err) {
        $('#view').replaceChildren(h('div', { class: 'empty' }, h('div', { class: 'big' }, '⚠️'),
            h('h2', {}, 'Could not load the coach'), h('p', {}, String(err))));
    }
}

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
    navigator.serviceWorker.register('sw.js').catch(() => {});
}
start();
