#!/usr/bin/env python3
import json, math, os, time, hashlib
from datetime import datetime, timezone

INTENT = os.environ.get("INTENT","engineering").strip().lower()
TYPE   = os.environ.get("TYPE","generic").strip().lower()

# deterministic emoji tiles
EMOJI_ID    = "🧱🧱🧱"
EMOJI_VALUE = "🧱🧱🧱"

# Intent → color + type emoji
INTENT_MAP = {
  "engineering":   ("🟩","🧱🧱🟩"),
  "ceo":           ("🟧","🧱🧱🟧"),
  "input":         ("🟦","🧱🧱🟦"),
  "routes":        ("🟥","🧱🧱🟥"),
  "assimilation":  ("🟪","🧱🧱🟪"),
  "extract":       ("🟨","🧱🧱🟨"),
  "investigative": ("🩷","🧱🧱🩷"),
}

COLOR, TYPE_EMOJI = INTENT_MAP.get(INTENT, ("🟦","🧱🧱🟦"))

def sha256(s: str) -> str:
  return hashlib.sha256(s.encode("utf-8", errors="ignore")).hexdigest()

def stable_score(metrics: dict) -> int:
  """
  Bank-style deterministic scoring (no time inputs):
  linear equation with fixed weights.
  """
  files = int(metrics.get("files",0))
  lines = int(metrics.get("lines",0))
  links = int(metrics.get("links",0))
  refs  = int(metrics.get("refs",0))
  # Linear equation (fixed weights)
  # Score = 2*files + (lines/40) + 6*links + 3*refs
  return int(2*files + (lines//40) + 6*links + 3*refs)

def choose_value_emoji(score: int) -> str:
  """
  Deterministic value “brick” ladder:
  higher score → denser value token.
  """
  if score >= 800: return "🧱🧱🧱"
  if score >= 400: return "🧱🧱"
  if score >= 200: return "🧱"
  if score >= 80:  return "🪙"
  return "•"

def build_block(repo_signals: list[dict]) -> dict:
  # aggregate deterministically
  total_files = sum(x["files"] for x in repo_signals)
  total_lines = sum(x["lines"] for x in repo_signals)
  total_links = sum(x["links"] for x in repo_signals)
  total_refs  = sum(x["refs"]  for x in repo_signals)

  metrics = dict(files=total_files, lines=total_lines, links=total_links, refs=total_refs)
  score = stable_score(metrics)

  # “routes” intent boosts on breadth (more repos touched)
  if INTENT == "routes":
    score += len(repo_signals) * 5

  # “investigative” boosts on link density
  if INTENT == "investigative":
    score += total_links * 2

  value_emoji = choose_value_emoji(score)

  block = {
    "type": TYPE,
    "intent": INTENT,
    "color": COLOR,
    "token": {
      "id": EMOJI_ID,
      "value": value_emoji,
      "type": TYPE_EMOJI,
      "time": datetime.now(timezone.utc).isoformat().replace("+00:00","Z"),
    },
    "metrics": metrics,
    "score": score,
    "repo_signals": repo_signals,
  }
  # proof hash excludes time (bank-grade)
  proof_payload = json.dumps({k:block[k] for k in block if k != "token"}, sort_keys=True)
  block["proof_sha256"] = sha256(proof_payload)
  return block

if __name__ == "__main__":
  # stdin optional future; for now this file is imported by miner.sh
  pass
