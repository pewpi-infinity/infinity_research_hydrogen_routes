#!/data/data/com.termux/files/usr/bin/bash
set -e

INTERVAL=120
LEDGER="LEDGER.md"
STATE=".state_proof"
LOG="miner.log"

export TYPE="hydrogen"
export INTENT="routes"

echo "[∞] Intent miner online: $TYPE ($INTENT)" | tee -a "$LOG"

while true; do
  echo "[∞] Scan start" | tee -a "$LOG"

  # collect repo signals (deterministic)
  python3 - <<'PY' > .signals.json
import os, json, subprocess, re, hashlib
from pathlib import Path

HOMEBASE = Path(os.path.expanduser("~/infinity-treasury"))
SELF = Path.cwd().name

def sh(cmd):
  return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)

signals = []
for p in sorted(HOMEBASE.iterdir()):
  if not p.is_dir(): continue
  if p.name == SELF: continue
  if not (p/".git").exists(): continue

  # metrics
  files = int(sh(f"find '{p}' -type f \\( -name '*.md' -o -name '*.py' -o -name '*.sh' \\) | wc -l").strip() or "0")
  lines = int(sh(f"find '{p}' -type f \\( -name '*.md' -o -name '*.py' -o -name '*.sh' \\) -exec wc -l {{}} \\; | awk '{{s+=$1}} END {{print s+0}}'").strip() or "0")
  links = int(sh(f"grep -RhoE \"https?://[^ )\\\"]+\" '{p}' | wc -l").strip() or "0")
  refs  = int(sh(f"grep -RhoE \"(import |require\\(|from )\" '{p}' | wc -l").strip() or "0")

  # content hash (deterministic)
  h = sh(f"find '{p}' -type f \\( -name '*.md' -o -name '*.py' -o -name '*.sh' \\) -exec sha256sum {{}} \\; | sha256sum | awk '{{print $1}}'").strip()

  signals.append({"repo": p.name, "files": files, "lines": lines, "links": links, "refs": refs, "hash": h})

print(json.dumps(signals, indent=2, sort_keys=True))
PY

  # build block + proof (proof excludes time)
  python3 - <<'PY' > .block.json
import os, json
from intent_logic import build_block

signals = json.load(open(".signals.json","r",encoding="utf-8"))
block = build_block(signals)
json.dump(block, open(".block.json","w",encoding="utf-8"), indent=2, sort_keys=True)
print(block["proof_sha256"])
PY > .proof.txt

  PROOF="$(cat .proof.txt | tail -n 1 | tr -d '\n')"
  OLD=""
  [ -f "$STATE" ] && OLD="$(cat "$STATE" | tr -d '\n')"

  if [ "$PROOF" != "$OLD" ]; then
    echo "[∞] New meaningful change → mint block" | tee -a "$LOG"
    echo "$PROOF" > "$STATE"

    # append a clean human block
    python3 - <<'PY' >> "$LEDGER"
import json
b=json.load(open(".block.json","r",encoding="utf-8"))
t=b["token"]
print()
print(f"## Block {t['time']}")
print(f"- Intent: {b['intent']} {b['color']}")
print(f"- Token ID: {t['id']}")
print(f"- Token Value: {t['value']}")
print(f"- Token Type: {t['type']}")
print(f"- Proof SHA256: {b['proof_sha256']}")
print()
print("### Repo Signals")
for s in b["repo_signals"]:
  print(f"- {s['repo']} | files:{s['files']} | links:{s['links']} | refs:{s['refs']} | hash:{s['hash']}")
print()
print("### Score")
print(f"- score: {b['score']}")
PY

    git add "$LEDGER" "$STATE" miner.sh intent_logic.py .block.json .signals.json
    git commit -m "∞ $TYPE:$INTENT block"
    git push origin main
  else
    echo "[∞] No meaningful change" | tee -a "$LOG"
  fi

  sleep "$INTERVAL"
done
