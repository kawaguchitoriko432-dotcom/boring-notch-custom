//
//  LimitsView.swift
//  boringNotch
//
//  Вкладка «Лимиты»: две карточки (Claude Code и Codex).
//

import SwiftUI

struct LimitsView: View {
    @ObservedObject private var manager = LimitsManager.shared

    var body: some View {
        HStack(spacing: 10) {
            LimitCard(
                title: "Claude Code",
                symbol: "sun.max.fill",
                limits: manager.claude,
                emptyHint: "Лимиты Claude (Cowork) подключим позже."
            )
            LimitCard(
                title: "Codex",
                symbol: "chevron.left.forwardslash.chevron.right",
                limits: manager.codex,
                emptyHint: "Нет данных. Отправьте любой запрос в Codex."
            )
        }
        .padding(.horizontal, 4)
        .onAppear { manager.refresh() }
    }
}

private struct LimitCard: View {
    let title: String
    let symbol: String
    let limits: ProviderLimits
    let emptyHint: String

    var body: some View {
        // Раз в 30 секунд перерисовываем, чтобы «сброс через…» шёл вместе со временем.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if let updated = limits.updatedAt {
                        Text(freshness(updated, now: context.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if limits.hasData {
                    if let five = limits.fiveHour {
                        LimitRow(label: "5 ч", window: five, now: context.date)
                    }
                    if let week = limits.weekly {
                        LimitRow(label: "Неделя", window: week, now: context.date)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text(emptyHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
        }
    }

    private func freshness(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 90 { return "Свежие" }
        return "Обновлено в \(LimitsFormat.clock(date))"
    }
}

private struct LimitRow: View {
    let label: String
    let window: LimitWindow
    let now: Date

    var body: some View {
        let remaining = window.remainingPercent(now: now)
        let level = LimitLevel(remaining: remaining)

        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Осталось \(Int(remaining.rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(level.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(level.color)
                        .frame(width: max(3, geo.size.width * remaining / 100))
                }
            }
            .frame(height: 4)

            Text(detail(now: now))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func detail(now: Date) -> String {
        let used = Int((100 - window.remainingPercent(now: now)).rounded())
        guard let reset = window.resetsAt else { return "Исп. \(used)%" }
        if window.isExpired(now: now) { return "Лимит сброшен" }
        return "Исп. \(used)% · сброс через \(LimitsFormat.duration(until: reset, now: now)) · \(LimitsFormat.clock(reset))"
    }
}
