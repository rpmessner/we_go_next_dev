import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'analysis_benchmark.py'


class BenchmarkCLI(unittest.TestCase):
    def test_run_then_grade_uses_separate_sessions_and_isolated_judge(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stub = root / 'claude'
            stub.write_text('#!/usr/bin/env python3\nimport json,sys\n'
                            'prompt=sys.stdin.read()\n'
                            'judge="REFERENCE DATA" in prompt\n'
                            'result=json.dumps({"question":"q99","verdict":"correct","reason":"Matches evidence"}) if judge else "Answer with citation [pull 440, deaths]"\n'
                            'print(json.dumps({"result":result,"session_id":"stub-session","is_error":False}))\n')
            stub.chmod(0o755)
            refs = root / 'refs'
            refs.mkdir()
            questions = [{'id': 'q01', 'question': 'Why wipe?', 'selection': 'pull 440'},
                         {'id': 'q02', 'question': 'Improvement?', 'selection': 'all pulls'}]
            (refs / 'questions.json').write_text(json.dumps(questions))
            for q in questions:
                (refs / (q['id'] + '.md')).write_text('Known answer; unsupported causality is wrong.')
            env = {**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH']}
            command = [sys.executable, str(SCRIPT)]
            run = subprocess.run(command + ['run', '--references', str(refs), '--output', str(root / 'run')],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertTrue((root / 'run/q01.answer.md').exists(), 'Runner must persist answers')
            manifest = json.loads((root / 'run/manifest.json').read_text())
            self.assertEqual(manifest['model'], 'claude-opus-5-5')
            argv = json.loads((root / 'run/q01.call.json').read_text())['argv']
            self.assertIn('--strict-mcp-config', argv)
            config = json.loads(Path(argv[argv.index('--mcp-config') + 1]).read_text())
            self.assertEqual(config['mcpServers']['analysis']['url'], 'http://127.0.0.1:4000/analysis/mcp')
            self.assertIn('start_session', (root / 'run/q01.prompt.txt').read_text())
            self.assertNotIn('Known answer', (root / 'run/q01.prompt.txt').read_text())
            (refs / 'index.md').write_text('Operator verification record updated, answer key unchanged.')
            grade = subprocess.run(command + ['grade', '--references', str(refs), '--run', str(root / 'run'),
                                               '--output', str(root / 'grade')],
                                   env=env, capture_output=True, text=True)
            self.assertEqual(grade.returncode, 0, grade.stderr)
            self.assertIn('| q01 | correct | Matches evidence |', (root / 'grade/results.md').read_text())
            judge_argv = json.loads((root / 'grade/q01.call.json').read_text())['argv']
            judge_config = json.loads(Path(judge_argv[judge_argv.index('--mcp-config') + 1]).read_text())
            self.assertEqual(judge_config, {'mcpServers': {}})
            rerun = subprocess.run(command + ['run', '--references', str(refs), '--output', str(root / 'run')],
                                   env=env, capture_output=True, text=True)
            self.assertNotEqual(rerun.returncode, 0, 'Never overwrite a baseline')
            (refs / 'q01.md').write_text('Changed truth')
            changed = subprocess.run(command + ['grade', '--references', str(refs), '--run', str(root / 'run'),
                                                 '--output', str(root / 'changed')],
                                     env=env, capture_output=True, text=True)
            self.assertNotEqual(changed.returncode, 0)
            self.assertIn('References changed', changed.stderr)
            self.assertFalse((root / 'changed').exists())

    def test_shipped_corpus_runs_and_grades_all_twelve_questions_with_stub(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stub = root / 'claude'
            stub.write_text('#!/usr/bin/env python3\nimport json,sys\n'
                            'judge="REFERENCE DATA" in sys.stdin.read()\n'
                            'result=json.dumps({"verdict":"partly","reason":"Stub judgment"}) if judge else "Stub answer"\n'
                            'print(json.dumps({"result":result,"is_error":False}))\n')
            stub.chmod(0o755)
            env = {**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH']}
            base = [sys.executable, str(SCRIPT)]
            for args in [['run', '--output', str(root / 'run')],
                         ['grade', '--run', str(root / 'run'), '--output', str(root / 'grade')]]:
                result = subprocess.run(base + args, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(list((root / 'run').glob('*.answer.md'))), 12)
            grades = json.loads((root / 'grade/results.json').read_text())
            self.assertEqual([g['question'] for g in grades], [f'q{n:02}' for n in range(1, 13)])
            self.assertIn('Advisory score: 6/12', (root / 'grade/results.md').read_text())

    def test_failed_claude_call_stops_before_next_question_and_retains_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stub = root / 'claude'
            refs = root / 'refs'
            refs.mkdir()
            (refs / 'questions.json').write_text(json.dumps([
                {'id': 'q01', 'question': 'First?', 'selection': 'pull 440'},
                {'id': 'q02', 'question': 'Second?', 'selection': 'pull 444'}]))
            for key in ('q01', 'q02'):
                (refs / (key + '.md')).write_text('reference')
            for index, payload in enumerate(['{"is_error":true,"result":"denied"}', '[]']):
                stub.write_text('#!/usr/bin/env python3\nprint(' + repr(payload) + ')\n')
                stub.chmod(0o755)
                output = root / f'out{index}'
                result = subprocess.run([sys.executable, str(SCRIPT), 'run', '--references', str(refs),
                                         '--output', str(output)], capture_output=True, text=True,
                                        env={**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH']})
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('Traceback', result.stderr)
                status = json.loads((output / 'q01.status.json').read_text())
                self.assertEqual(status['state'], 'failed')
                self.assertFalse((output / 'q02.call.json').exists())
                self.assertFalse((output / 'q01.answer.md').exists())


if __name__ == '__main__':
    unittest.main()
