#!/bin/bash
# Cut a release: bump VERSION, commit, tag, push. CI (.github/workflows/release.yml)
# builds ClawBar.app and publishes the GitHub Release.
#   ./release.sh 1.0.1
#   ./release.sh 1.0.0 --force   # overwrite an existing tag/release (only if nobody pulled it)
set -e
cd "$(dirname "$0")"

V=""; FORCE=0
for a in "$@"; do
  case "$a" in
    --force|-f) FORCE=1 ;;
    *) [ -z "$V" ] && V="${a#v}" ;;
  esac
done
[ -z "$V" ] && { echo "uso: ./release.sh <version> [--force]   (ej: ./release.sh 1.0.1)"; exit 1; }
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "version invalida: '$V' (usa X.Y.Z)"; exit 1; }
TAG="v$V"

[ -n "$(git status --porcelain)" ] && { echo "el arbol git tiene cambios sin commitear; limpia primero"; exit 1; }

REMOTE=$(git remote | head -1)
BRANCH=$(git branch --show-current)
[ -z "$REMOTE" ] && { echo "no hay remote configurado"; exit 1; }
REPO=$(git remote get-url "$REMOTE" | sed -E 's#.*github.com[:/]+([^/]+/[^/.]+)(\.git)?.*#\1#')

tag_exists() {
  git rev-parse "$TAG" >/dev/null 2>&1 || git ls-remote --tags "$REMOTE" 2>/dev/null | grep -q "refs/tags/$TAG$"
}

if tag_exists; then
  if [ "$FORCE" != 1 ]; then
    echo "el tag $TAG ya existe (usa --force para sobrescribirlo si nadie lo descargo)"; exit 1
  fi
  echo "FORCE: borrando release y tag $TAG (destructivo, solo seguro si nadie lo bajo) ..."
  command -v gh >/dev/null 2>&1 && gh release delete "$TAG" -R "$REPO" --yes 2>/dev/null || true
  git push "$REMOTE" ":refs/tags/$TAG" 2>/dev/null || true
  git tag -d "$TAG" 2>/dev/null || true
fi

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
echo "release $TAG disparado -> https://github.com/$REPO/actions"
