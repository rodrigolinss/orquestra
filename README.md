<p align="center">
  <a href="https://nevoaai.com/?utm_source=orquestra&utm_medium=readme&utm_campaign=opensource_orchestrator">
    <img src="docs/logo.png" width="110" alt="Orquestra">
  </a>
</p>

<h1 align="center">Orquestra</h1>

<p align="center">
  <strong>Run a team of AI coding agents on your Mac — isolated, supervised, and safe by design.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-black?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/agents-Claude%20Code%20%C2%B7%20Codex-CCFF00" alt="Agents">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
  <img src="https://img.shields.io/badge/built%20with-SwiftUI%20%2B%20Bash-orange" alt="Stack">
</p>

<p align="center">
  <a href="#installation">Installation</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#security-model">Security</a> ·
  <a href="#architecture">Architecture</a>
</p>

---

Orquestra turns your machine into a supervised AI engineering team. A **maestro** agent takes your instructions in plain language and recruits worker agents — each one locked inside its own git worktree and branch, watched by a deterministic command firewall, and merged back **only** with your explicit, typed approval.

No copy-pasting between terminals. No agent ever touching your main branch. No "oops" moments.

```
                    ┌─────────────┐
                    │   MAESTRO   │  ← you talk to it in plain language
                    └──────┬──────┘
             ┌─────────────┼─────────────┐
        ┌────┴────┐   ┌────┴────┐   ┌────┴────┐
        │ builder │   │reviewer │   │  docs   │  ← each in its own worktree,
        └─────────┘   └─────────┘   └─────────┘     branch agent/<name>
                  shared notes = progress protocol
```

## Why Orquestra

Running 3–4 AI agents in loose terminals turns you into a copy-paste router. Orquestra fixes that with three architectural decisions:

| | Decision | Result |
|---|---|---|
| 🗂 | **Isolation lives in the filesystem, not the prompt** | Each agent only sees its own worktree. A confused agent can't break another agent's work — or your main branch. |
| 🛡 | **Deterministic guardrails** | A `PreToolUse` hook blocks destructive commands *before* they run. It doesn't depend on the model having a good day. |
| ✍️ | **Merging is a human decision** | `nvo done` shows the full diff and requires you to type the agent's name. There is no auto-merge. Ever. |

## Features

- **Native macOS app** — visual canvas with the maestro on top and live agent cards wired below it. Status, terminal output, notes, and diffs at a glance.
- **Works with Claude Code and Codex** — pick the harness per agent. Mixed teams (Claude builder + Codex reviewer) work out of the box.
- **Zero-credential setup** — the installer detects what you already have. Claude/Codex already logged in? Git already configured? Orquestra just uses it.
- **GitHub-ready** — open a local folder or paste `user/repo` and Orquestra clones and registers it. Private repos work with your existing git credentials.
- **Shared notes protocol** — agents report progress, decisions, and blockers to markdown notes. When one writes `STATUS: CONCLUIDO` or `BLOQUEADO`, you get a native macOS notification.
- **Built-in file inspector** — an optional sidebar (closed by default) to browse any agent's worktree and inspect recently modified files without leaving the app.
- **Live token metering** — a status strip shows your current 5-hour session window (tokens, estimated API-equivalent value, reset time), today's total, and the model mix. Also available as `nvo usage`.
- **Per-agent model selection** — run workers on Sonnet or Haiku for a fraction of Opus cost, straight from the new-agent dialog or `nvo new <name> "<task>" claude sonnet`.
- **Nothing to babysit** — no daemon, no database. State is the filesystem; kill tmux and nothing is lost.

## Installation

**Requirements:** macOS with [Homebrew](https://brew.sh). At least one agent CLI ([Claude Code](https://docs.anthropic.com/en/docs/claude-code) or [Codex](https://github.com/openai/codex)) installed and logged in.

```bash
git clone https://github.com/rodrigolinss/orquestra.git ~/orquestra
cd ~/orquestra && ./install.sh
```

The installer is idempotent and only fills the gaps: installs `tmux`/`jq` if missing, wires the security hook, adds the CLI to your `PATH`, and builds the native app when Xcode Command Line Tools are present. It ends with a full environment diagnosis:

```
nvo doctor — environment check
  ✓ tmux 3.7b
  ✓ git 2.50 · identity configured
  ✓ Claude Code installed — existing login will be used
  ✓ Codex CLI installed
  ✓ security hook configured
  ✓ Orquestra.app installed
ready to orchestrate.
```

## Usage

### The app

Open **Orquestra** (Spotlight → "Orquestra"). Pick a project — a local folder or a GitHub repo — then start the maestro and tell it what you want:

> *"create a builder agent to implement the payment webhook from docs/webhook.md, and a reviewer to audit it. Let me know when both finish."*

Each agent appears as a live card wired to the maestro: status, terminal output, direct prompt field, notes, and diff. When an agent finishes or gets stuck, macOS notifies you.

### The CLI

Everything the app does, scriptable:

```bash
nvo init ~/projects/my-api          # register the active project
nvo new builder "implement X"       # branch + worktree + tmux window + agent
nvo new reviewer "audit it" codex   # same, but running on Codex
nvo ls                              # overview of every agent
nvo read builder 60                 # peek at an agent's screen, non-intrusive
nvo send builder "prioritize retry" # send a prompt
nvo note builder                    # read its progress notes
nvo diff builder                    # review its work against the base branch
nvo done builder                    # diff → typed confirmation → merge --no-ff
nvo kill reviewer                   # discard without merge (branch preserved)
nvo attach                          # watch everything live in tmux
nvo doctor                          # environment diagnosis
nvo usage                           # token consumption: 5h window, day, models
```

### Token efficiency

Orquestra is designed to keep supervision cheap and spend visible:

1. **Meter first** — the usage strip (or `nvo usage`) shows the 5-hour window and reset time, so you know your headroom before launching a team.
2. **Right-size the model** — builders and reviewers rarely need the top model. Sonnet delivers most coding tasks at ~40% of Opus cost; Haiku handles mechanical work at ~20%.
3. **Closed tasks burn less** — a scoped task ("implement X per docs/x.md, with tests") finishes in far fewer tokens than an open one ("improve the backend").
4. **Notes over screens** — the maestro reads agent notes instead of re-reading terminal scrollback, keeping its own context small.

## Security model

Orquestra assumes agents *will* misbehave eventually, and makes that survivable:

| Layer | Enforcement |
|---|---|
| **Worktree isolation** | Agents never run on the main branch. Worktrees outside `~/orquestra/worktrees` are rejected. |
| **Command firewall** (`guard.sh`) | Blocks before execution: `rm -rf` on absolute/home paths, `sudo`, `git push`, `git reset --hard`, checkout/switch to main/master, `curl\|sh` pipes, `chmod 777`, and any access to `.env*`, `*.pem`, `id_rsa`, `~/.ssh`, `~/.aws`. |
| **Human-gated merge** | `nvo done` requires typing the agent's name in a real terminal. The app deliberately has no merge button. |
| **Standard permissions** | Agent permission prompts are never bypassed. `--dangerously-skip-permissions` is not used anywhere in the codebase. |

The firewall hook ships to every worktree automatically (as `.claude/settings.local.json`, git-ignored), so agents carry their guardrails with them.

**Privacy:** the repository versions code only. Your worktrees, notes, cloned repos, and project registration are excluded by `.gitignore` and never leave your machine.

## Architecture

```
~/orquestra/
├── bin/nvo                  CLI — the single source of action (~450 lines of bash)
├── bin/guard.sh             deterministic command firewall (PreToolUse hook)
├── app/main.swift           native macOS app (SwiftUI, single file)
├── app/build.sh             one-command rebuild
├── .claude/settings.json    maestro's security hook
├── install.sh               idempotent installer with environment detection
└── runtime (git-ignored)
    ├── worktrees/<project>/<agent>/    isolated working copy per agent
    ├── notes/<project>/<agent>.md      progress protocol
    └── repos/                          GitHub clones
```

**Design principles**

1. **The CLI is the only source of action.** Every button in the app shells out to `nvo` — there is no second code path to audit.
2. **Notes are the protocol.** Agents write structured progress to markdown; status, notifications, and supervision all derive from it.
3. **State is the filesystem.** No daemon, no database, no lock-in. Everything is inspectable with `ls` and `git`.

## Development

```bash
bash app/build.sh                        # rebuild the app after editing main.swift
NVO_AGENT_CMD=bash nvo new t "..."       # spawn a plain shell instead of an agent (testing)
swift app/gen_icon.swift out.png         # regenerate the icon assets
```

## License

[MIT](LICENSE) © 2026 [Nevoa AI](https://nevoaai.com/?utm_source=orquestra&utm_medium=readme&utm_campaign=opensource_orchestrator)

<p align="center">
  <a href="https://nevoaai.com/?utm_source=orquestra&utm_medium=readme_footer&utm_campaign=opensource_orchestrator">
    <img src="https://img.shields.io/badge/powered%20by-nevoaai.com-CCFF00?labelColor=09090B" alt="powered by nevoaai.com">
  </a>
</p>
