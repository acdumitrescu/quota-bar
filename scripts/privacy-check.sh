#!/bin/bash
# Fails if the repository (files or git history) contains anything that could identify a person or leak a secret.
# Optional: put extra forbidden terms (one per line, e.g. your real name) in .privacy-denylist. That file is gitignored.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
report() { printf 'privacy-check: %b\n' "$1" >&2; fail=1; }

files=$(git ls-files --cached --others --exclude-standard | grep -v '^scripts/privacy-check.sh$')

# 1. Absolute home paths.
hits=$(echo "$files" | xargs grep -nE '/Users/[A-Za-z0-9._-]+/' 2>/dev/null)
[ -n "$hits" ] && report "home-directory paths found:\n$hits"

# 2. Email addresses other than GitHub noreply / example domains.
hits=$(echo "$files" | xargs grep -noE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 2>/dev/null \
  | grep -vE '@(users\.)?noreply\.github\.com|@example\.(com|org)')
[ -n "$hits" ] && report "email addresses found:\n$hits"

# 3. Things that look like real API keys.
hits=$(echo "$files" | xargs grep -nE 'sk-[A-Za-z0-9_-]{24,}|sk-ant-[A-Za-z0-9_-]{16,}|sk-or-v1-[a-f0-9]{16,}' 2>/dev/null)
[ -n "$hits" ] && report "possible API keys found:\n$hits"

# 4. Network hosts in source code must be on the allowlist.
allowed='^https://(api\.anthropic\.com|api\.deepseek\.com|openrouter\.ai|api\.openai\.com|www\.apple\.com)$'
hosts=$(grep -rhoE 'https://[A-Za-z0-9.-]+' Sources | sort -u | grep -vE "$allowed")
[ -n "$hosts" ] && report "hosts not on the allowlist in Sources/:\n$hosts"

# 5. Git authors and committers must use noreply addresses.
if git rev-parse HEAD >/dev/null 2>&1; then
  bad=$(git log --format='%ae%n%ce' | sort -u | grep -vE '@(users\.)?noreply\.(github\.com|anthropic\.com)$')
  [ -n "$bad" ] && report "commits with non-noreply emails:\n$bad"
fi

# 6. Personal denylist (not committed).
if [ -f .privacy-denylist ]; then
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    hits=$(echo "$files" | xargs grep -nliF -- "$term" 2>/dev/null)
    [ -n "$hits" ] && report "denylisted term found in:\n$hits"
    if git rev-parse HEAD >/dev/null 2>&1 && git log --format='%an%n%cn%n%B' | grep -qiF -- "$term"; then
      report "denylisted term found in git history"
    fi
  done < .privacy-denylist
fi

[ "$fail" -eq 0 ] && echo "privacy-check: OK"
exit "$fail"
