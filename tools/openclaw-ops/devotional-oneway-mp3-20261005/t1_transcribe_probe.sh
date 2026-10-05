#!/bin/bash
# T1 — đo khả thi: tải MP3 tập 05/10 từ API Oneway, chép lời bằng faster-whisper small int8 (ưu tiên thấp).
# Chỉ ghi vào /tmp/devotional-probe-20261005; không gửi, không đụng workspace/cron/gateway.
set -euo pipefail
D=/tmp/devotional-probe-20261005
mkdir -p "$D"; cd "$D"
URL=$(python3 -c '
import json,urllib.request
d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.oneway.vn/v1/radio/radio?perPage=8",headers={"User-Agent":"Mozilla/5.0"}),timeout=20))
print([x["link"] for x in d["data"]["docs"] if "05/10" in x["title"]][0])')
echo "URL=$URL"
curl -fsSL -A "Mozilla/5.0" --max-time 120 --max-filesize 62914560 -o ep.mp3 "$URL"
ls -l ep.mp3
echo "DURATION_S=$(ffprobe -v error -show_entries format=duration -of csv=p=0 ep.mp3)"
cat > tr.py <<'PY'
import sys, time
from faster_whisper import WhisperModel
t = time.time()
m = WhisperModel("/home/hung/.openclaw-voice/models/faster-whisper-small", device="cpu", compute_type="int8",
                 cpu_threads=1, num_workers=1, local_files_only=True)
segs, info = m.transcribe(sys.argv[1], language="vi", beam_size=1, vad_filter=True, temperature=0.0)
text = " ".join(s.text.strip() for s in segs)
open("transcript.txt", "w", encoding="utf-8").write(text)
print(f"TRANSCRIBE_OK chars={len(text)} seconds={time.time()-t:.0f} lang={info.language} dur={info.duration:.0f}")
PY
/usr/bin/time -v nice -n 19 timeout 1200 /home/hung/.openclaw-voice/venv/bin/python tr.py ep.mp3 2> time.txt
grep -E "Maximum resident|Elapsed" time.txt
