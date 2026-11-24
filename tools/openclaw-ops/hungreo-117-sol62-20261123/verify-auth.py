import json
from pathlib import Path
import sys

raw = Path(sys.argv[1]).read_text()
indices = [i for i, character in enumerate(raw) if character in "{["]
for index in indices:
    try:
        value, _ = json.JSONDecoder().raw_decode(raw[index:])
        break
    except json.JSONDecodeError:
        continue
else:
    raise RuntimeError("Missing JSON auth profile list")

profiles = value.get("profiles") if isinstance(value, dict) else value
if isinstance(profiles, dict):
    profiles = [dict(profile, profileId=key) for key, profile in profiles.items() if isinstance(profile, dict)]
if not isinstance(profiles, list):
    raise RuntimeError("Unexpected auth profile list")

modes = set()
for p in profiles:
    if not isinstance(p, dict):
        continue
    ident = p.get("profileId", p.get("id", ""))
    provider = p.get("provider") or ident.split(":", 1)[0]
    if provider in ("openai", "openai-codex"):
        modes.add(p.get("type", p.get("mode")))
if not modes or not modes <= {"oauth", "OAuth", "chatgpt", "ChatGPT"}:
    raise RuntimeError("OpenAI auth profiles do not establish an OAuth-only route")
print("openai_auth_profiles=oauth_only")
