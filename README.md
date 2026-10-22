# Quota

**Your AI usage limits in the macOS menu bar. Local-first, no accounts, no telemetry.**

Quota shows how much of your AI plans and API credits you've used: Claude's 5-hour and weekly limits, Claude Code tokens, and balances or spend for DeepSeek, OpenRouter and OpenAI. Everything runs on your Mac. Quota only talks to the providers you turn on.

## Providers

| Provider | Shows | Needs | Network |
|---|---|---|---|
| **Claude subscription** *(unofficial)* | Session (5h) and weekly limits, reset times, weekly split by app | Claude Code installed and logged in | `api.anthropic.com` |
| **Claude Code** | Tokens today / 7 days / 30 days, by model | Claude Code transcripts in `~/.claude/projects` | none |
| **DeepSeek** | Balance; usage worked out from balance changes | API key | `api.deepseek.com` |
| **OpenRouter** | Credits used today / week / month, key limit, free-model requests | API key | `openrouter.ai` |
| **OpenAI** | Organization tokens, requests and cost (today / month) | Admin key (`sk-admin-…`) from an org owner | `api.openai.com` |

Every provider is **off by default**.

**About "unofficial":** the Claude subscription numbers come from the same endpoint Claude Code's `/usage` uses. Anthropic doesn't document it, so it can change or stop working at any time. Quota reads Claude Code's existing login **read-only**. It never refreshes, copies or stores the token. If the login has expired, use Claude Code once and Quota picks it up again.

**DeepSeek** only reports the current balance. Quota records the balance at each refresh and counts drops as usage (top-ups are ignored), so usage counts from when you turn it on and only while Quota is running.

## Privacy

- No analytics, telemetry, crash reporting, update checks or accounts.
- API keys are stored only in the macOS Keychain, on this Mac only (no iCloud sync).
- Network requests go only to the hosts in the table above. This is enforced in code by an allowlist (`HTTPClient.allowedHosts`) and in CI by `scripts/privacy-check.sh`.
- History is a local SQLite file (`~/Library/Application Support/Quota/history.sqlite`). Turn it off, export it as CSV, or delete everything from Settings → Privacy.

More detail in [PRIVACY.md](PRIVACY.md).

## Install

Requires macOS 14 or later.

### Build from source (recommended)

```sh
git clone https://github.com/<you>/quota-bar.git
cd quota-bar
scripts/build-app.sh --install
```

This needs Xcode 16 or later (or the matching command line tools).

### Download a release

Release builds are ad-hoc signed, not notarized: notarizing requires an Apple Developer ID, which publishes the developer's legal name. After unzipping, right-click `Quota.app` → **Open** the first time, or run:

```sh
xattr -dr com.apple.quarantine Quota.app
```

Each release lists SHA-256 checksums. Compare them before opening.

## Command line

`scripts/build-app.sh` also builds `build/quota`:

```sh
quota                       # Claude subscription, Claude Code, and any provider with a key
quota openrouter --json     # one provider, as JSON
QUOTA_OPENROUTER_KEY=… quota openrouter
```

Keys are read from `QUOTA_<PROVIDER>_KEY` environment variables first, then the Keychain.

## Development

```sh
swift test                 # parsers, history, allowlist (all fixtures are made-up data)
swift run QuotaApp         # run without bundling (notifications are disabled outside a .app)
scripts/privacy-check.sh   # run before every commit
```

The code is split into `Sources/QuotaCore` (providers, Keychain, HTTP allowlist, history; no UI), `Sources/QuotaApp` (SwiftUI menu bar app) and `Sources/quota-cli`. Adding a provider means implementing `UsageProvider` and adding a case to `ProviderID`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. Not affiliated with Anthropic, DeepSeek, OpenRouter or OpenAI.
