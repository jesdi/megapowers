#!/usr/bin/env bash
set -euo pipefail

# Activate a local build of superpowers from this repo as an installed plugin.
# Usage: scripts/activate-local-plugin.sh [version]
#   version defaults to "local-dev"

VERSION="${1:-local-dev}"
PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers"
REGISTRY="$HOME/.claude/plugins/installed_plugins.json"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$PLUGIN_CACHE/$VERSION"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

say() { printf "${GREEN}[activate-local]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[activate-local]${NC} %s\n" "$1"; }
die() { printf "${RED}[activate-local]${NC} %s\n" "$1"; exit 1; }

# --- Pre-flight checks ---
[[ -f "$REGISTRY" ]] || die "No installed_plugins.json at $REGISTRY"
[[ -d "$REPO_ROOT/skills" ]] || die "Not in megapowers repo (no skills/ dir). cd to repo root first."
command -v jq &>/dev/null || die "jq is required. Install with: brew install jq"

# --- Check if already active ---
CURRENT_VERSION=$(jq -r '.plugins["superpowers@claude-plugins-official"][0].version' "$REGISTRY")
if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
    warn "Version $VERSION is already active. Nothing to do."
    exit 0
fi

# --- Copy repo to plugin cache ---
say "Copying repo to $DEST..."
if [[ -d "$DEST" ]]; then
    warn "Destination exists, removing..."
    rm -rf "$DEST"
fi

mkdir -p "$DEST"
rsync -a \
    --exclude='.git' \
    --exclude='.in_use' \
    --exclude='node_modules' \
    --exclude='docs/superpowers/plans' \
    "$REPO_ROOT/" "$DEST/"

# --- Update plugin.json with local version ---
say "Updating plugin.json version to $VERSION..."
jq --arg v "$VERSION" '.version = $v' \
    "$DEST/.claude-plugin/plugin.json" > "$DEST/.claude-plugin/plugin.json.tmp"
mv "$DEST/.claude-plugin/plugin.json.tmp" "$DEST/.claude-plugin/plugin.json"

# --- Back up registry if no backup exists ---
BACKUP="$PLUGIN_CACHE/.installed_plugins_backup.json"
if [[ ! -f "$BACKUP" ]]; then
    say "Backing up installed_plugins.json to $BACKUP"
    cp "$REGISTRY" "$BACKUP"
else
    say "Backup already exists at $BACKUP"
fi

# --- Switch registry to local version ---
say "Switching superpowers to version $VERSION..."
jq --arg path "$DEST" --arg v "$VERSION" \
    '(.["plugins"]["superpowers@claude-plugins-official"][0].installPath) = $path
     | (.["plugins"]["superpowers@claude-plugins-official"][0].version) = $v' \
    "$REGISTRY" > "$REGISTRY.tmp"
mv "$REGISTRY.tmp" "$REGISTRY"

say "Done. superpowers $VERSION is active."
say "Previous version was: $CURRENT_VERSION"
say ""
say "To deactivate and restore the official version:"
say "  scripts/deactivate-local-plugin.sh"
