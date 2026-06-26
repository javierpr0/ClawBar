#!/bin/bash
# Cut a release: bump VERSION, commit, tag, push. CI (.github/workflows/release.yml)
# then builds ClawBar.app and publishes the GitHub Release.
#   ./release.sh 1.0.1
set -e
cd "$(dirname "$0")"

V="${1#v}"
[ -z "$V" ] && { echo "uso: ./release.sh <version>   (ej: ./release.sh 1.0.1)"; exit 1; }
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "version invalida: '$V' (usa X.Y.Z)"; exit 1; }
TAG="v$V"

[ -n "$(git status --porcelain)" ] && { echo "el arbol git tiene cambios sin commitear; limpia primero"; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "el tag $TAG ya existe"; exit 1; }

REMOTE=$(git remote | head -1)
BRANCH=$(git branch --show-current)
[ -z "$REMOTE" ] && { echo "no hay remote configurado"; exit 1; }

# keep the source VERSION in sync with the tag (skip the commit if already at $V)
sed -i '' "s/let VERSION = \".*\"/let VERSION = \"$V\"/" Sources/clawbar/Core.swift
if git diff --quiet Sources/clawbar/Core.swift; then
  echo "VERSION ya es $V; taggeo el HEAD actual"
else
  git add Sources/clawbar/Core.swift
  git commit -m "chore: release $TAG"
fi
git tag "$TAG"

git push "$REMOTE" "$BRANCH"
git push "$REMOTE" "$TAG"
echo "release $TAG disparado -> https://github.com/javierpr0/ClawBar/actions"
