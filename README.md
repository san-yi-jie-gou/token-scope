# TokenScope

TokenScope is a small native macOS desktop panel that aggregates local token usage from:

- Codex: `~/.codex/sessions/`
- Claude Code and CC Switch: `~/.claude/projects/`
- Kimi Code: `~/.kimi-code/sessions/**/agents/*/wire.jsonl`
- Oh My Pi: `~/.pi/agent/sessions/`
- OpenCode: `~/.local/share/opencode/storage/session/` plus active-session messages
- Gemini CLI: `~/.gemini/tmp/**/chats/`
- GitHub Copilot: `~/.copilot/` and VS Code Copilot chat storage
- Cursor: `~/Library/Application Support/Cursor/User/globalStorage/`
- Qoder: `~/.qoder/` and Qoder app storage
- Windsurf: `~/Library/Application Support/Windsurf/User/globalStorage/`
- Cline: VS Code Cline extension storage
- Trae: `~/Library/Application Support/Trae/User/globalStorage/`

It reads only usage metadata. Prompt text, model responses, OAuth data, API keys, and provider configuration are not persisted or displayed.

The Mac App Store build runs in the App Sandbox. On first launch, select your personal home directory once so TokenScope can read the supported agent folders. The permission is stored as an app-scoped security bookmark and can be changed later from the menu bar icon's right-click menu.

## Behavior

- Shows today or current-month totals, with a per-day usage chart in the month view.
- The month chart defaults to input plus output tokens and can include cache tokens on demand.
- Includes native small and medium WidgetKit widgets for the desktop and Notification Center.
- Detects supported agents from their local data directories and only shows agents active in the selected period.
- Separates input, output, and cache tokens.
- Refreshes every five minutes and on demand.
- Lives behind desktop icons by default and remembers its position.
- Can float over windows from the menu bar.
- Can register itself as a login item after being installed as an app.

The system widget reads only aggregate usage from the main app over a localhost-only bridge. Keep TokenScope running (or enable login startup) so the widget remains current. No prompt text, model output, or account configuration is transmitted.

Codex cumulative counters are converted to deltas. Claude Code streaming duplicates are deduplicated by message id. Kimi Code counts only `usage.record` entries with `usageScope: turn`. Copilot, Cursor, Qoder, Windsurf, Cline, and Trae use best-effort local JSON/JSONL usage extraction and only count records with explicit token usage fields.

## Build

Requirements: macOS 14+, Xcode 16+, and XcodeGen.

```bash
make test
make run
```

To install locally, build Release in Xcode and move `TokenScope.app` to `/Applications`.
