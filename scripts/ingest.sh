#!/bin/bash
# Pensieve wiki ingestion — runs via cron
# Checks for new raw notes and asks Claude Code to ingest them into the wiki.

VAULT_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain"
LOG_FILE="$VAULT_DIR/wiki/log.md"
RAW_DIR="$VAULT_DIR/raw"
LOCK_FILE="/tmp/secondbrain-ingest.lock"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    # Check if lock is stale (older than 10 minutes)
    if [ "$(find "$LOCK_FILE" -mmin +10 2>/dev/null)" ]; then
        rm -f "$LOCK_FILE"
    else
        exit 0
    fi
fi
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

# Check if vault exists
if [ ! -d "$VAULT_DIR" ]; then
    echo "Vault not found at $VAULT_DIR"
    exit 1
fi

# Find unprocessed notes by checking log.md
UNPROCESSED=""
for note in "$RAW_DIR"/*.md; do
    [ -f "$note" ] || continue
    basename=$(basename "$note" .md)
    if ! grep -q "$basename" "$LOG_FILE" 2>/dev/null; then
        UNPROCESSED="$UNPROCESSED $basename"
    fi
done

# Nothing to do
if [ -z "$UNPROCESSED" ]; then
    exit 0
fi

COUNT=$(echo "$UNPROCESSED" | wc -w | tr -d ' ')
echo "$(date): Found $COUNT unprocessed note(s):$UNPROCESSED"

# Run Claude Code to ingest
cd "$VAULT_DIR"
claude -p --dangerously-skip-permissions --model sonnet "Ingest all unprocessed raw notes into the wiki. Follow the instructions in CLAUDE.md exactly. The unprocessed notes are:$UNPROCESSED. Read each raw note, update theme pages, timeline, contradictions, index, and log. Work directly in this vault directory."
