# Boring Notch + лимиты + Яндекс Музыка

Форк [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) с доработками.

## Что добавлено
- Вкладка **Limits** (значок-спидометр рядом с Home/Shelf): остаток лимита Claude Code и Codex за 5 часов и за неделю, цвет зелёный / жёлтый / красный, время сброса, уведомление при остатке ≤ 10%.
- Источник музыки **«Яндекс Музыка»** (Настройки → Media → Music Source): показывает и управляет только приложением «Яндекс Музыка» (`ru.yandex.desktop.music`), чужие плееры игнорирует.
- Файловая полка (Shelf) уже была в Boring Notch: перетащите файл в шторку и заберите оттуда.

Код: `boringNotch/Custom/`. Токены и ключи не читаются, сеть не используется.

## Сборка
Нужен Xcode 16+ (бесплатно в App Store), macOS 14+.
1. `git clone --recursive` этого репозитория (или откройте папку из архива).
2. Откройте `boringNotch.xcodeproj`, в Signing & Capabilities выберите свой Apple ID (Personal Team).
3. Product → Run.
Без Xcode: workflow `.github/workflows/build-unsigned.yml` собирает приложение на GitHub.

## Лимиты Codex
Работают сразу: читается `~/.codex/sessions/…/rollout-*.jsonl`. Данные обновляются после каждого запроса в Codex.

## Лимиты Claude Code
Запустите один раз `tools/install-claude-hook.sh` (нужен `jq`). Скрипт прописывает statusline в `~/.claude/settings.json` (старая строка статуса сохраняется). Claude Code будет писать лимиты в `~/.claude/notch-limits.json`. Данные появляются после первого ответа в сессии, только для подписок Pro/Max.
