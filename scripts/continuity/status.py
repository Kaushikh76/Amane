from datetime import datetime
from zoneinfo import ZoneInfo
from pathlib import Path
import subprocess,sys
phase,state,note=sys.argv[1:4]
proof=sys.argv[4] if len(sys.argv)>4 else "LOCAL_UNIT"
sha=subprocess.check_output(['git','rev-parse','--short','HEAD'],text=True).strip()
stamp=datetime.now(ZoneInfo('Asia/Kolkata')).strftime('%Y-%m-%d %H:%M')
line=f'{stamp} · codex · {phase} · {state} · {sha} · {proof} · {note}\n'
with Path('/Users/kaushikh/Synq/v4-coordination/STATUS.md').open('a') as f:f.write(line)
with Path('reports/STATUS.md').open('a') as f:f.write(line)
