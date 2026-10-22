# Privacy

Quota is built to know as little as possible and to keep what it knows on your Mac.

## What Quota stores

| Data | Where | Removed by |
|---|---|---|
| API keys you paste | macOS login Keychain, service `quota.api-keys`, `ThisDeviceOnly` (not synced to iCloud) | Settings → Providers → Remove, or Settings → Privacy → Delete all |
| Preferences (enabled providers, refresh interval, alert thresholds) | `UserDefaults` for the app's bundle ID | Delete all |
| Usage history (timestamp, metric name, number) | `~/Library/Application Support/Quota/history.sqlite`, rows older than 35 days are pruned | Turn off history, or Delete all |
| Which alerts already fired | `UserDefaults` | Delete all |

No prompts, conversations, file contents, model outputs or account identifiers are stored. The Claude Code provider reads only the `usage`, `model`, `id` and `timestamp` fields of transcript lines, and keeps the counts in memory.

## What Quota reads but never stores

- **Claude Code's login** (for the Claude subscription provider): read with `/usr/bin/security` from the `Claude Code-credentials` Keychain item, or from `~/.claude/.credentials.json`. The access token is sent only to `api.anthropic.com`. It's never written anywhere, logged, refreshed or modified.
- **Claude Code transcripts** in `~/.claude/projects` (or `$CLAUDE_CONFIG_DIR/projects`).

## Network

Quota makes HTTPS GET requests only to the providers you turn on:

- `api.anthropic.com/api/oauth/usage`
- `api.deepseek.com/user/balance`
- `openrouter.ai/api/v1/key`
- `api.openai.com/v1/organization/usage/completions` and `/v1/organization/costs`

Requests use an ephemeral session with no cookies and no cache, plus a generic `User-Agent: Quota/<version>`. Requests to any other host are refused in code (`HTTPClient`). There is no update check, analytics or crash reporting.

## Verifying

- `scripts/privacy-check.sh` fails the build if source code references a host outside the allowlist, or if the repository contains home-directory paths, email addresses or key-like strings.
- Watch traffic yourself with `nettop -p Quota` or a firewall such as Little Snitch or LuLu.
