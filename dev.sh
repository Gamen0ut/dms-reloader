#!/usr/bin/env bash
# Usage: ./dev.sh link | reload | status | release <x.y.z>
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/DankMaterialShell/plugins/Reloader"
case "$1" in
  link)   mkdir -p "$(dirname "$DEST")"; ln -sfn "$DIR" "$DEST"; echo "Linked $DIR -> $DEST" ;;
  reload)
    # Reloader has no sibling .js/.qml imports, so `plugins reload` is stable
    # here (see the note in ROADMAP.md about plugins that do import siblings).
    out="$(dms ipc call plugins reload reloader)"
    echo "$out"
    [[ "$out" != *FAILED* ]] ;;
  status) dms ipc call plugins status reloader ;;
  release)
    v="$2"
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 release <x.y.z>"; exit 1; }
    cd "$DIR"
    [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Working tree not clean (commit or stash first)"; exit 1; }
    prev="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' plugin.json)"
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$v\"/" plugin.json
    sed -i "s/^## \[Unreleased\]$/## [Unreleased]\n\n## [$v] - $(date +%F)/" CHANGELOG.md
    sed -i "s#^\[Unreleased\]: \(.*\)/compare/v$prev\.\.\.HEAD#[Unreleased]: \1/compare/v$v...HEAD\n[$v]: \1/compare/v$prev...v$v#" CHANGELOG.md
    git commit -am "chore(release): v$v"
    git tag -a "v$v" -m "v$v"
    echo "Tagged v$v. Review with: git show --stat HEAD, then: git push --follow-tags"
    ;;
  *)      echo "Usage: $0 link | reload | status | release <x.y.z>"; exit 1 ;;
esac
