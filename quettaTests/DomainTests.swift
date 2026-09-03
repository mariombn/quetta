//
//  DomainTests.swift
//  quettaTests
//

import Testing
import Foundation
@testable import quetta

@Suite("Session state machine")
struct SessionStateMachineTests {

    @Test("Valid transitions are allowed")
    func validTransitions() {
        #expect(SessionStateMachine.canTransition(from: .draft, to: .active))
        #expect(SessionStateMachine.canTransition(from: .active, to: .paused))
        #expect(SessionStateMachine.canTransition(from: .paused, to: .active))
        #expect(SessionStateMachine.canTransition(from: .active, to: .finalizing))
        #expect(SessionStateMachine.canTransition(from: .paused, to: .finalizing))
        #expect(SessionStateMachine.canTransition(from: .finalizing, to: .generatingSummary))
        #expect(SessionStateMachine.canTransition(from: .finalizing, to: .completedWithoutSummary))
        #expect(SessionStateMachine.canTransition(from: .generatingSummary, to: .completed))
        #expect(SessionStateMachine.canTransition(from: .generatingSummary, to: .completedWithoutSummary))
    }

    @Test("Invalid transitions are rejected")
    func invalidTransitions() {
        #expect(!SessionStateMachine.canTransition(from: .draft, to: .paused))
        #expect(!SessionStateMachine.canTransition(from: .draft, to: .completed))
        #expect(!SessionStateMachine.canTransition(from: .completed, to: .active))
        #expect(!SessionStateMachine.canTransition(from: .failed, to: .active))
        #expect(!SessionStateMachine.canTransition(from: .active, to: .completed))
        #expect(!SessionStateMachine.canTransition(from: .generatingSummary, to: .failed))
    }

    @Test("Validate throws on invalid transition")
    func validateThrows() {
        #expect(throws: SessionStateError.self) {
            try SessionStateMachine.validate(from: .completed, to: .active)
        }
    }

    @Test("Terminal states expose no transitions")
    func terminalStates() {
        #expect(SessionStateMachine.allowedTransitions(from: .completed).isEmpty)
        #expect(SessionStateMachine.allowedTransitions(from: .completedWithoutSummary).isEmpty)
        #expect(SessionStateMachine.allowedTransitions(from: .failed).isEmpty)
    }
}

@Suite("Title generation")
struct TitleGeneratorTests {

    @Test("Portuguese title uses the localized prefix")
    func portugueseTitle() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 3; comps.hour = 10; comps.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let title = TitleGenerator.automaticTitle(for: date, locale: Locale(identifier: "pt_BR"))
        #expect(title.contains("Reunião"))
        #expect(title.contains("2026"))
        #expect(title.contains("—"))
    }

    @Test("English title uses the localized prefix")
    func englishTitle() {
        let date = Date(timeIntervalSince1970: 1_756_900_200)
        let title = TitleGenerator.automaticTitle(for: date, locale: Locale(identifier: "en_US"))
        #expect(title.contains("Meeting"))
    }
}

@Suite("Markdown exporter")
struct MarkdownExporterTests {

    private func sampleData(mode: SessionMode) -> MarkdownExportData {
        MarkdownExportData(
            title: "Test Meeting",
            date: Date(timeIntervalSince1970: 1_756_900_200),
            duration: 125,
            mode: mode,
            transcriptionLanguage: .portuguese,
            transcript: [
                .init(kind: .speech, text: "Olá a todos."),
                .init(kind: .pausedMarker, text: "Sessão pausada"),
                .init(kind: .speech, text: "Vamos começar."),
            ],
            translationPairs: mode == .translation ? [
                .init(original: "Olá a todos.", translated: "Hello everyone."),
                .init(original: "Vamos começar.", translated: "Let's begin."),
            ] : [],
            summaryMarkdown: "# Resumo da reunião\n\n## Resumo executivo\n\nTudo certo."
        )
    }

    @Test("Simple mode omits the translation section")
    func simpleMode() {
        let md = MarkdownExporter.makeMarkdown(from: sampleData(mode: .simple), locale: Locale(identifier: "en_US"))
        #expect(md.contains("# Test Meeting"))
        #expect(md.contains("## Transcript"))
        #expect(md.contains("Olá a todos."))
        #expect(md.contains("## Summary"))
        #expect(!md.contains("## Translation"))
    }

    @Test("Translation mode includes both original and translated text")
    func translationMode() {
        let md = MarkdownExporter.makeMarkdown(from: sampleData(mode: .translation), locale: Locale(identifier: "en_US"))
        #expect(md.contains("## Translation"))
        #expect(md.contains("Hello everyone."))
        #expect(md.contains("Let's begin."))
    }

    @Test("File name is filesystem safe")
    func fileName() {
        #expect(MarkdownExporter.suggestedFileName(for: "A/B:C") == "A-B-C.md")
        #expect(MarkdownExporter.suggestedFileName(for: "   ") == "quetta.md")
    }

    @Test("Duration formatting")
    func duration() {
        #expect(MarkdownExporter.formatDuration(65) == "01:05")
        #expect(MarkdownExporter.formatDuration(3_725) == "1:02:05")
    }
}

@Suite("Enums")
struct EnumTests {
    @Test("Language locale identifiers")
    func localeIdentifiers() {
        #expect(LanguageCode.portuguese.localeIdentifier == "pt-BR")
        #expect(LanguageCode.english.localeIdentifier == "en-US")
        #expect(LanguageCode.spanish.localeIdentifier == "es-ES")
    }

    @Test("Terminal status detection")
    func terminalStatus() {
        #expect(SessionStatus.completed.isTerminal)
        #expect(SessionStatus.failed.isTerminal)
        #expect(!SessionStatus.active.isTerminal)
    }
}
