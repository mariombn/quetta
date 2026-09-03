//
//  MarkdownExportService.swift
//  quetta
//
//  Presents an NSSavePanel and writes the Markdown export (spec §11). A failure to
//  save never alters the session.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum MarkdownExportService {

    @discardableResult
    static func export(_ session: MeetingSession, locale: Locale) -> Bool {
        let data = MarkdownExporter.makeExportData(from: session)
        let markdown = MarkdownExporter.makeMarkdown(from: data, locale: locale)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = MarkdownExporter.suggestedFileName(for: session.title)
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try markdown.data(using: .utf8)?.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
