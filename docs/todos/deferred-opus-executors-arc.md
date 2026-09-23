### Deferred from the Opus-executors / master-model arc — 2026-09-23

The stage-5 gate was clean at `9ff0a75` after two rounds (round 1: two P1s fixed in `a5f4b27`;
round 2: zero P0/P1, four P2). One P2 was fixed before the push (`d439477`: `--master` refuses
`max`, which Claude Code applies to one session only). The P2 that `--master=keep` leaves the
don't-ask file in place is by design and not listed.

1. `[P2 conf:0.5] install.sh:119 — MODEL_ID:EFFORT is split at the first colon, so a model ID that contains a colon (a Bedrock ID such as us.anthropic.claude-…-v1:0) mis-splits and fails with a misleading "invalid effort" error. Fix: split at the last colon, and only when the suffix is a known effort → whole-round2 #2`
2. `[P2 conf:0.4] skills/analyze-arcs/scripts/analyze.py:17-18 — pins_for compares the session start against the date '2026-09-23', so sessions that started earlier that day, before the pin change landed, are judged by the new pins. Fix: compare against the change's exact UTC time → whole-round2 #3`
