//
//  LimitsReader.swift
//  boringNotch
//
//  Читает лимиты из локальных файлов. Ни токены, ни ключи, ни сеть не используются.
//
//  Claude Code: файл ~/.claude/notch-limits.json, который пишет хук statusline
//               (tools/claude-notch-statusline.sh). Claude Code сам отдаёт
//               rate_limits.five_hour / seven_day в JSON для statusline.
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

    // MARK: - Claude Code

    static func readClaude() -> ProviderLimits {
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
