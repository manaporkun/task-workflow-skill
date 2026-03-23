# Changelog

## [1.4.0] - 2026-03-23

### Added

* **Claude Code headless agent** — Review via `claude -p --bare --output-format text`. Detected via `which claude`.
* **Aider agent** — Review via `aider --dry-run --message-file`. Detected via `which aider`. Works with any LLM Aider supports.
* **OpenAI-compatible API agent** — Generic integration via `scripts/openai-compatible.sh` for any OpenAI-compatible endpoint (OpenAI, Azure, LM Studio, etc.). Detected via `OPENAI_API_KEY` or `OPENAI_COMPATIBLE_API_KEY` env var. Supports model selection with `"openai:<model>"` format (default: `gpt-4o`). Set `OPENAI_BASE_URL` or `OPENAI_COMPATIBLE_BASE_URL` for non-OpenAI providers.

## [1.3.0](https://github.com/manaporkun/task-workflow-skill/compare/v1.2.0...v1.3.0) (2026-03-23)

### Features

* Add test suite, CI, and improve agent timeout reliability ([6678165](https://github.com/manaporkun/task-workflow-skill/commit/6678165dea6365d00092278dfb018cf470c35850))
* **OpenRouter API integration** — Real integration via `scripts/openrouter.sh` using curl and the OpenRouter REST API. Detected via `OPENROUTER_API_KEY` env var instead of a non-existent CLI binary. Supports model selection with `"openrouter:<model>"` format (default: `google/gemini-2.0-flash-001`).

### Bug Fixes

* Bash arithmetic compatibility with set -e in test.sh ([9f1feee](https://github.com/manaporkun/task-workflow-skill/commit/9f1feeeeb4d5d98608c533f5a755b452387af158))

### Removed

* **Antigravity agent** — Removed all references. Google Antigravity is an IDE (not a CLI) and has no headless/non-interactive mode for piping prompts.

## [1.2.0] - 2026-03-23

### Fixed

- **Marketplace recursion risk** — Removed in-repo `.claude-plugin/marketplace.json` and switched docs to use a separate marketplace catalog repository (`manaporkun/claude-plugin-marketplace`) to avoid recursive cache path expansion (`ENAMETOOLONG`) during plugin install.

### Security

- **Trust warning for `agentCommands`** — Added security note in SKILL.md and README warning that custom commands execute in the user's shell. Only use in trusted projects.

- **Phase reference in README** — `agents.codeReview` config field now correctly references Phase 5b (was Phase 4).

### Added

- **`.gitignore`** — Excludes `.claude/plans/` and `.claude/settings.local.json` from version control.
- **`configVersion` field** — Schema version (currently `1`) in `do-config.json` for forward compatibility.
- **`skipReviewThreshold` config field** — Configurable small-plan threshold for skipping external review (default: 1 file, 2 steps).
- **`maxCodeReviewIterations` config field** — Configurable max external code review iterations (default: 2).
- **Installer robustness** — `install.sh` now checks for `~/.claude/` before proceeding.
- **Parallel agent detection** — `which` checks run in a single loop instead of sequential commands.

### Removed

- **Stale development plan** — Removed `.claude/plans/do-skill-portability-improvements.md` from the repository.

## [1.1.1] - 2026-03-22

### Fixed

- **Phase numbering consistency** — Promoted Approve to its own Phase 3 and renumbered all phases 1-6, matching README documentation.
- **BUILD vs IMPLEMENT naming** — README diagram now says "IMPL" to match SKILL.md phase naming.
- **Missing `requirements.txt` in project detection** — Python projects using `requirements.txt` are now detected alongside `pyproject.toml`.
- **Temp file cleanup on failure** — Cleanup instructions now explicitly require running even if the agent call failed or timed out.

### Added

- **Config validation** — `do-config.json` is now validated for correct shape before use; malformed config falls back to auto-detection with a warning.
- **`$CLAUDE_SKILL_DIR` documentation** — Inline note explaining the variable is injected by Claude Code at runtime.
- **Privacy note** — README now warns that cloud agents (Gemini, Codex) receive plan and diff content.

## [1.1.0] - 2026-03-22

### Security

- **Fix command injection in Codex invocation** — Replaced `codex exec "$(cat ...)"` with stdin-piped `cat ... | codex exec -q -` to prevent shell metacharacter expansion from prompt contents.
- **Scope `git add -N` to plan-relevant files** — Phase 4b no longer runs `git add -N .`, which could expose unrelated files (`.env`, credentials) in diffs sent to external agents.
- **Use `mktemp` for temp files** — Plan-review and code-review temp files now use randomized names via `mktemp` instead of predictable paths, with cleanup after use.

### Added

- **Input validation** — The skill now rejects empty `/do` invocations with a usage message instead of proceeding with no task.
- **Large diff truncation** — Phase 4b truncates diffs exceeding 15,000 lines to the most relevant files and notes the truncation in the review prompt.
- **Version field** in `plugin.json` for future plugin ecosystem compatibility.

## [1.0.0] - 2026-03-21

### Added

- Initial release: structured `/do` workflow with 6 phases (Plan, Analyze, Approve, Implement, QC, Present).
- Cached environment detection for Gemini, Codex, and Ollama agents.
- Per-phase agent routing via `.claude/do-config.json`.
- Prompt templates for plan review and code review.
- Symlink installer and Claude Code plugin manifest.
