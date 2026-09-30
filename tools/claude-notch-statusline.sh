#!/bin/bash
# Хук statusline для Claude Code: сохраняет лимиты (5 часов / неделя) в файл,
# который читает шторка. Ничего не отправляет в сеть, токены не трогает.
# Если раньше у вас была своя строка статуса, её команда лежит в NOTCH_INNER_STATUSLINE.
input=$(cat)
out="$HOME/.claude/notch-limits.json"

if command -v jq >/dev/null 2>&1; then
  tmp="$out.tmp.$$"
  printf '%s' "$input" | jq -c '{updated: (now | floor), five_hour: .rate_limits.five_hour, seven_day: .rate_limits.seven_day}' > "$tmp" 2>/dev/null \
    && mv "$tmp" "$out" || rm -f "$tmp"
fi

if [ -n "$NOTCH_INNER_STATUSLINE" ]; then
  printf '%s' "$input" | bash -c "$NOTCH_INNER_STATUSLINE"
elif command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | jq -r '"[\(.model.display_name // "Claude")]"'
fi
