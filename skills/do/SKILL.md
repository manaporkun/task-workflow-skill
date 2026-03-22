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
   - **Validate** (only if `agents` is non-empty): run `which <first-agent-in-list> 2>/dev/null` to confirm it's still installed. If validation fails or `agents` is empty, discard cache and proceed to step 3.
3. **If cache is missing or invalid** — run full detection:
   - `which gemini 2>/dev/null`
   - `which codex 2>/dev/null`
   - `which ollama 2>/dev/null`
   - If ollama was found: `ollama list 2>/dev/null`
   - **Save cache**: write a JSON file to `~/.claude/do-env.json` with this structure:
     ```json
     { "agents": ["gemini", "codex"], "ollamaModels": ["qwen2.5-coder"], "detectedAt": "2026-03-22T14:25:00Z" }
     ```
     Use only the agent names that were found. Use the Bash tool to write the file, e.g.:
     `sh -c 'echo "{\"agents\":[\"gemini\",\"codex\"],\"ollamaModels\":[],\"detectedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > ~/.claude/do-env.json'`

### Project detection (always runs)

These are project-specific and must be checked every time:

1. **Project config**: `cat .claude/do-config.json 2>/dev/null`
2. **Project type**: `sh -c 'ls -1 package.json Podfile *.xcodeproj pyproject.toml requirements.txt go.mod Cargo.toml Makefile 2>/dev/null || echo "no project files"'`

Record which agents are available and proceed. If no external agents are found, skip external review phases.

### Configuration

If `.claude/do-config.json` exists, validate and use its values:
- `agents` must be an object with array values (e.g. `{"planReview": [...], "codeReview": [...]}`), not a bare string or array
- Each agent entry must match the format `"gemini"`, `"codex"`, or `"ollama:<model>"`
- `maxIterations` must be a positive integer if present
- If the config is malformed, warn the user and fall back to auto-detection

Schema:

```json
{
  "agents": {
    "planReview": ["ollama:qwen2.5-coder", "gemini"],
    "codeReview": ["gemini", "codex"]
  },
  "agentCommands": {
    "gemini": "cat {file} | gemini -p \"Review the content provided via stdin. Respond in plain text.\" -o text",
    "codex": "cat {file} | codex exec -q -",
    "ollama": "cat {file} | ollama run {model}"
  },
  "qc": {
    "test": "npm test",
    "build": "npm run build",
    "lint": "eslint ."
  },
  "maxIterations": 3
}
```

### Agent routing

The `agents` field controls which agent is used per phase. Each entry is an ordered list — the skill tries the first available agent and falls back to the next.

Agent format:
- `"gemini"` — Gemini CLI
- `"codex"` — Codex CLI
- `"ollama:<model>"` — Ollama with a specific model (e.g. `"ollama:qwen2.5-coder"`)

If `agents` is omitted, all phases use the first available agent detected in the environment.
The `agentCommands` field is optional — if omitted, use the default commands listed in the Analyze phase.
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

1. Read the prompt template from `${CLAUDE_SKILL_DIR}/prompts/plan-review.md` (`$CLAUDE_SKILL_DIR` is set by Claude Code to the skill's directory at runtime)
2. Build the full review prompt by replacing the template placeholders:
   - `{TASK}` → the task description ($ARGUMENTS)
   - `{PLAN}` → the full plan content
   - `{CONTEXT}` → brief codebase context (key file paths, interfaces involved)
3. Create a temp file and write the assembled prompt to it:
   `PLAN_REVIEW_FILE=$(mktemp /tmp/do-plan-review-XXXXXX.md)` then write the prompt content to `$PLAN_REVIEW_FILE`
4. Select the agent: use the first available entry from `agents.planReview` in config, or fall back to the first detected agent.
5. Call the selected agent (with a 120-second timeout):
   - **Gemini**: `timeout 120 sh -c 'cat $PLAN_REVIEW_FILE | gemini -p "Review the implementation plan provided via stdin. Respond in plain text." -o text'`
   - **Codex**: `timeout 120 sh -c 'cat $PLAN_REVIEW_FILE | codex exec -q -'`
   - **Ollama**: `timeout 120 sh -c 'cat $PLAN_REVIEW_FILE | ollama run <model>'` — replace `<model>` with the model from the agent string (e.g. `ollama:qwen2.5-coder` → `qwen2.5-coder`)
   - **Custom**: If `agentCommands` defines a command for this agent, use it with `{file}` replaced by `$PLAN_REVIEW_FILE` and `{model}` replaced by the model name
   - If the agent call times out or fails, try the next agent in the list. If all fail, note the failure and continue to the checkpoint.
6. Clean up: `rm -f $PLAN_REVIEW_FILE` — **always run this**, even if the agent call failed or timed out, to avoid leaving prompt content on disk.
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

Run QC commands based on project type (or config overrides):

| Type | Commands |
|---|---|
| Node.js | `npm test`, `npx playwright test` (if installed), `npm run build` |
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
   `CODE_REVIEW_FILE=$(mktemp /tmp/do-code-review-XXXXXX.md)` then write the prompt content to `$CODE_REVIEW_FILE`
5. Select the agent: use the first available entry from `agents.codeReview` in config, or fall back to the first detected agent.
6. Call the selected agent (same invocation patterns and timeout as Phase 2, using `$CODE_REVIEW_FILE` as the temp file). For **Codex** specifically, you may also try `codex review` as an alternative.
   Clean up after the agent call: `rm -f $CODE_REVIEW_FILE` — **always run this**, even if the agent call failed or timed out, to avoid leaving diff content on disk.
7. Analyze the feedback:
   - Fix **CRITICAL** issues immediately
   - Note **WARNING**s and fix if straightforward
   - Log **SUGGESTION**s but do not necessarily act on all
8. Re-run affected tests after fixes
9. Maximum **2 code review iterations**

---

## Phase 6: PRESENT

Present to the user:

1. **Changes Summary** — files modified/created with brief descriptions
2. **Plan Compliance** — checklist of plan items with completion status
3. **QC Results** — test pass/fail, build status, external review summary
4. **Outstanding Items** — any warnings, suggestions, or follow-up tasks

Ask the user for final approval.
