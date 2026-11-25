#!/usr/bin/env bash
# B6: build whisper.cpp v1.9.5 (cùng bản Mac) cho claudebot, không cần sudo.
set -euo pipefail
B=$HOME/.cache/voice-build; O=$HOME/.local/opt; mkdir -p $B $O
cd $B
if [[ ! -x $O/cmake-4.5.1-linux-x86_64/bin/cmake ]]; then
  curl -fsSL -o cmake.tgz https://github.com/Kitware/CMake/releases/download/v4.5.1/cmake-4.5.1-linux-x86_64.tar.gz
  tar -C $O -xzf cmake.tgz && rm cmake.tgz
fi
CMAKE=$O/cmake-4.5.1-linux-x86_64/bin/cmake
[[ -d whisper.cpp ]] || git clone -q --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
nice -n 19 $CMAKE -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON >/dev/null
nice -n 19 $CMAKE --build build -j 1 --target whisper-cli 2>&1 | tail -2
install -d $O/whisper.cpp-1.9.5/bin
install -m 755 build/bin/whisper-cli $O/whisper.cpp-1.9.5/bin/whisper-cli
M=$HOME/.claude/channels/telegram-collab/voice/models; install -d -m 700 $M
[[ -f $M/ggml-small-q5_1.bin ]] || curl -fsSL -o $M/ggml-small-q5_1.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin
chmod 600 $M/ggml-small-q5_1.bin
ls -la $O/whisper.cpp-1.9.5/bin/whisper-cli $M/ggml-small-q5_1.bin
sha256sum $M/ggml-small-q5_1.bin
$O/whisper.cpp-1.9.5/bin/whisper-cli --help 2>&1 | head -1
echo B6_BUILD_DONE
