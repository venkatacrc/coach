// Smoke test for the web app in headless Chrome at phone size: every view renders, ticking a
// step counts toward its habit, the coach reacts to a seeded week, lessons and goals save, and
// a backup merges. Screenshots go to build/shots/.
// Usage: node tools/smoke_web.mjs
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SHOTS = join(ROOT, 'build', 'shots');
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 20000 + Math.floor(Math.random() * 20000);
const DEBUG = PORT + 1;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
mkdirSync(SHOTS, { recursive: true });
const START = `http://127.0.0.1:${PORT}/index.html`;

const server = spawn('python3', ['-m', 'http.server', String(PORT), '-d', join(ROOT, 'web')], { stdio: 'ignore' });
const chrome = spawn(CHROME, [
    '--headless=new', `--remote-debugging-port=${DEBUG}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), 'coach-chrome-'))}`,
    '--no-first-run', '--no-default-browser-check', '--window-size=390,844', 'about:blank',
], { stdio: 'ignore' });
const cleanup = () => { chrome.kill(); server.kill(); };
process.on('exit', cleanup);

let ws;
let seq = 0;
const pending = new Map();
const problems = [];
let failures = 0;

async function connect() {
    for (let i = 0; i < 50; i++) {
        try {
            const list = await (await fetch(`http://127.0.0.1:${DEBUG}/json/list`)).json();
            const page = list.find((t) => t.type === 'page');
            if (page) { ws = new WebSocket(page.webSocketDebuggerUrl); break; }
        } catch { /* Chrome still starting */ }
        await sleep(200);
    }
    await new Promise((r) => ws.addEventListener('open', r, { once: true }));
    ws.addEventListener('message', (e) => {
        const m = JSON.parse(e.data);
        if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
        if (m.method === 'Runtime.exceptionThrown') problems.push('exception: ' + m.params.exceptionDetails.exception?.description);
        if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') problems.push('console.error: ' + m.params.args.map((a) => a.value ?? a.description).join(' '));
        if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') problems.push('log: ' + m.params.entry.text + ' ' + (m.params.entry.url || ''));
    });
}
function send(method, params = {}) {
    const id = ++seq;
    ws.send(JSON.stringify({ id, method, params }));
    return new Promise((r) => pending.set(id, r));
}
async function js(expr) {
    const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'evaluate failed');
    return r.result.result.value;
}
async function shot(name) {
    const r = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(SHOTS, name + '.png'), Buffer.from(r.result.data, 'base64'));
}
async function waitFor(expr, ms = 10000) {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
        if (await js(expr)) return true;
        await sleep(200);
    }
    return false;
}
function check(name, ok, detail = '') {
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ' · ' + detail : ''}`);
    if (!ok) failures++;
}
const click = (sel) => js(`(document.querySelector(${JSON.stringify(sel)}).click(), true)`);
const tab = async (name) => { await click(`#tabs button[data-tab="${name}"]`); await sleep(150); };

await connect();
await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
await send('Page.navigate', { url: START });
if (!(await waitFor(`!!document.querySelector('.block')`))) {
    console.log('FAIL today loads', await js(`document.body.innerText.slice(0, 300)`), problems);
    process.exit(1);
}
check('today loads', true, await js(`document.querySelectorAll('.block').length + ' blocks'`));
check('first-run coach says start small', await js(`document.querySelector('.coach').innerText.includes('Start small')`));
await shot('01-today');

// Tick the first habit step of the open block (or open the first block).
await js(`document.querySelector('.block:not(.open) .block-head')?.click(); true`);
await sleep(100);
const before = await js(`document.querySelector('.ring span').textContent`);
await js(`[...document.querySelectorAll('.step')].find((s) => s.querySelector('.tag'))?.querySelector('input').click(); true`);
await sleep(150);
const after = await js(`document.querySelector('.ring span').textContent`);
check('ticking a habit step moves the ring', before !== after, `${before} → ${after}`);
check('tick is saved', await js(`Object.values(JSON.parse(localStorage.getItem('coach.state')).days)[0].done.length === 1`));

// Roadmap: this week's goal is the first step; done moves on; a missed week pushes the finish date out.
const steps = await js(`content.roadmap.steps.length`);
check('week goal is roadmap step 1', await js(`document.querySelector('.week-goal .goal-text')?.textContent === content.roadmap.steps[0].title && document.querySelector('.week-goal').innerText.includes('step 1 of ${steps}')`));
const finish0 = await js(`roadmapProgress().finish.getTime()`);
check('finish date adds up the planned weeks', await js(`(() => { const p = roadmapProgress(); return Math.round((p.finish - addDays(mondayOf(new Date()), 6)) / WEEK_MS) === sumWeeks(p.active) - 1 && p.slip === 0; })()`));
await js(`[...document.querySelectorAll('.week-goal .btn')].find((b) => b.textContent.includes('Done')).click(); true`);
await sleep(150);
check('done moves to step 2, finish date holds', await js(`document.querySelector('.week-goal .done-line')?.innerText.includes(content.roadmap.steps[0].title) && document.querySelector('.week-goal .goal-text').textContent === content.roadmap.steps[1].title && roadmapProgress().finish.getTime() === ${finish0}`));
await shot('01b-week-goal');
await js(`(() => {
    const s = JSON.parse(localStorage.getItem('coach.state'));
    const pad = (n) => String(n).padStart(2, '0');
    const key = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
    const mon = mondayOf(new Date());
    s.roadmap.started = key(addDays(mon, -28));
    s.roadmap.done = { [content.roadmap.steps[0].id]: key(addDays(mon, -26)) };
    localStorage.setItem('coach.state', JSON.stringify(s));
    return true;
})()`);
await send('Page.reload');
await waitFor(`!!document.querySelector('.week-goal .goal-text')`);
check('missed weeks carry the step and move the finish date', await js(`(() => { const p = roadmapProgress(); return p.slip === 3 && p.hits === 1 && p.weeks === 5 && document.querySelector('.week-goal').innerText.includes('3 weeks later') && document.querySelector('.week-goal .goal-text').textContent === content.roadmap.steps[1].title; })()`));
check('pace estimate shows after 4 weeks', await js(`document.querySelector('.week-goal').innerText.includes('At your pace so far (25% of the planned speed)')`));
check('time on the current step is counted and flagged', await js(`(() => { const p = roadmapProgress(); const t = document.querySelector('.week-goal p.over'); return p.took[content.roadmap.steps[0].id] === 3 && p.elapsed === daysBetween(keyOf(addDays(mondayOf(new Date()), -26)), todayKey()) && !!t && t.innerText.includes('Day ' + p.elapsed + ' on this step'); })()`));
await shot('01c-week-goal-behind');

// The focus blocks show this week's step; 🍅 hands it to Simple Pomo, whose logged time comes back as hours.
check('focus blocks carry this week\'s step', await js(`(() => {
    const st = content.rhythm.templates.weekday.blocks.find((b) => b.id === 'build').steps[0];
    const el = renderStep(todayKey(), makeStep('build', st.id, { ...st, text: 'x' }), false);
    return el.querySelector('.practice')?.innerText.includes(roadmapProgress().current.title) && !!el.querySelector('a.pomo');
})()`));
check('focus link hands the step to Simple Pomo', await js(`(() => {
    const u = new URL(document.querySelector('.week-goal a.pomo').href), s = roadmapProgress().current, q = u.searchParams;
    return u.href.startsWith(appById.simple_pomo.web) && q.get('task') === s.title && q.get('ref') === 'coach:' + s.id
        && q.get('est') === String(Math.round(s.weeks * hoursPerWeek() * 60 / 25)) && q.get('start') === '1';
})()`));
await js(`(() => {
    const id = roadmapProgress().current.id, t0 = Date.now() - 86400000;
    const focus = (i) => ({ id: 's' + i, taskId: 't1', phase: 'focus', startedAt: new Date(t0 + i * 3e6).toISOString(), endedAt: new Date(t0 + i * 3e6 + 25 * 6e4).toISOString() });
    localStorage.setItem('simplepomo.store.v1', JSON.stringify({
        tasks: [{ id: 't1', title: 'x', ref: 'coach:' + id }, { id: 't2', title: 'other' }],
        sessions: [focus(0), focus(1), focus(2), { ...focus(3), phase: 'shortBreak' }, { ...focus(4), taskId: 't2' }],
    }));
    return true;
})()`);
await send('Page.reload');
await waitFor(`!!document.querySelector('.week-goal .goal-text')`);
check('pomodoros count as hours on the step', await js(`document.querySelector('.week-goal').innerText.includes('🍅 3 pomodoros, 1.5 h') && roadmapProgress().current.hours === 1.5`));
await js(`document.querySelector('.week-goal').scrollIntoView(); true`);
await shot('01d-week-goal-pomo');

// Seed a week where sleep was missed, then reload: the coach should say so.
await js(`(() => {
    const s = JSON.parse(localStorage.getItem('coach.state'));
    const pad = (n) => String(n).padStart(2, '0');
    const key = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
    for (let i = 1; i <= 7; i++) {
        const d = new Date(); d.setDate(d.getDate() - i);
        s.days[key(d)] = { done: ['sadhana.chant', 'build.roadmap', 'family-pm.tea', 'oneone.time', 'reflect.review', 'shuttle-am.lesson', 'family.breakfast', 'family.together', 'out.oneone', 'kids.choice', 'review.week'], mood: 4, energy: 2, updated: Date.now() };
    }
    localStorage.setItem('coach.state', JSON.stringify(s));
    return true;
})()`);
await send('Page.reload');
await waitFor(`!!document.querySelector('.coach .msg')`);
const coach = await js(`document.querySelector('.coach').innerText`);
check('coach flags missed sleep', coach.includes('Sleep first'), coach.split('\n').slice(1, 3).join(' | '));
check('coach shows a streak or second issue', (await js(`document.querySelectorAll('.coach .msg').length`)) >= 2);
await shot('02-today-coach');

// Grow: open a track, a lesson, mark it done, write a note.
await tab('grow');
check('grow lists 5 tracks', (await js(`document.querySelectorAll('.track').length`)) === 5);
await click('.track .up-next');
await sleep(150);
check('lesson dialog opens', await js(`document.querySelector('#lesson-dialog').open && document.querySelector('#lesson-dialog h2').textContent.length > 0`));
await shot('03-lesson');
await js(`(() => { const t = document.querySelector('#lesson-dialog textarea'); t.value = 'Tried it.'; t.dispatchEvent(new Event('input')); return true; })()`);
await js(`[...document.querySelectorAll('#lesson-dialog .btn')].find((b) => b.textContent === 'Mark done').click(); true`);
await sleep(150);
check('lesson marked done with note', await js(`(() => { const l = JSON.parse(localStorage.getItem('coach.state')).lessons['lead-01']; return l.done && l.note === 'Tried it.'; })()`));
await js(`document.querySelector('#lesson-dialog').close(); true`);
await sleep(100);
await shot('04-grow');

// Review: evening, week and progress.
await tab('review');
await js(`document.querySelectorAll('.scale.mood button')[3].click(); true`);
await sleep(100);
check('mood saved', await js(`Object.entries(JSON.parse(localStorage.getItem('coach.state')).days).some(([k, d]) => d.mood === 4 && d.done?.length === 1)`));
await js(`(() => { const i = document.querySelectorAll('.card')[1].querySelector('input'); i.value = 'Ship the kernel write-up'; i.dispatchEvent(new Event('input')); return true; })()`);
check("tomorrow's top 3 lands on tomorrow", await js(`Object.values(JSON.parse(localStorage.getItem('coach.state')).days).some((d) => d.focus?.[0] === 'Ship the kernel write-up')`));
await shot('05-review-evening');
await js(`[...document.querySelectorAll('.segmented button')].find((b) => b.textContent === 'Week').click(); true`);
await sleep(150);
check('week review renders', await js(`document.querySelectorAll('.big3').length === 3`));
check('week review says the step carries over', await js(`document.querySelector('.week-goal').innerText.includes('Not finished: ' + content.roadmap.steps[1].title)`));
await shot('06-review-week');
await js(`[...document.querySelectorAll('.segmented button')].find((b) => b.textContent === 'Progress').click(); true`);
await sleep(150);
check('progress shows 10 habits × 28 days', (await js(`document.querySelectorAll('.stat-row').length`)) === 10 && (await js(`document.querySelectorAll('.stat-row')[0].querySelectorAll('.dots i').length`)) === 28);
await shot('07-review-progress');

// Plan: the roadmap list, then a suggested goal and a milestone.
await tab('plan');
check('roadmap lists phases with the current step open', await js(`document.querySelectorAll('.roadmap .phase').length === content.roadmap.phases.length && document.querySelector('.roadmap .lessons button.current')?.innerText.includes(content.roadmap.steps[1].title)`));
await shot('08a-roadmap');
await js(`document.querySelector('.roadmap .lessons button.current').click(); true`);
await sleep(150);
check('step dialog has links', await js(`document.querySelector('#step-dialog').open && document.querySelectorAll('#step-dialog .reading a').length > 0`));
check('plan shows planned vs actual', await js(`document.querySelector('.roadmap').innerText.includes('planned at 1 week and took 3 days (0.4× the plan)') && document.querySelector('.roadmap .tag.took')?.textContent === 'took 3 days'`));
await js(`(() => { const sel = document.querySelector('#step-dialog .time select'); sel.value = '2'; sel.dispatchEvent(new Event('change')); return true; })()`);
await sleep(100);
check('a bigger estimate moves the plan, not the finish', await js(`JSON.parse(localStorage.getItem('coach.state')).roadmap.edits[content.roadmap.steps[1].id]?.weeks === 2 && roadmapProgress().slip === 2`));
await js(`(() => { const i = document.querySelector('#step-dialog input.hours'); i.value = '8'; i.dispatchEvent(new Event('input')); return true; })()`);
check('typed hours win over Pomo', await js(`JSON.parse(localStorage.getItem('coach.state')).roadmap.hours[content.roadmap.steps[1].id] === 8 && roadmapSteps()[1].hours === 8`));
await shot('08b-step');
await js(`(() => { const sel = document.querySelector('#step-dialog .time select'); sel.value = '1'; sel.dispatchEvent(new Event('change')); return true; })()`);
await sleep(100);
await js(`[...document.querySelectorAll('#step-dialog .btn')].find((b) => b.textContent === 'Skip').click(); true`);
await sleep(100);
check('skipping a step moves to the next', await js(`roadmapProgress().current.id === content.roadmap.steps[2].id && roadmapProgress().active.length === content.roadmap.steps.length - 1`));
await js(`[...document.querySelectorAll('#step-dialog .btn')].find((b) => b.textContent === 'Unskip').click(); document.querySelector('#step-dialog').close(); true`);
await sleep(100);
await js(`document.querySelector('.suggest').open = true; document.querySelector('.suggestion .link').click(); true`);
await sleep(150);
check('suggested goal added', (await js(`document.querySelectorAll('.goal').length`)) === 1);
await js(`document.querySelector('.goal .milestone input').click(); true`);
await sleep(100);
check('milestone ticked', await js(`Object.values(JSON.parse(localStorage.getItem('coach.state')).goals)[0].milestones[0].done === true`));
check('rhythm and apps render', (await js(`document.querySelectorAll('.rhythm-row').length`)) > 5 && (await js(`document.querySelectorAll('.app-row').length`)) === 14);
await shot('08-plan');

// Drawer: rename a family member and check it reaches the plan.
await click('#open-drawer');
await sleep(250);
await js(`(() => { const i = document.querySelectorAll('#drawer input')[3]; i.value = 'Lakshmi'; i.dispatchEvent(new Event('input')); i.dispatchEvent(new Event('change')); return true; })()`);
await shot('09-drawer');
await click('#close-drawer');
await tab('plan');
await js(`[...document.querySelectorAll('.day-chips button')].find((b) => b.textContent === 'Sun').click(); true`);
await sleep(150);
check('family name used in the plan', await js(`document.querySelector('#view').innerText.includes('with Lakshmi')`));
check('autopilot blocks are quiet rows', (await js(`document.querySelectorAll('.rhythm-row.quiet-row').length`)) === 2);
await js(`[...document.querySelectorAll('.day-chips button')].find((b) => b.textContent === 'Mon').click(); true`);
await tab('today');
check('today shows autopilot blocks as one line', (await js(`document.querySelectorAll('.quiet').length`)) >= 2);
await shot('09b-today-quiet');

// Merge: an older copy of a day must not overwrite the newer one; a new day must arrive.
const merged = await js(`(() => {
    const s = JSON.parse(localStorage.getItem('coach.state'));
    const [k, d] = Object.entries(s.days).find(([, v]) => v.mood === 4 && v.done.length === 1);
    const incoming = { days: { [k]: { ...d, mood: 1, updated: 1 }, '2001-01-01': { done: [], mood: 5, updated: 5 } } };
    return { n: mergeState(incoming), kept: state.days[k].mood, added: state.days['2001-01-01']?.mood };
})()`);
check('merge keeps newer and adds new', merged.n === 1 && merged.kept === 4 && merged.added === 5, JSON.stringify(merged));

// Adjusting the plan: the seeded week never ticks some habit steps, so the coach suggests a change.
await js(`window.confirm = () => true; true`);
await tab('plan');
check('adjust card suggests a change', await js(`[...document.querySelectorAll('.card h3')].some((x) => x.textContent.includes('Adjust to your practice'))`));
await js(`document.querySelector('.rhythm-row .icon-btn').click(); true`);
await sleep(150);
check('block editor opens', await js(`document.querySelector('#block-dialog').open && document.querySelectorAll('#block-dialog .step-edit').length > 0`));
await js(`(() => {
    const dlg = document.querySelector('#block-dialog');
    dlg.querySelector('input[type=text]').value = 'My morning';
    dlg.querySelector('input[type=time]').value = '04:40';
    [...dlg.querySelectorAll('.btn')].find((b) => b.textContent === '+ Add step').click();
    const rows = dlg.querySelectorAll('.step-edit');
    const last = rows[rows.length - 1];
    last.querySelector('input').value = 'Walk around the block';
    const app = last.querySelector('select');
    app.value = app.options[1].value;
    return true;
})()`);
await shot('10-block-editor');
await js(`[...document.querySelectorAll('#block-dialog .btn')].find((b) => b.textContent === 'Save').click(); true`);
await sleep(150);
const saved = await js(`(() => {
    const c = JSON.parse(localStorage.getItem('coach.state')).custom;
    const o = Object.values(c.blocks)[0] ?? {};
    const steps = Object.values(c.addedSteps)[0] ?? [];
    return { title: o.title?.default, start: o.start?.default, step: steps[0]?.text, app: !!steps[0]?.app,
        row: document.querySelector('.rhythm-row strong').textContent };
})()`);
check('block edit saved', saved.title === 'My morning' && saved.start === '04:40' && saved.step === 'Walk around the block' && saved.app && saved.row.startsWith('My morning'), JSON.stringify(saved));
await tab('today');
await js(`document.querySelectorAll('.block-head').forEach((b) => { if (!b.parentElement.classList.contains('open')) b.click(); }); true`);
await sleep(150);
check('edited block shows on Today', await js(`document.querySelector('#view').innerText.includes('Walk around the block') && document.querySelector('#view').innerText.includes('My morning')`));

await tab('plan');
await js(`document.querySelector('.habit-row input[type=checkbox]').click(); true`);
await sleep(100);
await js(`document.querySelectorAll('.habit-row select')[1].value = '3'; document.querySelectorAll('.habit-row select')[1].dispatchEvent(new Event('change')); true`);
await sleep(100);
await shot('11-plan-habits');
await tab('review');
check('turned-off habit leaves progress', (await js(`document.querySelectorAll('.stat-row').length`)) === 9);
check('weekly target shows', await js(`document.querySelector('.stat-row').innerText.includes('3/week')`));
await tab('plan');
await js(`[...document.querySelectorAll('.btn')].find((b) => b.textContent === 'Reset plan').click(); true`);
await sleep(100);
check('reset plan clears changes', await js(`(() => { const c = JSON.parse(localStorage.getItem('coach.state')).custom; return !Object.keys(c.blocks).length && !Object.keys(c.habits).length && !Object.keys(c.addedSteps).length; })()`));

// The public site is locked: only content.enc, opened with the passcode.
const PASS = readFileSync(join(ROOT, '.passcode'), 'utf8').trim();
await send('Page.navigate', { url: START + '?locked' });
check('locked site asks for the passcode', await waitFor(`!document.querySelector('#gate').hidden && document.querySelector('#app').hidden`));
await shot('12-gate');
const submit = (p) => js(`(() => { document.querySelector('#gate-pass').value = ${JSON.stringify(p)}; document.querySelector('#gate').requestSubmit(); return true; })()`);
await submit('not-it');
check('wrong passcode refused', await waitFor(`!document.querySelector('#gate-error').hidden`));
await submit(PASS);
const unlocked = `!!document.querySelector('#view .card') && document.querySelector('#gate').hidden && !document.querySelector('#app').hidden`;
check('right passcode unlocks', await waitFor(unlocked));
check('passcode remembered', await js(`localStorage.getItem('coach.passcode') === ${JSON.stringify(PASS)}`));
await send('Page.reload');
check('remembered passcode skips the gate', await waitFor(unlocked));
await click('#open-drawer');
await sleep(200);
await js(`[...document.querySelectorAll('#drawer .menu-btn')].find((b) => b.textContent.startsWith('🔒')).click(); true`);
check('lock now forgets it', await waitFor(`!document.querySelector('#gate').hidden`) && await js(`!localStorage.getItem('coach.passcode')`));

check('no console errors', problems.length === 0, problems.join(' ; '));
console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed', `· screenshots in ${SHOTS}`);
cleanup();
process.exit(failures ? 1 : 0);
