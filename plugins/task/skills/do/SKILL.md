---
name: do
description: >
  Structured task execution: plan, external analysis, approval, implement,
  quality control, present. Use /do <task description> for any feature, bug fix, or task.
  Also manages provider/model config via /do config.
disable-model-invocation: true
argument-hint: "<task description> | config [subcommand]"
---

# /do — Structured Task Workflow

Execute the following phases strictly in order. Do not skip phases.
Present output to the user at each checkpoint marked with STOP.

## Input Validation

**If `$ARGUMENTS` starts with `config`**: strip `config` from the start of `$ARGUMENTS` (trim remaining whitespace) and jump to the [Config Management](#config-management) section. Do not run any phases.

**If `$ARGUMENTS` contains `--continue`**: strip `--continue` from arguments, then:
1. List saved plans: `ls .claude/plans/*.md 2>/dev/null`
2. If no plans found: respond "No saved plans found in `.claude/plans/`." and STOP.
3. If one plan exists: load it and skip to Phase 3 (APPROVE) with that plan. Announce: "Resuming plan: `<filename>`"
4. If multiple plans exist: show the list and ask the user which to resume. Load the chosen plan and skip to Phase 3.

**If `$ARGUMENTS` contains `--refresh-env`**: run `rm ~/.claude/do-env.json 2>/dev/null`, then strip `--refresh-env` from the task description before proceeding.

If `$ARGUMENTS` is empty or contains only whitespace (after stripping flags):
- Respond with:
  ```
  Usage: /do <task description>   — plan and implement a task
         /do config               — view and change provider/model settings
  ```
- **STOP. Do not proceed to any phase.**

## Environment Detection

Before starting Phase 1, detect available agents and project context.

### Agent detection (cached)

Agent availability is cached at `~/.claude/do-env.json` to avoid redundant `which` checks on every invocation.

**If `$ARGUMENTS` contains `--refresh-env`**: run `rm ~/.claude/do-env.json 2>/dev/null`, then strip `--refresh-env` from the task description before proceeding.

1. **Read cache**: `cat ~/.claude/do-env.json 2>/dev/null || true`
2. **If cache exists and is valid JSON**:
   - Use the `agents` array and `ollamaModels` array from the cache
   - **Validate** (only if `agents` is non-empty): for CLI-based agents (`gemini`, `codex`, `ollama`, `claude`, `aider`), run `which <agent> 2>/dev/null` to confirm it's still installed. For `openrouter`, check `[ -n "${OPENROUTER_API_KEY:-}" ]`. For `openai`, check `[ -n "${OPENAI_API_KEY:-}${OPENAI_COMPATIBLE_API_KEY:-}" ]`. For `copilot`, check `[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]`. If validation fails for the first agent in the list or `agents` is empty, discard cache and proceed to step 3.
3. **If cache is missing or invalid** — run full detection:
   - `for cmd in gemini codex ollama claude aider; do which $cmd 2>/dev/null && echo "$cmd: found" || echo "$cmd: not found"; done`
   - **OpenRouter**: detected via environment variable, not a CLI binary. Check: `[ -n "${OPENROUTER_API_KEY:-}" ] && echo "openrouter: found" || echo "openrouter: not found"`
   - **OpenAI-compatible**: detected via environment variable. Check: `[ -n "${OPENAI_API_KEY:-}${OPENAI_COMPATIBLE_API_KEY:-}" ] && echo "openai: found" || echo "openai: not found"`
   - **GitHub Copilot**: detected via environment variable. Check: `[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ] && echo "copilot: found" || echo "copilot: not found"`
   - If ollama was found: `ollama list 2>/dev/null`
   - **Save cache**: write a JSON file to `~/.claude/do-env.json` with this structure:
     ```json
     { "agents": ["gemini", "codex", "claude", "aider", "openrouter", "openai", "copilot"], "ollamaModels": ["qwen2.5-coder"], "detectedAt": "2026-03-22T14:25:00Z" }
     ```
     Use only the agent names that were found. Use the Bash tool to write the file, e.g.:
     `sh -c 'echo "{\"agents\":[\"gemini\",\"codex\",\"claude\",\"aider\",\"openrouter\",\"openai\"],\"ollamaModels\":[],\"detectedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > ~/.claude/do-env.json'`

### Platform detection (always runs)

Run `uname -s` to record the platform (e.g. `Darwin` or `Linux`). This informs command compatibility (e.g. mktemp behavior, available utilities).

### Project detection (always runs)

These are project-specific and must be checked every time:

1. **Project config**: `cat .claude/do-config.json 2>/dev/null || true`
2. **Project type**: `sh -c 'ls -1 package.json Podfile *.xcodeproj pyproject.toml requirements.txt go.mod Cargo.toml Makefile 2>/dev/null || echo "no project files"'`

Record which agents are available and proceed. If no external agents are found, skip external review phases.

### Configuration

If `.claude/do-config.json` exists, validate and use its values:
- `configVersion` must be `1` if present (reserved for future schema changes). If missing, default to `1`.
- `agents` must be an object with array values (e.g. `{"planReview": [...], "codeReview": [...]}`), not a bare string or array
- Each agent entry must match one of: `"gemini"`, `"codex"`, `"ollama:<model>"`, `"openrouter"`, `"openrouter:<model>"`, `"claude"`, `"aider"`, `"openai"`, `"openai:<model>"`, `"copilot"`, or `"copilot:<model>"`
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
    "openai": "${CLAUDE_SKILL_DIR}/scripts/openai-compatible.sh {file} {model}",
    "copilot": "${CLAUDE_SKILL_DIR}/scripts/copilot.sh {file} {model}"
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
- `"openrouter"` — OpenRouter API (default model: `google/gemini-3.1-pro-preview`)
- `"openrouter:<model>"` — OpenRouter with a specific model (e.g. `"openrouter:anthropic/claude-sonnet-4"`)
- `"claude"` — Claude Code headless mode (`claude -p`)
- `"aider"` — Aider in dry-run review mode
- `"openai"` — OpenAI-compatible API (default model: `gpt-5.4`)
- `"openai:<model>"` — OpenAI-compatible API with a specific model (e.g. `"openai:gpt-4.1-mini"`)
- `"copilot"` — GitHub Copilot API (default model: `gpt-4o`)
- `"copilot:<model>"` — GitHub Copilot API with a specific model (e.g. `"copilot:claude-sonnet-4-5"`)

The model separator may be `:` or `/` interchangeably (e.g. `copilot/gpt-4o` === `copilot:gpt-4o`). Normalise to `:` in the config file.

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
   - **Complexity Estimate**: Rate as Simple (1–2 files, ≤3 steps) / Medium (3–10 files, ≤10 steps) / Large (10+ files or 10+ steps), with a one-line scope summary
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
   - **OpenRouter**: `${CLAUDE_SKILL_DIR}/scripts/openrouter.sh $PLAN_REVIEW_FILE <model>` — replace `<model>` with the model from the agent string (e.g. `openrouter:anthropic/claude-sonnet-4` → `anthropic/claude-sonnet-4`). If no model is specified, omit the second argument to use the default (`google/gemini-3.1-pro-preview`). Requires `OPENROUTER_API_KEY` env var.
   - **Claude Code**: `cat $PLAN_REVIEW_FILE | claude -p --bare --output-format text --allowedTools "Read"` — runs Claude Code in headless mode. Uses `--bare` to skip loading hooks/plugins/MCP for fast, deterministic execution.
   - **Aider**: `aider --no-auto-commits --no-git --dry-run --yes --message-file $PLAN_REVIEW_FILE` — runs Aider in read-only dry-run mode so it reviews without modifying files.
   - **OpenAI-compatible**: `${CLAUDE_SKILL_DIR}/scripts/openai-compatible.sh $PLAN_REVIEW_FILE <model>` — works with any OpenAI-compatible API (OpenAI, Azure, LM Studio, etc.). Replace `<model>` with the model from the agent string (e.g. `openai:gpt-4.1-mini` → `gpt-4.1-mini`). If no model is specified, omit the second argument to use the default (`gpt-5.4`). Requires `OPENAI_API_KEY` or `OPENAI_COMPATIBLE_API_KEY` env var. Set `OPENAI_BASE_URL` or `OPENAI_COMPATIBLE_BASE_URL` for non-OpenAI providers.
   - **GitHub Copilot**: `${CLAUDE_SKILL_DIR}/scripts/copilot.sh $PLAN_REVIEW_FILE <model>` — calls the GitHub Copilot API. Replace `<model>` with the model from the agent string (e.g. `copilot:claude-sonnet-4-5` → `claude-sonnet-4-5`). If no model is specified, omit the second argument to use the default (`gpt-4o`). Requires `GITHUB_TOKEN` or `GH_TOKEN` env var with an active GitHub Copilot subscription.
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

**Branch creation**: Before implementing, check if the working directory is a git repository:
1. Run `git rev-parse --git-dir 2>/dev/null` — if this fails, skip branch creation silently (not a git repo).
2. Run `git rev-parse --abbrev-ref HEAD 2>/dev/null` — if the current branch already starts with `do/`, skip branch creation silently.
3. Otherwise, generate a branch name:
   - Take the task description, lowercase it, replace spaces and special characters with hyphens, collapse multiple hyphens, strip leading/trailing hyphens
   - Prefix with `do/` and truncate the slug to 50 characters total (e.g. `do/add-dark-mode-toggle`)
4. Run `git checkout -b <branch-name>` and record the branch name for Phase 6.

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
   - **CRITICAL** — Fix immediately before proceeding
   - **WARNING** — Fix if straightforward; note if complex
   - **SUGGESTION:safe** — Auto-apply if purely cosmetic (style, imports, naming with no logic change). These are low-risk and can be applied without user approval.
   - **SUGGESTION:risky** — Log only. Do not auto-apply suggestions involving behavioral, architectural, or API changes. Surface them in Phase 6 as follow-up items.
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

---

## Config Management

Reached when `$ARGUMENTS` started with `config`. The remaining text after stripping
`config` is the subcommand. Parse it and dispatch below.

The config file is `.claude/do-config.json` in the current project directory.

### Valid provider values

| Value | Description |
|---|---|
| `gemini` | Gemini CLI |
| `codex` | Codex CLI |
| `ollama:<model>` | Ollama with a specific model (e.g. `ollama:qwen2.5-coder`) |
| `openrouter` | OpenRouter API (default model: `google/gemini-3.1-pro-preview`) |
| `openrouter:<model>` | OpenRouter with a specific model |
| `claude` | Claude Code headless mode |
| `aider` | Aider in dry-run review mode |
| `openai` | OpenAI-compatible API (default model: `gpt-5.4`) |
| `openai:<model>` | OpenAI-compatible API with a specific model |
| `copilot` | GitHub Copilot API (default model: `gpt-4o`) |
| `copilot:<model>` | GitHub Copilot with a specific model (e.g. `copilot:claude-sonnet-4-5`) |

Use comma separation for fallback order: `copilot,gemini` means try copilot first, then gemini.

The model separator can be either `:` or `/` — `copilot:gpt-4o` and `copilot/gpt-4o` are equivalent. Always normalise to `:` when writing to the config file.

CLI-only agents (`gemini`, `codex`, `claude`, `aider`) do not accept a model suffix.

---

### (no subcommand) or `show`

Print the current configuration.

1. `cat .claude/do-config.json 2>/dev/null || true`
2. If missing: respond "No `.claude/do-config.json` found — `/do` is using auto-detected defaults." and STOP.
3. Otherwise parse and display each section:

```
Provider config (.claude/do-config.json)
─────────────────────────────────────────
Plan review agents : copilot, gemini
Code review agents : copilot:gpt-4o
Max iterations     : 3
Max code review    : 2
Skip threshold     : 1 file / 2 steps

QC commands
─────────────────────────────────────────
test  : npm test
build : npm run build
lint  : eslint .
```

Omit sections that are not set.

---

### `set provider <value>`

Set **both** `planReview` and `codeReview` to the same provider(s).

- Parse `<value>`: split on commas, trim each entry, validate against the provider list above. Error and STOP if invalid.
- Read `.claude/do-config.json` or start from `{"configVersion":1}`.
- Set `agents.planReview` and `agents.codeReview` to the parsed array.
- Write back. Respond: "Set both plan and code review agents to: `<value>`"

---

### `set plan <value>`

Set only `agents.planReview`. Same steps as `set provider` but only that field.
Respond: "Set plan review agents to: `<value>`"

---

### `set code <value>`

Set only `agents.codeReview`. Same steps as `set provider` but only that field.
Respond: "Set code review agents to: `<value>`"

---

### `set model <model>`

Update the model suffix on all currently configured API providers, in both
`planReview` and `codeReview`. Skip CLI-only agents (`gemini`, `codex`, `claude`, `aider`).

- If no config file exists: respond "No config found. Use `/do config set provider <provider>` first." and STOP.
- For each entry in `agents.planReview` and `agents.codeReview`: strip any existing `:<model>` suffix and append `:<model>`.
- Write back and respond with a summary of what changed.

---

### `set iterations <n>`

Set `maxIterations` (max QC fix retries). Validate `<n>` is a positive integer.
Respond: "Set max iterations to `<n>`."

---

### `set code-iterations <n>`

Set `maxCodeReviewIterations`. Validate `<n>` is a positive integer.
Respond: "Set max code review iterations to `<n>`."

---

### `set skip-threshold <maxFiles> <maxSteps>`

Set `skipReviewThreshold`. Validate both are positive integers.
Respond: "Set skip threshold to `<maxFiles>` file(s) / `<maxSteps>` step(s)."

---

### `set qc <type> <command>`

Add or replace a QC command. `<type>` is the key (e.g. `test`, `lint`).
Everything after `<type> ` is the command string.
Respond: "Set QC command `<type>` to: `<command>`"

---

### `unset provider`

Remove the `agents` key from config entirely (revert to auto-detection).
Respond: "Removed agent config — `/do` will auto-detect available agents."

---

### `unset qc <type>`

Remove `qc.<type>` from config.
Respond: "Removed QC command `<type>`."

---

### `reset`

Delete `.claude/do-config.json`.

1. Ask: "This will delete `.claude/do-config.json` and revert all settings to defaults. Proceed? (yes/no)"
2. If yes: `rm -f .claude/do-config.json` → respond "Config deleted."
3. If no: respond "Cancelled."

---

### `refresh`

Clear the agent detection cache.

1. `rm -f ~/.claude/do-env.json`
2. Respond: "Agent detection cache cleared. `/do` will re-detect on next run."

---

### Unrecognized subcommand

Respond:

```
Usage: /do config [subcommand]

  show                               Print current config
  set provider <value>               Set provider for both phases
  set plan <value>                   Set provider for plan review only
  set code <value>                   Set provider for code review only
  set model <model>                  Update model on all API providers
  set iterations <n>                 Set max QC fix iterations
  set code-iterations <n>            Set max code review iterations
  set skip-threshold <files> <steps> Set small-plan skip threshold
  set qc <type> <command>            Add or replace a QC command
  unset provider                     Remove agent config (revert to auto-detect)
  unset qc <type>                    Remove a QC command
  reset                              Delete the config file
  refresh                            Clear agent detection cache

Provider formats:
  gemini | codex | claude | aider
  ollama:<model>
  openrouter | openrouter:<model>
  openai | openai:<model>
  copilot | copilot:<model>

Use commas for fallback order: copilot,gemini
```

---

### File write helper

When writing `.claude/do-config.json`:
1. Use `python3` to produce pretty-printed JSON (2-space indent).
2. Preserve all existing keys not touched by the subcommand.
3. Always keep `configVersion: 1`.

```bash
python3 - <<'PYEOF' > .claude/do-config.json
import json, sys
with open(".claude/do-config.json") as f:
    data = json.load(f)
# ... mutate data ...
print(json.dumps(data, indent=2))
PYEOF
```

For a fresh file, start with `{"configVersion": 1}` and mutate from there.
