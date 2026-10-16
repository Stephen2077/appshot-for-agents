# AGENTS.md

Shared rules for Claude Code and Codex. Bias toward caution over speed; for trivial tasks, use judgment.

## 1. Think Before Coding
Don't assume. Don't hide confusion. Surface tradeoffs.
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First
Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

## 3. Surgical Changes
Touch only what you must. Clean up only your own mess.
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style.
- Mention unrelated dead code; don't delete it.
- Remove imports/variables/functions that YOUR changes made unused.
- Every changed line must trace to the request.

## 4. Goal-Driven Execution
Define success criteria. Loop until verified.
- "Add validation" -> write tests for invalid inputs, then make them pass.
- "Fix the bug" -> write a test that reproduces it, then make it pass.
- "Refactor X" -> tests pass before and after.
- For multi-step tasks, state a brief plan: `1. [Step] -> verify: [check]`.

## Division of labor
- Orchestrator: the "Claude Code" bot runs everything via `claude -p` (main workflow, writing code) and calls Codex via `codex exec`.
- Claude Code: writes code and owns the main flow.
- Codex (`codex exec`): second opinion, code review, image generation.
- Before a large change, optionally have Codex write its own plan first, then compare it with the Claude Code plan before executing.

## Hard rules
- Ask Stephen before deleting files, pushing code, or touching repos outside the task.
- Never print secrets. Reply to Stephen in Chinese.
