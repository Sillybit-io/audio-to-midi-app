#!/bin/zsh
# Publish gate: greps the working tree and the tree of every commit on main for tokens, private keys,
# home-directory paths and personal addresses. Prints every hit and exits 1, or prints "sweep: clean".
# Agent-skill folders are judged by the secret-and-privacy-sweep skill instead. Third-party licence
# texts keep their authors' contact addresses, so the address pattern skips them.
set -uo pipefail
cd "${0:A:h:h}"

secrets='hf_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|/Users/[a-zA-Z]'
emails='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.(com|net|org)'
skip=(':!.agents' ':!.claude' ':!agent')
skip_notices=(':!THIRD_PARTY_NOTICES.md' ':!App/Resources/Licenses' ':!LICENSE')

found=0
scan() {
  local rev="$1"
  local out
  if [[ -z "$rev" ]]; then
    out="$(git grep -nIE "$secrets" -- . $skip; git grep -nIE "$emails" -- . $skip $skip_notices)"
  else
    out="$(git grep -nIE "$secrets" "$rev" -- . $skip; git grep -nIE "$emails" "$rev" -- . $skip $skip_notices)"
  fi
  if [[ -n "$out" ]]; then
    print -r -- "${rev:-working tree}:"
    print -r -- "$out" | cut -c1-200
    found=1
  fi
}

scan ""
for rev in $(git rev-list main); do scan "$rev"; done

# Commit metadata: only the GitHub noreply address may appear.
authors="$(git log --format='%ae%n%ce' | sort -u | grep -v 'users.noreply.github.com' || true)"
if [[ -n "$authors" ]]; then print -r -- "commit metadata:"; print -r -- "$authors"; found=1; fi

if (( found )); then exit 1; fi
echo "sweep: clean"
