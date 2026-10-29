"""Recompute phase-1 evidence; never connects to the app or database.

Input is analysis-reference.sql's read-only snapshot plus the original bronze log.
Output is deterministic JSON, independently diffable from the reviewed references.
"""
import argparse
from collections import Counter, defaultdict
import csv
from datetime import datetime
import json
from pathlib import Path
import re

# The operator's character in the Sept 6 log (Q12), confirmed on we-xf4.8.
OWN_CHARACTER = 'Wispless'


def wall_ms(timestamp):
    wall = re.sub(r'[+-]\d+(?::\d+)?$', '', timestamp)
    delta = datetime.strptime(wall, '%m/%d/%Y %H:%M:%S.%f') - datetime(1970, 1, 1)
    return delta.days * 86400000 + delta.seconds * 1000 + delta.microseconds // 1000


def bronze(snapshot, path):
    events, names, health = [], {}, {}
    types = {'SPELL_CAST_SUCCESS', 'SPELL_AURA_APPLIED', 'SPELL_AURA_REFRESH',
             'SPELL_AURA_REMOVED', 'SPELL_INTERRUPT'}
    with open(path, 'rb') as log:
        for pull in snapshot['pulls']:
            log.seek(pull['start_byte'])
            origin = None
            while log.tell() < pull['end_byte']:
                offset = log.tell()
                raw = log.readline()
                if not raw:
                    raise ValueError('Log ends before gold byte range')
                timestamp, payload = raw.decode('utf-8').rstrip('\r\n').split('  ', 1)
                if origin is None:
                    origin = wall_ms(timestamp)
                event_type = payload.split(',', 1)[0]
                if event_type not in types and not event_type.endswith('_DAMAGE'):
                    continue
                fields = next(csv.reader([payload]))
                if len(fields) < 12:
                    continue
                spell = int(fields[9]) if event_type.startswith(('SPELL_', 'RANGE_')) else 0
                if spell:
                    names[str(spell)] = fields[10]
                ms = wall_ms(timestamp) - origin
                if event_type in types:
                    row = {'pull': pull['id'], 'ms': ms, 'timestamp': timestamp,
                           'byte': offset, 'type': event_type, 'source': fields[1],
                           'target': fields[5], 'spell': spell, 'name': fields[10],
                           'hostile_source': bool(int(fields[3], 0) & 0x40)}
                    if event_type == 'SPELL_INTERRUPT':
                        row['interrupted_spell'] = int(fields[12])
                        row['interrupted_name'] = fields[13]
                    events.append(row)
                advanced = 9 if event_type == 'SWING_DAMAGE' else 12
                if event_type.endswith('_DAMAGE') and len(fields) > advanced + 3:
                    unit = fields[1] if event_type == 'SWING_DAMAGE' else fields[5]
                    name = fields[2] if event_type == 'SWING_DAMAGE' else fields[6]
                    if name == pull['name'] and fields[advanced] == unit:
                        hp, maximum = int(fields[advanced + 2]), int(fields[advanced + 3])
                        if maximum > 0 and 0 <= hp <= maximum:
                            candidate = {'ms': ms, 'timestamp': timestamp, 'byte': offset,
                                         'guid': unit, 'hp': hp, 'max_hp': maximum,
                                         'pct': round(100 * hp / maximum, 3)}
                            old = health.get(pull['id'])
                            if old is None or hp * old['max_hp'] < old['hp'] * maximum:
                                health[pull['id']] = candidate
    return events, names, health


def short_event(event, key=None):
    row = {k: event[k] for k in ('spell', 'ms', 'timestamp', 'byte')}
    if key is not None:
        row = {'key': key, **row}
    return row


def survival(snapshot, events, catalog):
    casts = {spell: action for action in catalog for spell in action['cast_spell_ids']}
    auras = {spell: action for action in catalog for spell in action['aura_spell_ids']}
    by_pull = defaultdict(list)
    for event in events:
        by_pull[event['pull']].append(event)
    rows = []
    for death in snapshot['deaths']:
        active, at_damage, used, consumables, recent = {}, {}, {}, [], []
        damage_ms = max((r['ms_into_fight'] for r in death['recap']), default=None)
        for event in by_pull[death['pull']]:
            if event['ms'] > death['ms']:
                break
            spell = event['spell']
            if event['type'] == 'SPELL_CAST_SUCCESS' and event['source'] == death['guid']:
                action = casts.get(spell)
                if action:
                    item = short_event(event, action['key'])
                    if action['kind'] != 'defensive':
                        consumables.append(item)
                    else:
                        used[action['key']] = item
                    if death['ms'] - event['ms'] <= 10000:
                        recent.append(item)
            if event['target'] == death['guid'] and spell in auras:
                key = (event['source'], spell)
                if event['type'] in ('SPELL_AURA_APPLIED', 'SPELL_AURA_REFRESH'):
                    active[key] = short_event(event, auras[spell]['key'])
                elif event['type'] == 'SPELL_AURA_REMOVED':
                    active.pop(key, None)
                if damage_ms is not None and event['ms'] <= damage_ms:
                    at_damage = dict(active)
        rows.append({'pull': death['pull'], 'guid': death['guid'], 'death_ms': death['ms'],
                     'killing_spell': death['spell'], 'last_defensive_casts': list(used.values()),
                     'recent_10s_casts': recent, 'active': list(active.values()),
                     'last_damage_ms': damage_ms, 'active_at_last_damage': list(at_damage.values()),
                     'consumables': consumables, 'availability': 'unknown'})
    return rows


def evidence(snapshot, events, names, health, catalog):
    pulls = snapshot['pulls']
    deaths, damage, criteria = (snapshot[k] for k in ('deaths', 'damage', 'criteria'))
    players = {(p['pull'], p['guid']): p for p in snapshot['players']}
    ssz = [p for p in pulls if p['name'] == 'Sszorak']
    twin = [p for p in pulls if p['name'] == 'The Twin Fangs']
    chosen = next((p for p in ssz if p['pull_number'] == 5), pulls[0])
    pair = twin[-2:]
    survival_rows = survival(snapshot, events, catalog)
    for row, death in zip(survival_rows, deaths):
        row['name'] = players.get((row['pull'], row['guid']), {}).get('name')
        row['recap_damage_last_10s'] = sum(h['amount'] for h in death['recap'] if
                                           death['ms'] - 10000 <= h['ms_into_fight'] <= death['ms'])

    def named_death(d):
        return {**d, 'name': players.get((d['pull'], d['guid']), {}).get('name'),
                'role': players.get((d['pull'], d['guid']), {}).get('role')}

    def pull_row(p):
        pid = p['id']
        return {'pull': pid, 'boss': p['name'], 'number': p['pull_number'],
                'success': p['success'], 'duration_ms': p['fight_time_ms'],
                'death_events': sum(d['pull'] == pid for d in deaths),
                'failure_rows': [f for f in snapshot['failures'] if f['pull'] == pid],
                'minimum_observed_boss_hp': health.get(pid)}

    def spell_totals(p):
        totals = defaultdict(lambda: {'hits': 0, 'amount': 0})
        for hit in damage:
            if hit['pull'] == p['id'] and hit['spell']:
                totals[hit['spell']]['hits'] += hit['hits']
                totals[hit['spell']]['amount'] += hit['amount']
        return sorted([{'spell': spell, 'name': names.get(str(spell)), **row}
                       for spell, row in totals.items()], key=lambda r: (-r['amount'], r['spell']))

    def scoped_rules(p):
        return [c for c in criteria if c['active'] and c['ruleset_status'] == 'active' and
                c['boss_encounter_id'] in (None, str(p['wow_encounter_id'])) and
                c['difficulty_id'] in (None, p.get('difficulty_id'))]

    selected_deaths = [named_death(d) for d in deaths if d['pull'] == chosen['id']]
    applicable = {p['id']: scoped_rules(p) for p in pulls}
    avoided = []
    for hit in damage:
        matches = [c for c in applicable[hit['pull']] if
                   c['spell'] == hit['spell'] and c['mechanic_type'] == 'avoidable']
        if matches and hit['pull'] in {p['id'] for p in twin}:
            avoided.append({**hit, 'name': players.get((hit['pull'], hit['guid']), {}).get('name')})
    unruled = defaultdict(lambda: {'amount': 0, 'hits': 0, 'players': set(), 'pulls': set()})
    for hit in damage:
        if hit['spell'] and not any(c['spell'] == hit['spell'] for c in applicable[hit['pull']]):
            row = unruled[hit['spell']]
            row['amount'] += hit['amount']
            row['hits'] += hit['hits']
            row['players'].add(hit['guid'])
            row['pulls'].add(hit['pull'])
    ranking = [{'spell': spell, 'name': names.get(str(spell)), **row,
                'players': sorted(row['players']), 'pulls': sorted(row['pulls'])}
               for spell, row in unruled.items() if len(row['pulls']) > 1]
    ranking.sort(key=lambda r: (-r['amount'], r['spell']))
    for row in ranking:
        row['player_count'] = len(row['players'])
        row['pull_count'] = len(row['pulls'])
    notes = []
    for guid in sorted({p['guid'] for p in snapshot['players']}):
        personal = [d for d in deaths if d['guid'] == guid]
        fatal = Counter(d['spell'] for d in personal if d['spell'])
        name = next(p['name'] for p in snapshot['players'] if p['guid'] == guid)
        if fatal:
            spell, count = sorted(fatal.items(), key=lambda x: (-x[1], x[0]))[0]
            relevant = [d for d in personal if d['spell'] == spell]
            notes.append({'guid': guid, 'name': name, 'death_events': len(personal),
                          'focus_spell': spell, 'spell_name': names.get(str(spell)),
                          'fatal_count': count,
                          'evidence': [{'pull': d['pull'], 'ms': d['ms']} for d in relevant],
                          'note': 'Review the damage window for this repeated killing blow; '
                                  'agree a positioning or mitigation plan with the raid lead. '
                                  'This is an investigation priority, not proof of avoidability.'})
        else:
            notes.append({'guid': guid, 'name': name, 'death_events': len(personal),
                          'note': 'No repeated named killing blow supports a specific correction; '
                                  'keep the survival plan and review mechanics with the raid lead.'})
    trends = []
    for note in notes:
        if 'focus_spell' not in note:
            continue
        for boss in sorted({p['name'] for p in pulls}):
            series = []
            for p in pulls:
                key = (p['id'], note['guid'])
                if p['name'] != boss or key not in players or p['fight_time_ms'] < 60000:
                    continue
                hits = sum(h['hits'] for h in damage if h['pull'] == p['id'] and
                           h['guid'] == note['guid'] and h['spell'] == note['focus_spell'])
                series.append({'pull': p['id'], 'hits': hits, 'duration_ms': p['fight_time_ms'],
                               'killing_blow_deaths': sum(d['pull'] == p['id'] and
                                                         d['guid'] == note['guid'] and
                                                         d['spell'] == note['focus_spell'] for d in deaths)})
            if len(series) >= 2 and any(r['hits'] for r in series):
                trends.append({'guid': note['guid'], 'name': note['name'], 'boss': boss,
                               'spell': note['focus_spell'], 'series': series,
                               'raw_hits_fell_first_to_last': series[-1]['hits'] < series[0]['hits']})
    npc_success = [e for e in events if e['pull'] in {p['id'] for p in ssz} and
                   e['type'] == 'SPELL_CAST_SUCCESS' and e['hostile_source'] and
                   e['source'].startswith('Creature-')]
    interrupts = [e for e in events if e['pull'] in {p['id'] for p in ssz} and
                  e['type'] == 'SPELL_INTERRUPT']
    interrupted_ids = {e['interrupted_spell'] for e in interrupts}
    completed = Counter((e['pull'], e['spell'], e['name']) for e in npc_success)
    pair_casts = [e for e in events if e['pull'] in {p['id'] for p in pair} and
                  e['type'] == 'SPELL_CAST_SUCCESS' and e['source'].startswith('Player-') and
                  e['spell'] in {s for a in catalog for s in a['cast_spell_ids']}]
    survival_counts = Counter((e['pull'], e['spell'], e['name']) for e in pair_casts)
    own_guids = {p['guid'] for p in snapshot['players'] if p['name'].split('-')[0] == OWN_CHARACTER}
    own_casts = [e for e in events if e['pull'] == chosen['id'] and
                 e['source'] in own_guids and e['type'] == 'SPELL_CAST_SUCCESS']
    gaps = [{'from_ms': a['ms'], 'to_ms': b['ms'], 'gap_ms': b['ms'] - a['ms'],
             'from_spell': a['spell'], 'to_spell': b['spell'],
             'from_byte': a['byte'], 'to_byte': b['byte']}
            for a, b in zip(own_casts, own_casts[1:]) if b['ms'] - a['ms'] >= 5000]
    return {
        'q01': {'pull': pull_row(chosen), 'death_chain': selected_deaths[:6]},
        'q02': {'pulls': [pull_row(p) for p in ssz],
                'applicable_rules': {str(p['id']): applicable[p['id']] for p in ssz},
                'observed_damage': {str(p['id']): spell_totals(p) for p in ssz}},
        'q03': {'pulls': [pull_row(p) for p in pair],
                'deaths': [named_death(d) for d in deaths if d['pull'] in {p['id'] for p in pair}],
                'observed_damage': {str(p['id']): spell_totals(p) for p in pair},
                'survival_casts': pair_casts,
                'survival_cast_counts': [{'pull': p, 'spell': s, 'name': n, 'count': count}
                                         for (p, s, n), count in sorted(survival_counts.items())],
                'survival': [r for r in survival_rows if r['pull'] in {p['id'] for p in pair}]},
        'q04': {'pull': pull_row(chosen), 'first_deaths': selected_deaths[:1],
                'applicable_rules': applicable[chosen['id']]},
        'q05': {'deaths': survival_rows,
                'summary': {'death_events': len(survival_rows),
                            'with_recent_cast': sum(bool(r['recent_10s_casts']) for r in survival_rows),
                            'with_prior_consumable': sum(bool(r['consumables']) for r in survival_rows),
                            'with_open_aura_at_last_damage': sum(bool(r['active_at_last_damage']) for r in survival_rows)}},
        'q06': {'deaths': [{**r, 'recap': next(d['recap'] for d in deaths if
                                           (d['pull'], d['guid'], d['ms']) ==
                                           (r['pull'], r['guid'], r['death_ms']))}
                           for r in survival_rows if r['active'] or r['active_at_last_damage'] or r['recent_10s_casts']]},
        'q07': {'pulls': [p['id'] for p in twin], 'avoidable_hits': avoided,
                'applicable_rules': {str(p['id']): applicable[p['id']] for p in twin}},
        'q08': {'completed_hostile_casts': npc_success,
                'completed_counts': [{'pull': p, 'spell': s, 'name': n, 'count': count}
                                     for (p, s, n), count in sorted(completed.items())],
                'completed_with_interrupt_evidence': [e for e in npc_success if e['spell'] in interrupted_ids],
                'interrupts': interrupts},
        'q09': {'ranking': ranking[:15]},
        'q10': {'notes': notes},
        'q11': {'observed_trends': trends, 'authored_failure_rows': snapshot['failures']},
        'q12': {'pull': pull_row(chosen), 'guids': sorted(own_guids),
                'roster': sorted({p['name'] for p in snapshot['players']}),
                'deaths': [d for d in selected_deaths if d['guid'] in own_guids],
                'cast_counts': dict(sorted(Counter(e['spell'] for e in own_casts).items())),
                'cast_gaps_at_least_5s': gaps,
                'survival': [r for r in survival_rows if r['pull'] == chosen['id'] and r['guid'] in own_guids]}
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('snapshot', 'catalog', 'log', 'output'):
        parser.add_argument('--' + key, required=True, type=Path)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    catalog = json.loads(args.catalog.read_text())
    events, names, health = bronze(snapshot, args.log)
    results = evidence(snapshot, events, names, health, catalog)
    args.output.mkdir(parents=True, exist_ok=False)
    for question, data in results.items():
        (args.output / (question + '.json')).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
    (args.output / 'spell-names.json').write_text(json.dumps(names, indent=2, sort_keys=True) + '\n')
    print('Recomputed 12 question evidence files')


if __name__ == '__main__':
    main()
