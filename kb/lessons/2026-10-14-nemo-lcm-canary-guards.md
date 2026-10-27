# 14/10/2026 — Nemo LCM canary: SSH unlock, Doctor warning and tool discovery

Loại: nemo, lcm, upgrade, ssh, bash-err-trap, doctor, deferred-tools, evidence

VERIFIED: GO Nemo 10.3 + LCM 1.1.1 deployed at 21:26:13 VNT; isolated model-backed compaction/restart/recall and live model/LCM grep passed. See tools/openclaw-ops/nemo-10.3-lcm-20261014/REPORT.md.

- `Permission denied (publickey)` in BatchMode alone does not prove the server rejects the key. Filter SSH debug for offered/accepted key; check ssh-agent identities. Here server accepted it but local encrypted key could not sign until the operator unlocked it. Never ask for a passphrase in chat or modify server access to work around this.
- `set +e` does not suppress an ERR trap, including inside a shell helper with output redirection. The first Doctor warning-only exit 1 incorrectly triggered safe rollback. Use `if command; then rc=0; else rc=$?; fi`, then validate JSON severity. Regression for this expected exit path passed before retry.
- A model saying “no lcm_grep” does not establish tool availability. Deferred catalog exposes tool_search/tool_call; actual id was openclaw:lossless-claw:lcm_grep. Verify dispatch + tool result in stored parts, not a recalled marker alone. Added narrow Nemo TOOLS.md guidance; subsequent direct request discovered and invoked the tool.
- Clone-only freshTail/fanout tuning enables a small real compaction test without changing serving defaults. Test model-backed summary, restart persistence, data retrieval, resource invariants and unaffected PIDs separately. Forced Sol route smoke is not automatic failover proof.
- An early RAM snapshot and readyz do not certify soak or every LCM/production workload. Keep paired core/plugin versions pinned during this canary; do not upgrade other profiles or claim savings from the canary alone.
