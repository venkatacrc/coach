#!/usr/bin/env python3
"""Validates content/ and writes the merged content.json that both apps read:
web/content.json and app/Sources/Coach/Resources/content.json.

Usage: python3 tools/build_content.py
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / 'content'
TRACK_ORDER = ['lead', 'staff', 'career', 'gig', 'life']
WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
OUTPUTS = [ROOT / 'web' / 'content.json', ROOT / 'app' / 'Sources' / 'Coach' / 'Resources' / 'content.json']

errors = []


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def minutes(hhmm):
    if not re.fullmatch(r'\d\d:\d\d', hhmm or ''):
        return None
    h, m = map(int, hhmm.split(':'))
    return h * 60 + m


def by_day_values(value):
    """A step field is either a plain value or a {weekday: value} map."""
    if isinstance(value, dict):
        for key in value:
            if key not in WEEKDAYS and key != 'default':
                errors.append(f'unknown weekday key {key!r} in {value}')
        return list(value.values())
    return [value]


def check(rhythm, apps, tracks, coach, goals):
    app_ids = {a['id'] for a in apps['apps']}
    category_ids = {c['id'] for c in apps['categories']}
    for a in apps['apps']:
        if a['category'] not in category_ids:
            errors.append(f"app {a['id']}: unknown category {a['category']}")
    area_ids = {a['id'] for a in rhythm['areas']}
    habit_ids = {h['id'] for h in rhythm['habits']}
    for h in rhythm['habits']:
        if h['area'] not in area_ids:
            errors.append(f"habit {h['id']}: unknown area {h['area']}")
    track_ids = {t['id'] for t in tracks}
    family_ids = {f['id'] for f in rhythm['family']}

    for day, template in rhythm['days'].items():
        if day not in WEEKDAYS:
            errors.append(f'days: unknown weekday {day}')
        if template not in rhythm['templates']:
            errors.append(f'days.{day}: unknown template {template}')

    for tid, template in rhythm['templates'].items():
        last_end = -1
        seen = set()
        for block in template['blocks']:
            where = f"{tid}/{block['id']}"
            if block['id'] in seen:
                errors.append(f'{where}: duplicate block id')
            seen.add(block['id'])
            start, end = minutes(block['start']), minutes(block['end'])
            if start is None or end is None or end <= start:
                errors.append(f'{where}: bad times {block["start"]}–{block["end"]}')
            elif start < last_end:
                errors.append(f'{where}: overlaps the previous block')
            else:
                last_end = end
            if block['area'] not in area_ids:
                errors.append(f"{where}: unknown area {block['area']}")
            step_ids = set()
            for step in block['steps']:
                sw = f"{where}/{step['id']}"
                if step['id'] in step_ids:
                    errors.append(f'{sw}: duplicate step id')
                step_ids.add(step['id'])
                for text in by_day_values(step['text']):
                    for name in re.findall(r'\{(\w+)\}', text):
                        if name not in family_ids:
                            errors.append(f'{sw}: unknown placeholder {{{name}}}')
                for app in by_day_values(step.get('app')):
                    if app is not None and app not in app_ids:
                        errors.append(f'{sw}: unknown app {app}')
                for track in by_day_values(step.get('track')) + [step.get('practice')]:
                    if track is not None and track not in track_ids:
                        errors.append(f'{sw}: unknown track {track}')
                if step.get('habit') and step['habit'] not in habit_ids:
                    errors.append(f"{sw}: unknown habit {step['habit']}")
                if step.get('action') not in (None, 'review', 'week'):
                    errors.append(f"{sw}: unknown action {step['action']}")

    lesson_ids = set()
    for track in tracks:
        if track['area'] not in area_ids:
            errors.append(f"track {track['id']}: unknown area {track['area']}")
        for lesson in track['lessons']:
            if lesson['id'] in lesson_ids:
                errors.append(f"duplicate lesson id {lesson['id']}")
            lesson_ids.add(lesson['id'])
            for key in ('title', 'idea', 'practice', 'ask'):
                if not lesson.get(key):
                    errors.append(f"{lesson['id']}: missing {key}")

    rules = {m['rule'] for m in coach['messages']}
    for rule in ('welcome', 'sleep', 'mood', 'energy', 'build', 'family', 'gig', 'lead', 'reflect', 'sadhana',
                 'adjust', 'levelup', 'streak', 'strong', 'weekly'):
        if rule not in rules:
            errors.append(f'coach.json: no message for rule {rule}')

    goal_ids = set()
    for g in goals:
        if g['id'] in goal_ids:
            errors.append(f"duplicate goal id {g['id']}")
        goal_ids.add(g['id'])
        if g['area'] not in area_ids:
            errors.append(f"goal {g['id']}: unknown area {g['area']}")


def main():
    rhythm = load(CONTENT / 'rhythm.json')
    apps = load(CONTENT / 'apps.json')
    tracks = [load(CONTENT / 'tracks' / f'{t}.json') for t in TRACK_ORDER]
    wisdom = load(CONTENT / 'wisdom.json')
    coach = load(CONTENT / 'coach.json')
    goals = load(CONTENT / 'goals.json')

    check(rhythm, apps, tracks, coach, goals)
    if errors:
        print('\n'.join(f'error: {e}' for e in errors), file=sys.stderr)
        sys.exit(1)

    merged = {
        'rhythm': rhythm,
        'categories': apps['categories'],
        'apps': apps['apps'],
        'tracks': tracks,
        'wisdom': wisdom,
        'coach': coach,
        'goals': goals,
    }
    body = json.dumps(merged, ensure_ascii=False, sort_keys=True)
    merged['version'] = hashlib.sha1(body.encode('utf-8')).hexdigest()[:10]
    text = json.dumps(merged, ensure_ascii=False, separators=(',', ':'))
    for out in OUTPUTS:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding='utf-8')

    lessons = sum(len(t['lessons']) for t in tracks)
    blocks = sum(len(t['blocks']) for t in rhythm['templates'].values())
    print(f"content {merged['version']}: {len(rhythm['templates'])} day templates, {blocks} blocks, "
          f"{len(tracks)} tracks, {lessons} lessons, {len(apps['apps'])} apps, {len(wisdom)} sayings, {len(goals)} goals")


if __name__ == '__main__':
    main()
