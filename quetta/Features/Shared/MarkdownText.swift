//
//  MarkdownText.swift
//  quetta
//
//  Renders a Markdown document read-only, preserving headings and paragraphs.
//

import SwiftUI

struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private struct Block: Identifiable {
        let id = UUID()
        let view: AnyView
    }

    private var blocks: [Block] {
        markdown
            .components(separatedBy: "\n")
            .map { line -> Block in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("### ") {
                    return Block(view: AnyView(Text(String(trimmed.dropFirst(4))).font(.headline)))
                } else if trimmed.hasPrefix("## ") {
                    return Block(view: AnyView(Text(String(trimmed.dropFirst(3))).font(.title3.bold())))
                } else if trimmed.hasPrefix("# ") {
                    return Block(view: AnyView(Text(String(trimmed.dropFirst(2))).font(.title2.bold())))
                } else if trimmed.isEmpty {
                    return Block(view: AnyView(Spacer().frame(height: 2)))
                } else {
                    return Block(view: AnyView(Text(inline(trimmed))))
                }
            }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
