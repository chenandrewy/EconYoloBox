# 0919b — Claude Code vs Codex speed: yolo vs AI-reviewer mode

Copied 2026-09-19 from the Obsidian main vault (Work/AI-Journal). Snapshot;
the vault copy is the one that gets edited.

Web search (Claude Code session, 2026-09-19) on how much the AI-reviewer modes slow things down vs yolo. Context: yolobox design.

**Headline: neither vendor publishes a measured latency number.** Everything is qualitative. Both agree the reviewer is designed to run rarely, so per-session cost is usually small.

## Claude Code: auto mode vs `--dangerously-skip-permissions`

How the overhead is structured
- Two-stage classifier: fast stage-1 filter, then a reasoning stage only if stage 1 is unsure. Stage 2 reuses stage 1's prompt via cache ("almost entirely cache-hit from stage 1"). Stage 1 alone: 8.5% false-block rate; full pipeline: 0.4%. [Anthropic engineering post](https://www.anthropic.com/engineering/claude-code-auto-mode)
- Tiered evaluation: allow/deny rules first; "in-project edits are allowed without a classifier call" because "routine coding doesn't pay classifier latency"; only the remainder hits the model. [arXiv stress test](https://arxiv.org/html/2604.04978v2)
- Official docs: "may have a small impact on token consumption, cost, and latency for tool calls." No number. [permission modes docs](https://code.claude.com/docs/en/permission-modes)

In practice
- Anthropic stopped billing Pro/Max/Team for classifier tokens on 2026-08-07, when auto mode became the default. [claude.com blog](https://claude.com/blog/auto-mode-default-in-claude-code)
- Third-party: "for small tasks the overhead is negligible, but for a 200-tool-call session, the overhead adds up, though it's not a dealbreaker." [buildfastwithai](https://www.buildfastwithai.com/blogs/claude-code-auto-mode-2026)
- Bypass mode has no gate at all, so strictly faster per call. [claudefa.st](https://claudefa.st/blog/guide/development/permission-management), [Shipyard](https://shipyard.build/blog/claude-code-auto-mode/)

## Codex CLI: auto-review (guardian) vs `--yolo` / `danger-full-access`

How the overhead is structured
- Auto-review is a **reviewer swap, not a permission grant**. Only runs on *escalation requests* (network, writes outside workspace, etc.). "Auto-review does not run for routine actions already allowed inside the sandbox." [OpenAI auto-review docs](https://learn.chatgpt.com/docs/sandboxing/auto-review)
- Reviewer is **GPT-5.4 Thinking, low reasoning** — a full LLM call, not a small classifier. OpenAI says outright "Auto-review sacrifices speed for security" vs full access, and that they "monitor added latency" in production but don't report it. [OpenAI alignment post](https://alignment.openai.com/auto-review/)
- Fires rarely: sessions stop for human approval "roughly 200x less often" than manual; ~99% of escalated actions approved. [same]
- Community: "adds latency (an extra LLM call per approval)... For interactive development, the latency is often acceptable. For `codex exec` in CI pipelines, you typically want deterministic rule-based approvals instead." [Codex KB internals](https://codex.danielvaughan.com/2026/04/10/codex-cli-internals-queue-pair-guardian-sandbox/)
- Rough edges: guardian timeouts under slow network used to surface as denials [failure modes post](https://codex.danielvaughan.com/2026/04/20/when-guardian-approval-goes-wrong-failure-modes-escalation-patterns/); open bug where auto-review keeps running under `on-request` and "amplifies quota usage" [openai/codex #43287](https://github.com/openai/codex/issues/43287)

YOLO
- `--yolo` = `danger-full-access` + `approval_policy = never`: no sandbox, no gate. "The speed is real, and for well-scoped work it feels great." [HarnessRouter](https://harnessrouter.ai/blog/codex-full-auto), [codeagentswarm](https://www.codeagentswarm.com/en/guides/codex-yolo-mode)

## Side-by-side

| | Claude Code auto | Codex auto-review |
|---|---|---|
| Reviewer | Two-stage classifier (small fast filter + cached reasoning stage) | GPT-5.4 Thinking (low) — full model call |
| When it runs | Every tool call not covered by rules / in-project edits | Only on sandbox escalation requests |
| Published latency | None ("small impact") | None ("sacrifices speed") |
| Classifier tokens billed | No (Pro/Max/Team, since Aug 2026) | Counts against quota (see bug above) |

## Takeaway for yolobox

Reviewer overhead per session scales with how many actions cross a boundary, not total tool calls. Codex's is heavier per invocation (real LLM) but invoked less often; Claude's is lighter but checks more calls. For a long autonomous run of mostly in-repo edits + tests, both should be within a few percent of yolo; for network-heavy or system-touching work the gap widens. Nobody has published a real number — would have to time it ourselves.

Related: [[260813 redditors who always use yolo anyway]], [[260915 Codex yolo disaster in the wild]]
