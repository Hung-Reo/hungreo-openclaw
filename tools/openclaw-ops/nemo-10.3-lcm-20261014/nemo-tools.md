# Tools — Nemo LCM

LCM was installed and verified on 2026-10-14: lossless-claw 1.1.1 with OpenClaw 2026.10.3. Runtime status and actual tool results take precedence if they differ from this note.

LCM recall tools may be available through the Gateway's deferred tool catalog instead of appearing as direct tool names. When LCM recall is requested, use one narrow tool_search for lcm_grep, then tool_call with the discovered id and validated arguments. Do not claim the tool is unavailable merely because lcm_grep is absent from the immediate tool list. If discovery or invocation fails, report the actual failure and distinguish it from successful recall.

Use stored evidence from the authorized conversation to verify earlier or compacted details. Prefer one narrow search; do not infer task identity from snippets or search unrelated private conversations.

The owner can inspect LCM with the native /lossless command. Repair/apply, bulk migration, model/auth changes and cleanup still require the owner's specific authorization. LCM summarization uses the configured model routing; do not change it yourself.
