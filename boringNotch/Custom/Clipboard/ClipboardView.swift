//
//  ClipboardView.swift
//  boringNotch
//
//  Вкладка «Буфер»: карточки последних скопированных текстов, картинок и файлов.
//

import AppKit
import SwiftUI

struct ClipboardView: View {
    @ObservedObject private var manager = ClipboardManager.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("Буфер обмена")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if manager.isPaused {
                    Text("на паузе")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(manager.isPaused ? "Продолжить запись" : "Пауза") {
                    manager.isPaused.toggle()
                }
                Button("Очистить") { manager.clearUnpinned() }
                    .disabled(manager.items.allSatisfy { $0.pinned })
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            if manager.items.isEmpty {
                Text("Скопируйте текст, картинку или файл, и он появится здесь. Клик по карточке возвращает её в буфер, а файлы и картинки можно перетащить наружу.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(manager.items) { item in
                            ClipboardCard(item: item)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var hovering = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

            HStack(spacing: 4) {
                Text(footer)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.pinned || hovering {
                    Button {
                        manager.togglePin(item)
                    } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                    }
                    .foregroundStyle(item.pinned ? Color.yellow : Color.secondary)
                }
                if hovering {
                    Button {
                        manager.remove(item)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
        }
        .padding(8)
        .frame(width: 138, height: 116)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.12 : 0.07))
        )
        .overlay(alignment: .top) {
            if justCopied {
                Text("Скопировано")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.85)))
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            manager.copyToPasteboard(item)
            withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeIn(duration: 0.2)) { justCopied = false }
            }
        }
        .onDrag { dragProvider() }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
        case .image:
            if let image = manager.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        case .files:
            let paths = item.filePaths ?? []
            HStack(alignment: .top, spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: paths.first ?? "/"))
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: paths.first ?? "").lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    if paths.count > 1 {
                        Text("и ещё \(paths.count - 1)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        let when = f.localizedString(for: item.date, relativeTo: Date())
        if let app = item.sourceApp { return "\(app) · \(when)" }
        return when
    }

    /// Перетаскивание наружу: файлы и картинки как файлы, текст как строка.
    private func dragProvider() -> NSItemProvider {
        switch item.kind {
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .files:
            if let path = item.filePaths?.first,
               let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) {
                return provider
            }
            return NSItemProvider()
        case .image:
            if let url = manager.imageURL(for: item),
               let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        }
    }
}
