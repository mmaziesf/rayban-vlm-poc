#!/usr/bin/env bash
# Summarize GlanceVlm timing lines: load once, infer p50/p90/max. M1c pass = infer p50 < 5000 ms.
log=$(cat "${1:-/dev/stdin}")   # buffer once: stdin can only be read once
grep -o "load_ms=[0-9]*" <<<"$log" | head -1
grep -o "infer_ms=[0-9]*" <<<"$log" | cut -d= -f2 | sort -n | awk '{a[NR]=$1} END{
  if(NR==0){print "no infer lines"; exit 1}
  p50=a[int((NR+1)/2)]; p90=a[int(NR*0.9+0.5)<1?1:int(NR*0.9+0.5)];
  printf "turns=%d infer_p50_ms=%d infer_p90_ms=%d infer_max_ms=%d M1C=%s\n", NR, p50, p90, a[NR], (p50<5000?"PASS":"FAIL")}'
