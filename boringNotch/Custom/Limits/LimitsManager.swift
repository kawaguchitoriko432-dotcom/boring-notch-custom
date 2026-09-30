//
//  LimitsManager.swift
//  boringNotch
//

import Combine
import Foundation
import UserNotifications

final class LimitsManager: ObservableObject {
    static let shared = LimitsManager()

    @Published private(set) var claude = ProviderLimits()
    @Published private(set) var codex = ProviderLimits()

    /// Порог, ниже которого приходит одно уведомление (в процентах остатка).
    private let notifyThreshold: Double = 10
    private var notified: Set<String> = []
    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let claude = LimitsReader.readClaude()
            let codex = LimitsReader.readCodex()
            await MainActor.run {
                self?.apply(claude: claude, codex: codex)
            }
        }
    }

    @MainActor
    private func apply(claude newClaude: ProviderLimits, codex newCodex: ProviderLimits) {
        if newClaude != claude { claude = newClaude }
        if newCodex != codex { codex = newCodex }
        checkNotifications(name: "Claude Code", limits: newClaude)
        checkNotifications(name: "Codex", limits: newCodex)
    }

    // MARK: - Уведомление на исходе лимита

    private func checkNotifications(name: String, limits: ProviderLimits) {
        guard let window = limits.fiveHour, !window.isExpired() else { return }
        let remaining = window.remainingPercent()
        guard remaining <= notifyThreshold else { return }

        // Один раз на каждое окно (ключ включает время сброса).
        let key = "\(name)-\(Int(window.resetsAt?.timeIntervalSince1970 ?? 0))"
        guard !notified.contains(key) else { return }
        notified.insert(key)

        let title = "У \(name) заканчиваются лимиты"
        var body = "5 ч: осталось \(Int(remaining.rounded()))%"
        if let reset = window.resetsAt {
            body += ", сброс через \(LimitsFormat.duration(until: reset))"
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: key, content: content, trigger: nil)
            center.add(request)
        }
    }
}
