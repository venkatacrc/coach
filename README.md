# Coach

A personal coach for a hands-on engineer growing into leadership. It turns the day into a plan,
links each block to the right practice app, teaches management, Staff+ technical leadership,
career growth, and the skills to run your own gig, and keeps family, health and sādhana at the
centre so the progress comes with happiness.

The same coach runs in two apps that read one content file:

- **Mac:** a SwiftUI app (`app/`), built into `build/Coach.app`, with a menu bar widget.
- **Phone:** an installable web app (`web/`) that works offline, published at
  <https://venkatacrc.github.io/coach/> behind a passcode.

## Private by default

This repo is public, so the personal content (the daily plan, family roles, lessons and messages)
is never committed in plain text:

- `content.vault` holds `content/` encrypted, and `web/content.enc` holds the built content the
  phone app downloads. Both use AES-256-GCM with a key derived from the passcode
  (PBKDF2-SHA256, 250,000 iterations).
- `content/`, `web/content.json`, the app's bundled copy and `.passcode` are git-ignored.
- The phone app asks for the passcode before it shows anything. **Remember on this device** keeps
  it in the browser's storage; ☰ → **Lock now** forgets it.

The passcode lives in `.passcode` (one line, git-ignored), or in `$COACH_PASSCODE`. After a fresh
clone, write the passcode to `.passcode` and run `node tools/lock.mjs open` to get `content/` back
(`scripts/build_app.sh` does this for you).

To change the passcode, write the new one to `.passcode` and run `./scripts/publish_web.sh`, then
commit `content.vault` and `web/content.enc`. Each device asks for the new passcode the next time.

## What's inside

| Part | What it does |
| --- | --- |
| **Today** | The day's time blocks with steps to tick. Each step links to the app it uses or to the next lesson in a track. Top 3 for the day, the coach's messages, and a thought for the day. |
| **Grow** | 75 lessons in five tracks: *Lead people*, *Lead technically*, *Grow your career*, *Build your own gig* and *Live well*. Each has one idea, one practice for the week, one question and something to read, plus your notes. |
| **Review** | The evening review, the weekly review, and progress: habits over 28 days with streaks, plus mood and energy. |
| **Plan** | Quarterly goals with milestones, suggestions to adjust the plan, the weekly rhythm, habit settings and all your apps. |

## Making it yours

The plan in `content/` is a starting point. Change it to fit how you actually practise, on the
phone or the Mac, without touching the content files:

- **Adjust a block** (✎ in Plan → Weekly rhythm, or "Adjust this block" on Today): change its
  title, times and area, or skip it. Change a step's text, app or habit, skip a step, or add your
  own steps. On weekdays you choose whether the change applies to every workday or only that
  weekday.
- **Add a block** of your own to any day.
- **Habits** (Plan): turn off a habit you aren't practising now, or give it a weekly target
  (for example 3× a week), so fewer days still count as 100%.
- **Adjust to your practice**: the coach looks at the last two weeks. A habit step (or one of
  your own) done on 20% of days or fewer gets an **Adjust** button. A habit at 90% or more for
  three weeks is ready for a bigger step.
- **Reset plan** (Plan → Habits) undoes all of it.

Your changes travel in backups with the rest of your progress.

## Build and run

Requires macOS 14 or later, the Xcode Command Line Tools and Node 18 or later.

```sh
./scripts/build_app.sh
open build/Coach.app
```

For development, `swift run --package-path app --build-system native`.

On the Mac: **⌘1–⌘4** switch sections, **⌘[** and **⌘]** move between days, **⌘T** goes back to
today. The menu bar compass shows the current block and what's next. **Plan → Reminders** turns
on a notification at the start of each block (built app only). State is saved in
`~/Library/Application Support/Coach/state.json`.

## Phone

Open <https://venkatacrc.github.io/coach/> in Chrome, then ⋮ → **Install app** (Safari: Share →
**Add to Home Screen**). It works offline once opened.

GitHub Pages serves the repo from the `main` branch; the root `index.html` redirects to `web/`.
To publish a content change:

```sh
./scripts/publish_web.sh          # build, validate and seal
git add content.vault web/content.enc && git commit -m "Update content" && git push
```

To try it locally (no passcode; add `?locked` to test the lock screen):

```sh
python3 -m http.server -d web 8080
```

## Sync between phone and Mac

Each device keeps its own progress. To move it, export a backup (phone: ☰ → **Export backup**;
Mac: **File → Export Backup…**, ⇧⌘E) and import it on the other device (**Import backup** /
**File → Import Backup…**, ⌘O). Importing merges per day, lesson, week and goal, and the newer
entry wins, so you can import in both directions without losing anything.

## Changing the content

Everything the coach says lives in `content/` (after `node tools/lock.mjs open`):

```
content/rhythm.json     areas, habits, family roles and the weekday / Saturday / Sunday plans
content/apps.json       your apps, with web links and Mac .app paths
content/tracks/*.json   lessons: lead, staff, career, gig, life
content/coach.json      greetings and the coach's messages
content/wisdom.json     the thought for the day
content/goals.json      suggested quarterly goals
```

A step's `text`, `app` and `track` can be one value or a map by weekday, and family placeholders
are replaced with the names set on the device. A step with a `habit` counts toward that habit.
After editing, run:

```sh
./scripts/publish_web.sh          # validates, writes content.json, seals content.vault and web/content.enc
node tools/smoke_web.mjs          # headless Chrome at phone size; screenshots in build/shots/
./scripts/build_app.sh            # rebuild the Mac app
```

## Layout

```
app/                      Swift package (SwiftUI app and menu bar widget)
web/                      phone and web app (plain HTML, CSS and JavaScript)
content.vault             content/ sealed with the passcode
web/content.enc           the built content, sealed, for the phone app
tools/lock.mjs            seal and open the vault
tools/build_content.py    validates content/ and writes content.json for both apps
tools/smoke_web.mjs       web app smoke test (including the lock and plan editing)
scripts/publish_web.sh    build and seal before pushing
scripts/build_app.sh      builds build/Coach.app
scripts/make_icon.swift   draws the compass icon (Mac .icns and web PNGs)
```
