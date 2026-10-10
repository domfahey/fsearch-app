#!/bin/bash
# Refuses commits and pushes that would publish keys or secrets.
# Install once with `make hooks` (sets core.hooksPath to scripts/hooks).
# Usage: check-secrets.sh <file>... (the hooks run it on a copy of each staged blob or
# pushed commit's blob, in a scratch directory, so the check sees what would be committed)
set -u
fail=0
for f in "$@"; do
  [ -f "$f" ] || continue
  [ "$f" = scripts/hooks/check-secrets.sh ] && continue  # holds the patterns themselves
  case "$f" in
    *.p12|*.p8|*.pem|*.key|*.cer|*.certSigningRequest|*.mobileprovision|*.provisionprofile|*AuthKey_*|*sparkle*private*|*private-key*|.env|.env.*)
      echo "secret check: refusing key or secret file: $f" >&2; fail=1; continue ;;
  esac
  # An EdDSA (Sparkle) private key is 32 bytes: a lone 44-character base64 line.
  lower=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *.key|*eddsa*)
      if grep -Eq '^[[:space:]]*[A-Za-z0-9+/]{43}=[[:space:]]*$' "$f"; then
        echo "secret check: $f holds a 44-character base64 line that looks like an EdDSA private key" >&2; fail=1; continue
      fi ;;
  esac
  if grep -IqE -- '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|gh[opsu]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN OPENSSH PRIVATE KEY-----' "$f"; then
    echo "secret check: $f contains something that looks like a private key or token" >&2; fail=1
  fi
done
exit $fail
