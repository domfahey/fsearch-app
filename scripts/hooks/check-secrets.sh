#!/bin/bash
# Refuses commits and pushes that would publish keys or secrets.
# Install once with `make hooks` (sets core.hooksPath to scripts/hooks).
# Usage: check-secrets.sh <file>... (pre-commit passes the staged files)
set -u
fail=0
for f in "$@"; do
  [ -f "$f" ] || continue
  [ "$f" = scripts/hooks/check-secrets.sh ] && continue  # holds the patterns themselves
  case "$f" in
    *.p12|*.p8|*.pem|*.key|*.cer|*.certSigningRequest|*.mobileprovision|*.provisionprofile|*AuthKey_*|*sparkle*private*|*private-key*|.env|.env.*)
      echo "secret check: refusing key or secret file: $f" >&2; fail=1; continue ;;
  esac
  if grep -IqE -- '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN OPENSSH PRIVATE KEY-----' "$f"; then
    echo "secret check: $f contains something that looks like a private key or token" >&2; fail=1
  fi
done
exit $fail
