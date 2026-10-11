#!/usr/bin/env bash
# Download Gemma 4 E4B (.litertlm, LiteRT-LM) to the bot box. Resumable; verifies size + sha256.
# License: Apache-2.0 (ai.google.dev/edge/litert-lm/models/gemma-4). The litert-community repo is NOT gated:
# anonymous HEAD → 200 on 2026-10-10, so no HF account/token is needed (H7 resolved).
set -euo pipefail
VARIANT=${VARIANT:-E4B}                       # E4B (3.66 GB, Android target) | E2B (2.58 GB, fallback / iOS)
DIR=${MODEL_DIR:-$HOME/models}
case "$VARIANT" in
  E4B) NAME=gemma-4-E4B-it.litertlm; REPO=litert-community/gemma-4-E4B-it-litert-lm
       SIZE=3659530240; SHA=0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0 ;;
  E2B) NAME=gemma-4-E2B-it.litertlm; REPO=litert-community/gemma-4-E2B-it-litert-lm; SIZE=""; SHA="" ;;
  *) echo "VARIANT must be E4B|E2B" >&2; exit 2 ;;
esac
URL="https://huggingface.co/$REPO/resolve/main/$NAME"
mkdir -p "$DIR"; OUT="$DIR/$NAME"
need=$(( ${SIZE:-3000000000} / 1024 + 1048576 ))
avail=$(df -Pk "$DIR" | awk 'NR==2{print $4}')
(( avail > need )) || { echo "Not enough disk in $DIR ($avail KB < $need KB)" >&2; exit 3; }
curl -fL --retry 5 --retry-delay 5 -C - -o "$OUT" "$URL"
if [[ -n "$SIZE" ]]; then [[ $(stat -c %s "$OUT") == "$SIZE" ]] || { echo "size mismatch" >&2; exit 4; }; fi
if [[ -n "$SHA" ]]; then echo "$SHA  $OUT" | sha256sum -c - ; fi
echo "MODEL_OK $OUT"
