#!/bin/bash
# Подключает хук лимитов к Claude Code (~/.claude/settings.json).
# Если у вас уже есть statusLine, он сохраняется и продолжает работать.
set -e
if ! command -v jq >/dev/null 2>&1; then
  echo "Нужен jq (brew install jq)"; exit 1
fi
mkdir -p "$HOME/.claude"
HOOK="$HOME/.claude/notch-statusline.sh"
cp "$(dirname "$0")/claude-notch-statusline.sh" "$HOOK"
chmod +x "$HOOK"

SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-notch"

INNER=$(jq -r '.statusLine.command // empty' "$SETTINGS")
if [ "$INNER" = "$HOOK" ] || [[ "$INNER" == *notch-statusline.sh ]]; then
  echo "Хук уже установлен."; exit 0
fi

if [ -n "$INNER" ]; then
  CMD="NOTCH_INNER_STATUSLINE=$(printf '%q' "$INNER") $HOOK"
else
  CMD="$HOOK"
fi

jq --arg cmd "$CMD" '.statusLine = {type: "command", command: $cmd, refreshInterval: 60}' "$SETTINGS.bak-notch" > "$SETTINGS"
echo "Готово. Перезапустите Claude Code; резервная копия: $SETTINGS.bak-notch"
