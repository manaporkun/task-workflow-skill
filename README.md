# /do — Structured Task Workflow

[![Test](https://github.com/manaporkun/claude-plugins/actions/workflows/test.yml/badge.svg)](https://github.com/manaporkun/claude-plugins/actions/workflows/test.yml)
[![Release](https://github.com/manaporkun/claude-plugins/actions/workflows/release.yml/badge.svg)](https://github.com/manaporkun/claude-plugins/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/github/v/release/manaporkun/claude-plugins)](https://github.com/manaporkun/claude-plugins/releases)

A Claude Code skill that turns any task into a systematic, quality-controlled workflow with external agent review.

**Plan** an implementation, get it **reviewed by another AI agent**, get your **approval**, **implement** with subagents, run **automated QC**, then **present** the results.

## Quick Start

```
/do Add a dark mode toggle to the settings page
```

That's it. The skill auto-detects your project type and any available review agents. No configuration needed.

To resume an interrupted workflow from a saved plan:

```
/do --continue
```

## How It Works

| Phase | What happens |
|---|---|
| **1. Plan** | Claude researches the codebase and creates a step-by-step implementation plan with a complexity estimate |
| **2. Analyze** | An external agent (Gemini, Codex, Claude, etc.) independently reviews the plan |
| **3. Approve** | You review the plan + feedback and approve, reject, or request changes |
| **4. Implement** | Auto-creates a `do/<task-slug>` git branch, then spawns subagents to implement the approved plan |
| **5. QC** | Automated tests/builds run, then an external agent reviews the diff — safe suggestions are auto-applied, risky ones are surfaced for review |
| **6. Present** | Summary of changes, branch name, QC results, and outstanding items for final approval |

## Supported Agents

The skill can use any of these agents for plan and code review. All are optional — the skill detects what's available and falls back gracefully.

| Agent | Install | Type | Detection |
|---|---|---|---|
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `npm i -g @google/gemini-cli` | Cloud | `which gemini` |
| [Codex CLI](https://github.com/openai/codex-cli) | `brew install codex` | Cloud | `which codex` |
| [Ollama](https://ollama.com) | `brew install ollama` | Local | `which ollama` |
| [OpenRouter](https://openrouter.ai/) | Set `OPENROUTER_API_KEY` | Cloud | env var |
| [Claude Code](https://claude.com/claude-code) | `npm i -g @anthropic-ai/claude-code` | Cloud | `which claude` |
| [Aider](https://aider.chat) | `pip install aider-chat` | Cloud/Local | `which aider` |
| OpenAI-compatible | Set `OPENAI_API_KEY` | Cloud/Local | env var |
| GitHub Copilot | Set `GITHUB_TOKEN` or `GH_TOKEN` | Cloud | env var |

Agent availability is cached at `~/.claude/do-env.json`. To force re-detection:

```
/do --refresh-env <task description>
```

## Configuration Commands

Manage `.claude/do-config.json` without editing it manually:

```
/do config                              # show current config
/do config set provider copilot        # use Copilot for both plan and code review
/do config set provider copilot,gemini # Copilot with Gemini as fallback
/do config set plan gemini             # plan review only
/do config set code copilot:gpt-4o    # code review only, specific model
/do config set model gpt-4.1           # update model on all API providers
/do config set qc test "npm test"      # add/replace a QC command
/do config unset provider              # revert to auto-detection
/do config reset                       # delete the config file
/do config refresh                     # clear agent detection cache
```

Both `:` and `/` work as the model separator — `copilot:gpt-4o` and `copilot/gpt-4o` are equivalent.

## Flags

| Flag | Description |
|---|---|
| `--continue` | Resume from a saved plan in `.claude/plans/`. Skips planning and jumps straight to approval. |
| `--refresh-env` | Clear the agent detection cache and re-detect available agents before running. |

## Installation

### Plugin marketplace

```
/plugin marketplace add manaporkun/claude-plugins
/plugin install task
/reload-plugins
```

The skill is available as `/task:do`.

### Symlink installer

```bash
git clone https://github.com/manaporkun/claude-plugins.git
cd claude-plugins && ./plugins/task/install.sh
```

Creates a symlink so `git pull` updates take effect immediately. The skill is available as `/do`.

### Other options

- **Direct loading**: `claude --plugin-dir ./plugins/task`
- **Manual copy**: Copy `plugins/task/skills/do/` into `~/.claude/skills/` (user-wide) or `.claude/skills/` (project-scoped)

## Configuration

The skill works out of the box with zero configuration. For advanced control, create `.claude/do-config.json` in your project root.

### Agent routing

Control which agent reviews each phase:

```json
{
  "agents": {
    "planReview": ["ollama:qwen2.5-coder", "gemini"],
    "codeReview": ["gemini", "codex"]
  }
}
```

Each entry is an ordered fallback list — the skill tries the first available agent, then the next.

**Agent format:**

| Format | Example | Description |
|---|---|---|
| `"gemini"` | | Gemini CLI |
| `"codex"` | | Codex CLI |
| `"claude"` | | Claude Code headless mode |
| `"aider"` | | Aider dry-run review |
| `"ollama:<model>"` | `"ollama:qwen2.5-coder"` | Ollama with a specific model |
| `"openrouter:<model>"` | `"openrouter:anthropic/claude-sonnet-4"` | OpenRouter with a specific model |
| `"openai:<model>"` | `"openai:gpt-4.1-mini"` | Any OpenAI-compatible API |
| `"copilot"` | | GitHub Copilot (requires `GITHUB_TOKEN` or `GH_TOKEN`) |
| `"copilot:<model>"` | `"copilot:claude-sonnet-4-5"` | GitHub Copilot with a specific model |

Agents without `:<model>` use their default model. `openrouter` defaults to `google/gemini-3.1-pro-preview`, `openai` defaults to `gpt-5.4`, `copilot` defaults to `gpt-4o`. Both `:` and `/` are accepted as the model separator.

### QC commands

Override auto-detected test/build/lint commands:

```json
{
  "qc": {
    "test": "npm test",
    "build": "npm run build",
    "lint": "eslint ."
  }
}
```

### All config fields

| Field | Type | Default | Description |
|---|---|---|---|
| `configVersion` | number | `1` | Schema version for forward compatibility |
| `agents.planReview` | string[] | auto-detect | Ordered agent list for plan review |
| `agents.codeReview` | string[] | auto-detect | Ordered agent list for code review |
| `agentCommands` | object | built-in | Custom shell commands per agent (`{file}` = prompt path, `{model}` = model name) |
| `qc.test` | string | auto | Test command |
| `qc.build` | string | auto | Build command |
| `qc.lint` | string | auto | Lint command |
| `maxIterations` | number | `3` | Max QC fix iterations per failing command |
| `maxCodeReviewIterations` | number | `2` | Max external code review rounds |
| `skipReviewThreshold` | object | `{"maxFiles":1,"maxSteps":2}` | Skip external plan review for small plans |

> **Security note**: Custom `agentCommands` execute directly in your shell. Only use this field in projects you trust — a malicious `.claude/do-config.json` in a cloned repo could run arbitrary commands when `/do` is invoked.

## Supported Project Types

Auto-detection for: **Node.js** (package.json), **iOS/macOS** (Podfile, *.xcodeproj), **Python** (pyproject.toml, requirements.txt), **Go** (go.mod), **Rust** (Cargo.toml). For other project types, specify QC commands in config.

## Privacy

When using cloud-based agents, the skill sends your implementation plans and code diffs to those external services for review. For sensitive codebases, use a local agent like Ollama or Aider with a local model.

## File Structure

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace catalog
├── plugins/
│   └── task/
│       ├── .claude-plugin/
│       │   └── plugin.json       # Plugin manifest
│       ├── skills/do/
│       │   ├── SKILL.md          # Workflow orchestrator
│       │   ├── prompts/
│       │   │   ├── plan-review.md
│       │   │   └── code-review.md
│       │   └── scripts/
│       │       ├── openrouter.sh
│       │       ├── openai-compatible.sh
│       │       └── copilot.sh
│       └── install.sh            # Symlink installer
├── CHANGELOG.md
└── LICENSE
```

## Troubleshooting

**Agent not detected**: Run `/do --refresh-env <task>` or delete `~/.claude/do-env.json`.

**OpenRouter/OpenAI not working**: Verify env vars are set (`echo $OPENROUTER_API_KEY`). For non-OpenAI providers, also set `OPENAI_BASE_URL` or `OPENAI_COMPATIBLE_BASE_URL`.

**GitHub Copilot not working**: Verify `GITHUB_TOKEN` or `GH_TOKEN` is set and the account has an active Copilot subscription. The token must have sufficient scopes to access the Copilot API.

## License

MIT
