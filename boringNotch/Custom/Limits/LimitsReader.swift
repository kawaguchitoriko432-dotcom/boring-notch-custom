//
//  LimitsReader.swift
//  boringNotch
//
//  Читает лимиты из локальных файлов. Ни токены, ни ключи, ни сеть не используются.
//
//  Claude:      ~/Library/Application Support/Claude/plan-usage-history.json
//               (пишет приложение Claude, покрывает и Cowork); запасной вариант —
//               ~/.claude/notch-limits.json от хука statusline Claude Code.
//  Codex:       ~/.codex/sessions/ГГГГ/ММ/ДД/rollout-*.jsonl — в событиях
//               token_count лежит rate_limits.primary / secondary.
//

import Foundation

enum LimitsReader {
    /// Настоящая домашняя папка. В песочнице `homeDirectoryForCurrentUser`
    /// указывает в контейнер, поэтому берём путь из базы пользователей.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Claude (приложение Claude / Cowork)

    /// Читает `plan-usage-history.json`, который ведёт само приложение Claude:
    /// замеры {t (мс), u: {fh: % за 5 ч, sd: % за неделю}}. Ничего, кроме времени и
    /// двух процентов, не используется (поле org игнорируется). Формат внутренний,
    /// поэтому проверяем version; если он другой, источник считается недоступным.
    /// Сначала пробуем этот файл, потом (запасной вариант) хук Claude Code.
    static func readClaude() -> ProviderLimits {
        if let app = readClaudeApp() { return app }
        return readClaudeCodeHook()
    }

    private static func readClaudeApp() -> ProviderLimits? {
        let url = realHome.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard
            let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (obj["version"] as? NSNumber)?.intValue == 2,
            let raw = obj["samples"] as? [[String: Any]]
        else { return nil }

        struct Sample { let t: Date; let fh: Double; let sd: Double }
        let samples: [Sample] = raw.compactMap { d in
            guard
                let t = (d["t"] as? NSNumber)?.doubleValue,
                let u = d["u"] as? [String: Any],
                let fh = (u["fh"] as? NSNumber)?.doubleValue,
                let sd = (u["sd"] as? NSNumber)?.doubleValue
            else { return nil }
            return Sample(t: Date(timeIntervalSince1970: t / 1000), fh: fh, sd: sd)
        }.sorted { $0.t < $1.t }
        guard let last = samples.last else { return nil }

        // Начало текущей 5-часовой сессии: идём назад, пока процент не убывает
        // и между замерами нет разрыва больше 5 часов.
        let window: TimeInterval = 5 * 3600
        var first = samples.count - 1
        while first > 0 {
            let prev = samples[first - 1], cur = samples[first]
            if prev.fh > cur.fh || cur.t.timeIntervalSince(prev.t) >= window { break }
            first -= 1
        }
        var sessionReset: Date? = samples[first].t.addingTimeInterval(window)
        if let r = sessionReset, r <= Date() { sessionReset = nil }  // оценка устарела

        var five = LimitWindow(usedPercent: last.fh, resetsAt: sessionReset)
        five.resetsApproximate = true
        var week = LimitWindow(usedPercent: last.sd, resetsAt: nextWeeklyReset(after: Date()))
        week.resetsApproximate = true
        return ProviderLimits(fiveHour: five, weekly: week, updatedAt: last.t)
    }

    /// Недельный сброс: по экрану Usage — четверг 01:00 по местному времени.
    private static func nextWeeklyReset(after now: Date) -> Date? {
        var comps = DateComponents()
        comps.weekday = 5  // четверг
        comps.hour = 1
        comps.minute = 0
        return Calendar.current.nextDate(
            after: now, matching: comps, matchingPolicy: .nextTime)
    }

    /// Запасной источник: файл, который пишет хук статус-строки Claude Code.
    private static func readClaudeCodeHook() -> ProviderLimits {
        let url = realHome.appendingPathComponent(".claude/notch-limits.json")
        guard
            let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ProviderLimits() }

        func window(_ key: String) -> LimitWindow? {
            guard
                let d = obj[key] as? [String: Any],
                let used = (d["used_percentage"] as? NSNumber)?.doubleValue
            else { return nil }
            let reset = (d["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return LimitWindow(usedPercent: used, resetsAt: reset)
        }

        var result = ProviderLimits(fiveHour: window("five_hour"), weekly: window("seven_day"), updatedAt: nil)
        if let updated = (obj["updated"] as? NSNumber)?.doubleValue {
            result.updatedAt = Date(timeIntervalSince1970: updated)
        }
        return result
    }

    // MARK: - Codex

    static func readCodex() -> ProviderLimits {
        let sessions = realHome.appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = newestRolloutFiles(in: sessions, limit: 4)

        // Живые данные от фонового агента (tools/codex-limits-agent.pl), если он установлен.
        var best: ProviderLimits? = readCodexLiveFile()
        for file in files {
            guard let candidate = lastCodexLimits(in: file) else { continue }
            if best == nil || (candidate.updatedAt ?? .distantPast) > (best?.updatedAt ?? .distantPast) {
                best = candidate
            }
        }
        return best ?? ProviderLimits()
    }

    /// Файл ~/.codex/notch-limits-live.json: его раз в 5 минут пишет агент, спрашивая у codex app-server.
    private static func readCodexLiveFile() -> ProviderLimits? {
        let url = realHome.appendingPathComponent(".codex/notch-limits-live.json")
        guard
            let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var result = ProviderLimits()
        for key in ["primary", "secondary"] {
            guard
                let w = obj[key] as? [String: Any],
                let used = (w["used_percent"] as? NSNumber)?.doubleValue
            else { continue }
            let resetsAt = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let minutes = (w["window_minutes"] as? NSNumber)?.doubleValue ?? (key == "primary" ? 300 : 10_080)
            let window = LimitWindow(usedPercent: used, resetsAt: resetsAt)
            if minutes <= 360 {
                result.fiveHour = window
            } else {
                result.weekly = window
            }
        }
        guard result.hasData else { return nil }
        if let updated = (obj["updated"] as? NSNumber)?.doubleValue {
            result.updatedAt = Date(timeIntervalSince1970: updated)
        }
        return result
    }

    /// Самые свежие rollout-файлы. Не обходим всё дерево: берём три последних дня.
    private static func newestRolloutFiles(in root: URL, limit: Int) -> [URL] {
        let fm = FileManager.default

        func sortedSubdirs(_ dir: URL) -> [URL] {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return items.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }

        var dayDirs: [URL] = []
        outer: for year in sortedSubdirs(root) {
            for month in sortedSubdirs(year) {
                for day in sortedSubdirs(month) {
                    dayDirs.append(day)
                    if dayDirs.count >= 3 { break outer }
                }
            }
        }

        var files: [(url: URL, modified: Date)] = []
        for dir in dayDirs {
            let items = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            for item in items where item.pathExtension == "jsonl" {
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                files.append((item, modified))
            }
        }
        return files.sorted { $0.modified > $1.modified }.prefix(limit).map { $0.url }
    }

    /// Последнее событие token_count с rate_limits в файле (читаем только «хвост»).
    private static func lastCodexLimits(in file: URL) -> ProviderLimits? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let tailSize: UInt64 = 600_000
        let start = size > tailSize ? size - tailSize : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines.reversed() {
            guard line.contains("\"rate_limits\"") else { continue }
            guard
                let lineData = String(line).data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let payload = obj["payload"] as? [String: Any],
                let limits = payload["rate_limits"] as? [String: Any]
            else { continue }

            var result = ProviderLimits()
            for key in ["primary", "secondary"] {
                guard
                    let w = limits[key] as? [String: Any],
                    let used = (w["used_percent"] as? NSNumber)?.doubleValue
                else { continue }

                var resetsAt: Date?
                if let epoch = (w["resets_at"] as? NSNumber)?.doubleValue {
                    resetsAt = Date(timeIntervalSince1970: epoch)
                } else if let secs = (w["resets_in_seconds"] as? NSNumber)?.doubleValue {
                    resetsAt = Date().addingTimeInterval(secs)
                }

                let minutes = (w["window_minutes"] as? NSNumber)?.doubleValue
                    ?? (key == "primary" ? 300 : 10_080)
                let window = LimitWindow(usedPercent: used, resetsAt: resetsAt)
                if minutes <= 360 {
                    result.fiveHour = window
                } else {
                    result.weekly = window
                }
            }
            guard result.hasData else { continue }

            if let ts = obj["timestamp"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                result.updatedAt = f.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
            }
            return result
        }
        return nil
    }
}
