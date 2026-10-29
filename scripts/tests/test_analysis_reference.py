import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'analysis_reference.py'


class ReferenceCLI(unittest.TestCase):
    def test_bronze_survival_is_target_scoped_and_removal_closes_window(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lines = [
                '9/6/2026 11:00:00.000-4  ENCOUNTER_START,3420,"Sszorak",15,2,3004\n',
                '9/6/2026 11:00:01.000-4  SPELL_CAST_SUCCESS,Player-A,"A",0,0,Player-A,"A",0,0,104773,"Unending Resolve",32\n',
                '9/6/2026 11:00:01.001-4  SPELL_AURA_APPLIED,Player-A,"A",0,0,Player-A,"A",0,0,104773,"Unending Resolve",32,BUFF\n',
                '9/6/2026 11:00:02.000-4  SPELL_CAST_SUCCESS,Player-B,"B",0,0,Player-B,"B",0,0,6262,"Healthstone",32\n',
                '9/6/2026 11:00:03.000-4  SPELL_AURA_REMOVED,Player-A,"A",0,0,Player-A,"A",0,0,104773,"Unending Resolve",32,BUFF\n',
            ]
            log = ''.join(lines).encode()
            (root / 'log').write_bytes(log)
            snapshot = {
                'pulls': [{'id': 1, 'name': 'Sszorak', 'pull_number': 1, 'start_byte': 0,
                           'end_byte': len(log), 'success': False, 'fight_time_ms': 5000,
                           'wow_encounter_id': '3420'}],
                'players': [{'pull': 1, 'guid': 'Player-A', 'name': 'A', 'role': 'dps'},
                            {'pull': 1, 'guid': 'Player-B', 'name': 'B', 'role': 'dps'}],
                'deaths': [{'pull': 1, 'guid': 'Player-A', 'ms': 2500, 'spell': 9, 'recap': []},
                           {'pull': 1, 'guid': 'Player-A', 'ms': 4000, 'spell': 9,
                            'recap': [{'ms_into_fight': 2000, 'spell_id': 9, 'amount': 500}]}],
                'damage': [], 'failures': [], 'criteria': [
                    {'spell': 9, 'active': True, 'boss_encounter_id': None,
                     'difficulty_id': None, 'mechanic_type': 'avoidable',
                     'ruleset_status': 'archived'}],
            }
            catalog = [{'key': 'resolve', 'name': 'Unending Resolve', 'kind': 'defensive',
                        'cast_spell_ids': [104773], 'aura_spell_ids': [104773]}]
            (root / 'snapshot.json').write_text(json.dumps(snapshot))
            (root / 'catalog.json').write_text(json.dumps(catalog))
            result = subprocess.run([sys.executable, str(SCRIPT), '--snapshot', str(root / 'snapshot.json'),
                                     '--catalog', str(root / 'catalog.json'), '--log', str(root / 'log'),
                                     '--output', str(root / 'out')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((root / 'out/q05.json').exists(), 'CLI must emit per-death evidence')
            rows = json.loads((root / 'out/q05.json').read_text())['deaths']
            self.assertEqual(rows[0]['active'], [{'key': 'resolve', 'spell': 104773, 'ms': 1001,
                                                  'timestamp': '9/6/2026 11:00:01.001-4',
                                                  'byte': len(lines[0].encode()) + len(lines[1].encode())}])
            self.assertEqual(rows[1]['active'], [])
            self.assertEqual([r['spell'] for r in rows[1].get('active_at_last_damage', [])], [104773])
            self.assertEqual(rows[0]['consumables'], [])
            first_death = json.loads((root / 'out/q04.json').read_text())
            self.assertEqual(first_death['applicable_rules'], [], 'Archived rulesets must not label a death avoidable')
            self.assertEqual(len(list((root / 'out').glob('q*.json'))), 12)

    def test_only_hostile_creatures_are_counted_as_enemy_completed_casts(self):
        spec = importlib.util.spec_from_file_location('reference', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'log'
            log.write_text(
                '9/6/2026 11:00:00.000-4  ENCOUNTER_START,3420,"Sszorak",15,2,3004\n'
                '9/6/2026 11:00:01.000-4  SPELL_CAST_SUCCESS,Creature-Pet,"Pet",0x1114,0,Creature-Boss,"Sszorak",0xa48,0,104318,"Fel Firebolt",32\n'
                '9/6/2026 11:00:02.000-4  SPELL_CAST_SUCCESS,Creature-Boss,"Sszorak",0xa48,0,Player-A,"A",0x514,0,1277101,"Ravage",8\n')
            snapshot = {'pulls': [{'id': 1, 'name': 'Sszorak', 'start_byte': 0, 'end_byte': log.stat().st_size}]}
            events, _, _ = module.bronze(snapshot, log)
            self.assertEqual([e['source'] for e in events if e.get('hostile_source', False)], ['Creature-Boss'])


if __name__ == '__main__':
    unittest.main()
