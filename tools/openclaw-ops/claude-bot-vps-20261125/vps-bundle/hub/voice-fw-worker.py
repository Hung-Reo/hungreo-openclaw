#!/usr/bin/env python3
"""VOICE-QUALITY-20261127: chép 1 file wav 16k mono bằng faster-whisper small int8, cùng công thức với Rùa
(~hung/bin/openclaw-bounded-voice): VAD + danh sách tên riêng + beam 5 + chặn đoạn không tin cậy.
Chạy bằng venv ~/.local/opt/faster-whisper-venv. Model cục bộ, không tải gì, không gọi API trả tiền.
In transcript ra stdout; lỗi hoặc không tin cậy thì exit 2 và stdout rỗng (plugin báo "chưa chép được").
"""
import math
import sys
import wave
from pathlib import Path

MODEL_DIR = Path.home() / '.claude/channels/telegram-collab/voice/models/faster-whisper-small'
VOCAB_PROMPT = ('Hưng, Rùa, Hermes, OpenClaw, Claude Code, Gemini, Samsung, iPhone, '
                'Third Eye, VPS, Telegram, translate, voice.')


def reliable(segments):
    if not segments:
        return False
    for s in segments:
        if not math.isfinite(s.avg_logprob) or not math.isfinite(s.no_speech_prob):
            return False
        if s.avg_logprob < -1 or s.no_speech_prob > .6:
            return False
    return True


def load_pcm16(wav):
    # Tự đọc wav (plugin đã đổi sang 16k mono s16le) như Rùa, không qua PyAV.
    import numpy as np
    with wave.open(wav, 'rb') as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != 16000:
            raise ValueError('wav_format')
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, np.int16).astype(np.float32) / 32768


def main(wav):
    if not (MODEL_DIR / 'model.bin').is_file():
        return 2
    try:
        audio = load_pcm16(wav)
    except (OSError, ValueError, wave.Error):
        return 2
    from faster_whisper import WhisperModel
    model = WhisperModel(str(MODEL_DIR), device='cpu', compute_type='int8',
                         cpu_threads=2, num_workers=1, local_files_only=True)
    segs, _ = model.transcribe(audio, language='vi', task='transcribe', beam_size=5, temperature=0.0,
                               condition_on_previous_text=False, vad_filter=True,
                               vad_parameters={'min_silence_duration_ms': 500},
                               initial_prompt=VOCAB_PROMPT)
    segs = list(segs)
    if not reliable(segs):
        return 2
    text = ' '.join(s.text.strip() for s in segs).strip()
    if not text:
        return 2
    print(text[:3000], flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]) if len(sys.argv) == 2 else 2)
