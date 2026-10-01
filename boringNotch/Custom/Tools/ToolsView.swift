//
//  ToolsView.swift
//  boringNotch
//
//  Вкладка «Кнопки»: запускает готовые приложения-кнопки Дмитрия
//  («Stay Awake», «Заблокировать экран», «Переключить F-клавиши»).
//  Шторка ничего не меняет в системе сама: она только открывает эти приложения,
//  поэтому их права и запрос пароля остаются как раньше.
//

import AppKit
import SwiftUI

private struct ToolButton: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    /// Имя приложения-кнопки (без .app).
    let appName: String
}

private let toolButtons: [ToolButton] = [
    ToolButton(
        id: "awake-on", title: "Не засыпать", subtitle: "Включить",
        symbol: "cup.and.saucer.fill", tint: Color(red: 0.30, green: 0.85, blue: 0.45),
        appName: "Stay Awake - ON"),
    ToolButton(
        id: "awake-off", title: "Можно спать", subtitle: "Выключить",
        symbol: "moon.zzz.fill", tint: Color(red: 0.55, green: 0.60, blue: 1.00),
        appName: "Stay Awake - OFF"),
    ToolButton(
        id: "lock", title: "Заблокировать", subtitle: "Экран",
        symbol: "lock.fill", tint: Color(red: 1.00, green: 0.80, blue: 0.20),
        appName: "Заблокировать экран"),
    ToolButton(
        id: "fn", title: "F-клавиши", subtitle: "Переключить режим",
        symbol: "keyboard.fill", tint: Color(red: 0.95, green: 0.50, blue: 0.30),
        appName: "Переключить F-клавиши"),
]

/// Папки, где ищем приложения-кнопки (по порядку).
private func candidateURLs(for appName: String) -> [URL] {
    let home = LimitsReader.realHome
    return [
        home.appendingPathComponent("Applications/Системные кнопки/\(appName).app"),
        home.appendingPathComponent("Desktop/Системные кнопки/\(appName).app"),
    ]
}

struct ToolsView: View {
    @State private var message: String?
    @State private var pressed: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(toolButtons) { tool in
                    Button { launch(tool) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(tool.tint)
                            Text(tool.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(tool.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(pressed == tool.id ? 0.18 : 0.07))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if let message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
    }

    private func launch(_ tool: ToolButton) {
        pressed = tool.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pressed = nil }
        message = nil
        open(candidateURLs(for: tool.appName)[...], tool: tool)
    }

    /// Пробуем кандидатов по очереди; если ни один не открылся, подсказываем, куда положить.
    private func open(_ urls: ArraySlice<URL>, tool: ToolButton) {
        guard let url = urls.first else {
            message = "Не нашёл «\(tool.appName)». Положите папку «Системные кнопки» в ~/Applications."
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if error != nil {
                DispatchQueue.main.async { open(urls.dropFirst(), tool: tool) }
            }
        }
    }
}
