# Contributing

Thanks for helping. A few rules keep Quota private and easy to trust.

## Ground rules

1. **No new network destinations** unless they belong to a provider the user turns on. Add the host to `ProviderID.hosts`; the allowlist and `scripts/privacy-check.sh` derive from it.
2. **No telemetry, analytics or third-party SDKs.** Quota has no dependencies beyond Apple frameworks, and that should stay true.
3. **Secrets only through `SecretStore`** (Keychain). Never log, print or persist keys or tokens, and never include response bodies in errors.
4. **Fixtures must be made-up data.** No real responses, account names or keys.
5. Run `swift test` and `scripts/privacy-check.sh` before opening a PR. CI runs both.

## Adding a provider

1. Add a case to `ProviderID` with its display name, summary, hosts and key info.
2. Create `Sources/QuotaCore/Providers/<Name>.swift` implementing `UsageProvider`. Put parsing in a `static func parse(...)` so it can be tested without the network.
3. Register it in `ProviderRegistry.defaults()`.
4. Add parser tests in `Tests/QuotaCoreTests`.
5. Document it in the README table and PRIVACY.md.

## Commits

Use your GitHub noreply address (`git config user.email <id>+<handle>@users.noreply.github.com`) if you don't want your personal email in the public history.
