//
//  LimitsModels.swift
//  boringNotch
//
//  Модели лимитов Claude Code / Codex для вкладки «Лимиты».
//

import Foundation
import SwiftUI

/// Одно окно лимита (5 часов или неделя).
struct LimitWindow: Equatable {
    /// Сколько уже израсходовано, 0...100.
    var usedPercent: Double
    /// Когда окно сбросится.
    var resetsAt: Date?

    /// Окно уже закончилось — значит, лимит сброшен.
    func isExpired(now: Date = Date()) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// Сколько осталось, 0...100 (с учётом того, что окно могло сброситься).
    func remainingPercent(now: Date = Date()) -> Double {
        if isExpired(now: now) { return 100 }
        return max(0, min(100, 100 - usedPercent))
    }
}

/// Лимиты одного провайдера.
struct ProviderLimits: Equatable {
    var fiveHour: LimitWindow?
    var weekly: LimitWindow?
    /// Когда данные были записаны источником (не когда мы их прочитали).
    var updatedAt: Date?

    var hasData: Bool { fiveHour != nil || weekly != nil }
}

/// Уровень «здоровья» лимита — задаёт цвет.
enum LimitLevel {
    case good, warning, critical

    init(remaining: Double) {
        if remaining <= 15 {
            self = .critical
        } else if remaining <= 40 {
            self = .warning
        } else {
            self = .good
        }
    }

    var color: Color {
        switch self {
        case .good: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .warning: return Color(red: 1.00, green: 0.80, blue: 0.20)
        case .critical: return Color(red: 1.00, green: 0.32, blue: 0.32)
        }
    }
}

enum LimitsFormat {
    /// «2 ч 10 мин», «5 мин», «4 д 6 ч».
    static func duration(until date: Date, now: Date = Date()) -> String {
        let total = max(0, Int(date.timeIntervalSince(now)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) д \(hours) ч" }
        if hours > 0 { return "\(hours) ч \(minutes) мин" }
        return "\(max(1, minutes)) мин"
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
