//
//  ClipboardModels.swift
//  boringNotch
//
//  История буфера обмена: модель элемента.
//

import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text, image, files
    }

    var id = UUID()
    var kind: Kind
    /// Текст (для .text).
    var text: String?
    /// Имя PNG-файла в папке истории (для .image).
    var imageFileName: String?
    /// Пути скопированных файлов (для .files). Сами файлы не копируются.
    var filePaths: [String]?
    var date = Date()
    var pinned = false
    var sourceApp: String?

    /// Ключ для сравнения содержимого (чтобы не плодить дубликаты).
    var contentKey: String {
        switch kind {
        case .text: return "t:" + (text ?? "")
        case .files: return "f:" + (filePaths ?? []).joined(separator: "\n")
        case .image: return "i:" + (imageFileName ?? "")
        }
    }
}
