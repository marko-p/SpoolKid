//
//  SaveNoticeTests.swift
//  SpoolKidTests
//

import Testing
@testable import SpoolKid

struct SaveNoticeTests {
    @Test func anEntryCarriesItsOwnRecord() {
        let notice = SaveNotice.appending(
            record: "Spool #4 · PLA Matte HS ROSY",
            message: "First Used — FilaMan sets this when the spool is created.",
            to: nil
        )

        #expect(notice?.entries.count == 1)
        #expect(notice?.entries.first?.record == "Spool #4 · PLA Matte HS ROSY")
    }

    /// The whole reason a notice is a LIST rather than one labelled string:
    /// `postSaveNotice` accumulates across writes (I4), and a filament saved
    /// from inside the spool sheet posts its caveat while the spool's own save
    /// follows moments later. One record label over both would mislabel one.
    @Test func twoRecordsKeepTheirOwnLabels() {
        var notice = SaveNotice.appending(record: "Filament · PLA Silk GOLD", message: "Colour was not applied.", to: nil)
        notice = SaveNotice.appending(record: "Spool #4", message: "Location was not created.", to: notice)

        #expect(notice?.entries.map(\.record) == ["Filament · PLA Silk GOLD", "Spool #4"])
        #expect(notice?.entries.map(\.message) == ["Colour was not applied.", "Location was not created."])
    }

    @Test func blanksAddNothing() {
        #expect(SaveNotice.appending(record: "Spool #4", message: "   ", to: nil) == nil)
        let kept = SaveNotice.appending(record: nil, message: "kept", to: nil)
        #expect(SaveNotice.appending(record: "Spool #4", message: "\n", to: kept) == kept)
    }

    /// Two saves failing the same way on the same record is one piece of news.
    @Test func anExactRepeatOnTheSameRecordIsNotSaidTwice() {
        var notice = SaveNotice.appending(record: "Spool #4", message: "same", to: nil)
        notice = SaveNotice.appending(record: "Spool #4", message: "same", to: notice)

        #expect(notice?.entries.count == 1)
    }

    /// …but the same sentence about a DIFFERENT record is genuinely new. This
    /// is what the old string-dedupe got wrong: it compared messages only, so
    /// the second spool's identical caveat vanished.
    @Test func theSameMessageAboutAnotherRecordIsKept() {
        var notice = SaveNotice.appending(record: "Spool #4", message: "Location was not created.", to: nil)
        notice = SaveNotice.appending(record: "Spool #7", message: "Location was not created.", to: notice)

        #expect(notice?.entries.count == 2)
    }

    /// A repository can hand back several caveats joined by newlines
    /// (`SaveOutcome.combinedNote`). They belong to one record but are separate
    /// pieces of news, so they arrive as separate entries under that record.
    @Test func aMultiLineMessageBecomesOneEntryPerLine() {
        let notice = SaveNotice.appending(
            record: "Spool #4",
            message: "First Used — FilaMan sets this when the spool is created.\nLast Used — FilaMan works this out from its own usage history.",
            to: nil
        )

        #expect(notice?.entries.count == 2)
        #expect(notice?.entries.allSatisfy { $0.record == "Spool #4" } == true)
    }
}
