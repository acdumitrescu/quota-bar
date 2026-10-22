# Security

Please report vulnerabilities privately through GitHub: **Security → Report a vulnerability** on this repository (a private security advisory). Don't open a public issue for security problems.

Areas that matter most:

- Any way an API key or the Claude Code token could reach a host other than its provider, a log, or a file.
- Requests that bypass `HTTPClient`'s host allowlist.
- Parsing bugs triggered by a malicious provider response.

Never paste real API keys into issues, pull requests or test fixtures.
