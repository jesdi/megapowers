#!/usr/bin/env bash
set -euo pipefail

# Deactivate a local superpowers build and restore the official version.
# Usage: scripts/deactivate-local-plugin.sh [version-to-restore]
#   version-to-restore defaults to the version saved in the backup

PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers"
REGISTRY="$HOME/.claude/plugins/installed_plugins.json"
BACKUP="$PLUGIN_CACHE/.installed_plugins_backup.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

say() { printf "${GREEN}[deactivate-local]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[deactivate-local]${NC} %s\n" "$1"; }
die() { printf "${RED}[deactivate-local]${NC} %s\n" "$1"; exit 1; }

command -v jq &>/dev/null || die "jq is required. Install with: brew install jq"

CURRENT_VERSION=$(jq -r '.plugins["superpowers@claude-plugins-official"][0].version' "$REGISTRY")

if [[ "$#" -ge 1 ]]; then
    TARGET_VERSION="$1"
    # Find the install path for that version
    TARGET_PATH="$PLUGIN_CACHE/$TARGET_VERSION"
    if [[ ! -d "$TARGET_PATH" ]]; then
        die "Version directory $TARGET_PATH does not exist."
    fi

    # Verify the backup has this version's path
    BACKUP_PATH=$(jq -r '.plugins["superpowers@claude-plugins-official"][0].installPath' "$BACKUP" 2>/dev/null || echo "")
else
    if [[ ! -f "$BACKUP" ]]; then
        die "No backup found at $BACKUP and no target version specified.\nSpecify a version: scripts/deactivate-local-plugin.sh 5.1.0"
    fi
    TARGET_VERSION=$(jq -r '.plugins["superpowers@claude-plugins-official"][0].version' "$BACKUP")
    TARGET_PATH=$(jq -r '.plugins["superpowers@claude-plugins-official"][0].installPath' "$BACKUP")
fi

if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
    warn "Version $TARGET_VERSION is already active. Nothing to do."
    exit 0
fi

say "Switching superpowers from $CURRENT_VERSION back to $TARGET_VERSION..."

jq --arg path "$TARGET_PATH" --arg v "$TARGET_VERSION" \
    '(.["plugins"]["superpowers@claude-plugins-official"][0].installPath) = $path
     | (.["plugins"]["superpowers@claude-plugins-official"][0].version) = $v' \
    "$REGISTRY" > "$REGISTRY.tmp"
mv "$REGISTRY.tmp" "$REGISTRY"

say "Done. superpowers $TARGET_VERSION is now active."
