---
name: do
description: >
  Structured task execution: plan, external analysis, approval, implement,
  quality control, present. Use /do <task description> for any feature, bug fix, or task.
disable-model-invocation: true
argument-hint: <task description>
---

# /do — Structured Task Workflow

Execute the following phases strictly in order. Do not skip phases.
Present output to the user at each checkpoint marked with STOP.

## Input Validation

If `$ARGUMENTS` is empty or contains only whitespace (after stripping `--refresh-env` if present):
- Respond with: "Usage: `/do <task description>` — describe what you want to build, fix, or refactor."
- **STOP. Do not proceed to any phase.**

## Environment Detection

Before starting Phase 1, detect available agents and project context.

### Agent detection (cached)

Agent availability is cached at `~/.claude/do-env.json` to avoid redundant `which` checks on every invocation.

**If `$ARGUMENTS` contains `--refresh-env`**: run `rm ~/.claude/do-env.json 2>/dev/null`, then strip `--refresh-env` from the task description before proceeding.

1. **Read cache**: `cat ~/.claude/do-env.json 2>/dev/null`
2. **If cache exists and is valid JSON**:
   - Use the `agents` array and `ollamaModels` array from the cache
   - **Validate** (only if `agents` is non-empty): for CLI-based agents (`gemini`, `codex`, `ollama`, `claude`, `aider`), run `which <agent> 2>/dev/null` to confirm it's still installed. For `openrouter`, check `[ -n "${OPENROUTER_API_KEY:-}" ]`. For `openai`, check `[ -n "${OPENAI_API_KEY:-}${OPENAI_COMPATIBLE_API_KEY:-}" ]`. If validation fails for the first agent in the list or `agents` is empty, discard cache and proceed to step 3.
3. **If cache is missing or invalid** — run full detection:
   - `for cmd in gemini codex ollama claude aider; do which $cmd 2>/dev/null && echo "$cmd: found" || echo "$cmd: not found"; done`
   - **OpenRouter**: detected via environment variable, not a CLI binary. Check: `[ -n "${OPENROUTER_API_KEY:-}" ] && echo "openrouter: found" || echo "openrouter: not found"`
   - **OpenAI-compatible**: detected via environment variable. Check: `[ -n "${OPENAI_API_KEY:-}${OPENAI_COMPATIBLE_API_KEY:-}" ] && echo "openai: found" || echo "openai: not found"`
   - If ollama was found: `ollama list 2>/dev/null`
   - **Save cache**: write a JSON file to `~/.claude/do-env.json` with this structure:
     ```json
     { "agents": ["gemini", "codex", "claude", "aider", "openrouter", "openai"], "ollamaModels": ["qwen2.5-coder"], "detectedAt": "2026-03-22T14:25:00Z" }
     ```
     Use only the agent names that were found. Use the Bash tool to write the file, e.g.:
     `sh -c 'echo "{\"agents\":[\"gemini\",\"codex\",\"claude\",\"aider\",\"openrouter\",\"openai\"],\"ollamaModels\":[],\"detectedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > ~/.claude/do-env.json'`

### Platform detection (always runs)

Run `uname -s` to record the platform (e.g. `Darwin` or `Linux`). This informs command compatibility (e.g. mktemp behavior, available utilities).

### Project detection (always runs)

These are project-specific and must be checked every time:

1. **Project config**: `cat .claude/do-config.json 2>/dev/null`
2. **Project type**: `sh -c 'ls -1 package.json Podfile *.xcodeproj pyproject.toml requirements.txt go.mod Cargo.toml Makefile 2>/dev/null || echo "no project files"'`

Record which agents are available and proceed. If no external agents are found, skip external review phases.

### Configuration

If `.claude/do-config.json` exists, validate and use its values:
- `configVersion` must be `1` if present (reserved for future schema changes). If missing, default to `1`.
- `agents` must be an object with array values (e.g. `{"planReview": [...], "codeReview": [...]}`), not a bare string or array
- Each agent entry must match one of: `"gemini"`, `"codex"`, `"ollama:<model>"`, `"openrouter"`, `"openrouter:<model>"`, `"claude"`, `"aider"`, `"openai"`, or `"openai:<model>"`
- `maxIterations` and `maxCodeReviewIterations` must be positive integers if present
- `skipReviewThreshold` must be an object with `maxFiles` and `maxSteps` as positive integers if present
- If the config is malformed, warn the user and fall back to auto-detection

Schema:

```json
{
  "configVersion": 1,
  "agents": {
    "planReview": ["ollama:qwen2.5-coder", "gemini"],
    "codeReview": ["gemini", "codex"]
  },
  "agentCommands": {
    "gemini": "cat {file} | gemini -p \"Review the content provided via stdin. Respond in plain text.\" -o text",
    "codex": "cat {file} | codex exec -q -",
    "ollama": "cat {file} | ollama run {model}",
    "openrouter": "${CLAUDE_SKILL_DIR}/scripts/openrouter.sh {file} {model}",
    "claude": "cat {file} | claude -p --bare --output-format text --allowedTools \"Read\"",
    "aider": "aider --no-auto-commits --no-git --dry-run --yes --message-file {file}",
    "openai": "${CLAUDE_SKILL_DIR}/scripts/openai-compatible.sh {file} {model}"
  },
  "qc": {
    "test": "npm test",
    "build": "npm run build",
    "lint": "eslint ."
  },
  "maxIterations": 3,
  "maxCodeReviewIterations": 2,
  "skipReviewThreshold": { "maxFiles": 1, "maxSteps": 2 }
}
```

### Agent routing

The `agents` field controls which agent is used per phase. Each entry is an ordered list — the skill tries the first available agent and falls back to the next.

Agent format:
- `"gemini"` — Gemini CLI
- `"codex"` — Codex CLI
- `"ollama:<model>"` — Ollama with a specific model (e.g. `"ollama:qwen2.5-coder"`)
- `"openrouter"` — OpenRouter API (default model: `google/gemini-2.0-flash-001`)
- `"openrouter:<model>"` — OpenRouter with a specific model (e.g. `"openrouter:anthropic/claude-sonnet-4"`)
- `"claude"` — Claude Code headless mode (`claude -p`)
- `"aider"` — Aider in dry-run review mode
- `"openai"` — OpenAI-compatible API (default model: `gpt-4o`)
- `"openai:<model>"` — OpenAI-compatible API with a specific model (e.g. `"openai:gpt-4.1-mini"`)

If `agents` is omitted, all phases use the first available agent detected in the environment.
The `agentCommands` field is optional — if omitted, use the default commands listed in the Analyze phase.

> **Security note**: Custom `agentCommands` execute directly in your shell. Only use this field in projects you trust — a malicious `.claude/do-config.json` in a cloned repo could run arbitrary commands when `/do` is invoked.

If no config file exists, auto-detect everything from the environment output above.

---

## Phase 1: PLAN (Research & Design)

1. Analyze the task: **$ARGUMENTS**
2. Explore the codebase to understand relevant files, patterns, and architecture
   - Use the Explore subagent for broad research if the task scope is unclear
   - Use Grep/Glob for targeted lookups
3. Create an implementation plan containing:
   - **Task Summary**: What needs to be done and why
   - **Files to Modify/Create**: Each with a brief description of changes
   - **Implementation Steps**: Numbered, ordered, actionable
   - **Testing Strategy**: How to verify correctness
   - **Risks & Edge Cases**: Potential issues to watch for
4. Save the plan to `.claude/plans/<descriptive-slug>.md`

---

## Phase 2: ANALYZE (External Review)

> If no external agent is available, skip to Phase 3.

**Small-plan threshold**: Before proceeding, check if the plan modifies only **N files** and has **M or fewer implementation steps**, where N and M come from `skipReviewThreshold` in config (default: `maxFiles: 1`, `maxSteps: 2`). If so, skip external review with a note: "Plan is small — skipping external review." and proceed directly to Phase 3.

1. Read the prompt template from `${CLAUDE_SKILL_DIR}/prompts/plan-review.md` (`$CLAUDE_SKILL_DIR` is set by Claude Code to the skill's directory at runtime)
2. Build the full review prompt by replacing the template placeholders:
   - `{TASK}` → the task description ($ARGUMENTS)
   - `{PLAN}` → the full plan content
   - `{CONTEXT}` → brief codebase context (key file paths, interfaces involved)
3. Create a temp file and write the assembled prompt to it:
   `PLAN_REVIEW_FILE=$(mktemp /tmp/do-plan-review-XXXXXX)` then write the prompt content to `$PLAN_REVIEW_FILE`
4. Select the agent: use the first available entry from `agents.planReview` in config, or fall back to the first detected agent.
5. Call the selected agent using the Bash tool with `timeout: 60000` (60 seconds) for the first attempt. If it times out or fails, try the next agent with `timeout: 90000` (90 seconds). Agents that require authentication or network setup may need longer on first run.
   - **Gemini**: `cat $PLAN_REVIEW_FILE | gemini -p "Review the implementation plan provided via stdin. Respond in plain text." -o text`
   - **Codex**: `cat $PLAN_REVIEW_FILE | codex exec -q -`
   - **Ollama**: `cat $PLAN_REVIEW_FILE | ollama run <model>` — replace `<model>` with the model from the agent string (e.g. `ollama:qwen2.5-coder` → `qwen2.5-coder`)
   - **OpenRouter**: `${CLAUDE_SKILL_DIR}/scripts/openrouter.sh $PLAN_REVIEW_FILE <model>` — replace `<model>` with the model from the agent string (e.g. `openrouter:anthropic/claude-sonnet-4` → `anthropic/claude-sonnet-4`). If no model is specified, omit the second argument to use the default (`google/gemini-2.0-flash-001`). Requires `OPENROUTER_API_KEY` env var.
   - **Claude Code**: `cat $PLAN_REVIEW_FILE | claude -p --bare --output-format text --allowedTools "Read"` — runs Claude Code in headless mode. Uses `--bare` to skip loading hooks/plugins/MCP for fast, deterministic execution.
   - **Aider**: `aider --no-auto-commits --no-git --dry-run --yes --message-file $PLAN_REVIEW_FILE` — runs Aider in read-only dry-run mode so it reviews without modifying files.
   - **OpenAI-compatible**: `${CLAUDE_SKILL_DIR}/scripts/openai-compatible.sh $PLAN_REVIEW_FILE <model>` — works with any OpenAI-compatible API (OpenAI, Azure, LM Studio, etc.). Replace `<model>` with the model from the agent string (e.g. `openai:gpt-4.1-mini` → `gpt-4.1-mini`). If no model is specified, omit the second argument to use the default (`gpt-4o`). Requires `OPENAI_API_KEY` or `OPENAI_COMPATIBLE_API_KEY` env var. Set `OPENAI_BASE_URL` or `OPENAI_COMPATIBLE_BASE_URL` for non-OpenAI providers.
   - **Custom**: If `agentCommands` defines a command for this agent, use it with `{file}` replaced by `$PLAN_REVIEW_FILE` and `{model}` replaced by the model name
   - Use the Bash tool's `timeout` parameter instead of the `timeout` shell command (which is unavailable on macOS)
   - If all agents fail or time out, note the failure and continue to the checkpoint without external review.
6. Clean up: `rm -f $PLAN_REVIEW_FILE` — **this MUST be the very next Bash command after the agent call**, regardless of whether it succeeded, failed, or timed out. Do not process the agent output or perform any other action before running cleanup. This prevents prompt content from remaining on disk if subsequent steps fail.
7. Capture and analyze the feedback
8. If the feedback suggests significant improvements:
   - Revise the plan
   - Update the saved plan file
   - Note what changed and why

---

## Phase 3: APPROVE (User Checkpoint)

Present to the user:
- The implementation plan (revised if applicable)
- External agent feedback summary (if available)
- Changes made based on feedback (if any)

**STOP. Ask the user to approve, reject, or request changes to the plan.**

- **If approved**: proceed to Phase 4.
- **If rejected with feedback**: revise the plan based on user feedback, update the saved plan file, re-run external analysis if the changes are significant, then present the revised plan again. Repeat until approved.
- **If rejected without feedback**: ask the user what they'd like changed before proceeding.

---

## Phase 4: IMPLEMENT

1. Review the approved plan
2. For each implementation unit:
   - Spawn an **Agent** (using the Agent tool) with a complete task description
   - Include the relevant plan section, file paths, and expected changes
   - The agent must verify its changes compile/parse correctly
3. For large tasks with independent units, spawn multiple agents in parallel using worktree isolation
4. After all agents complete, verify the full set of changes is coherent

---

## Phase 5: QUALITY CONTROL

### 5a — Automated Testing

Run QC commands based on project type (or config overrides). **Before running any auto-detected command, verify it exists**:

- **Node.js**: Run `node -e "process.exit(require('./package.json').scripts?.test ? 0 : 1)"` before attempting `npm test`. Only run `npm run build` if a `build` script exists. Only run `npx playwright test` if `playwright` is in dependencies.
- **Python/Go/Rust/iOS**: Check the relevant tool is installed (`which pytest`, `which go`, etc.) before running.
- **If no QC commands are applicable or available**: Skip automated testing with a note: "No applicable QC commands detected — skipping automated testing." and proceed to 5b.

| Type | Commands |
|---|---|
| Node.js | `npm test` (if test script exists), `npx playwright test` (if installed), `npm run build` (if build script exists) |
| iOS/macOS | `xcodebuild -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 16' build` |
| Python | `pytest`, `ruff check .` |
| Go | `go test ./...`, `go vet ./...` |
| Rust | `cargo test`, `cargo clippy` |
| Other | Check Makefile, CI config, or `.claude/do-config.json` for commands |

On failure: analyze the error, fix the issue, re-run the failing command.
Maximum **3 iterations** per failing command. If still failing after 3 attempts, report the failure and continue.

### 5b — External Code Review

> If no external agent is available, skip to Phase 6.

1. Generate a diff of all changes including new untracked files:
   - Identify new untracked files created during implementation (use `git ls-files --others --exclude-standard` and filter to files relevant to the plan)
   - `git add -N <file1> <file2> ...` only for those plan-relevant new files (do NOT use `git add -N .` — it would expose unrelated files like `.env` or credentials to the external agent)
   - `git diff HEAD` (captures both staged, unstaged, and intent-to-add files)
   - If the diff exceeds 15,000 lines, truncate to the most relevant files (prioritize files listed in the plan) and note the truncation in the review prompt
2. Read the prompt template from `${CLAUDE_SKILL_DIR}/prompts/code-review.md`
3. Build the review prompt by replacing placeholders:
   - `{TASK}` → the task description ($ARGUMENTS)
   - `{PLAN}` → the approved plan content
   - `{DIFF}` → the full diff output
4. Create a temp file and write the review prompt to it:
   `CODE_REVIEW_FILE=$(mktemp /tmp/do-code-review-XXXXXX)` then write the prompt content to `$CODE_REVIEW_FILE`
5. Select the agent: use the first available entry from `agents.codeReview` in config, or fall back to the first detected agent.
6. Call the selected agent (same invocation patterns and timeout strategy as Phase 2 — 60s first attempt, 90s fallback — using `$CODE_REVIEW_FILE` as the temp file). For **Codex** specifically, you may also try `codex review` as an alternative.
   Clean up: `rm -f $CODE_REVIEW_FILE` — **this MUST be the very next Bash command after the agent call**, regardless of outcome. Do not process output before cleanup.
7. Analyze the feedback:
   - Fix **CRITICAL** issues immediately
   - Note **WARNING**s and fix if straightforward
   - Log **SUGGESTION**s but do not necessarily act on all
8. Re-run affected tests after fixes
9. Maximum **N code review iterations**, where N comes from `maxCodeReviewIterations` in config (default: 2)

---

## Phase 6: PRESENT

Present to the user:

1. **Changes Summary** — files modified/created with brief descriptions
2. **Plan Compliance** — checklist of plan items with completion status
3. **QC Results** — test pass/fail, build status, external review summary
4. **Outstanding Items** — any warnings, suggestions, or follow-up tasks

Ask the user for final approval.
