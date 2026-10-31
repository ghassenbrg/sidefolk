import Foundation
import Testing
@testable import SidefolkCore

/// Today's line (D58): things sit at their time, whatever the width, and the hour labels never touch.
@Suite struct DayLineTests {
    let cal = TimeTest.utc
    func at(_ h: Int, _ m: Int = 0) -> Date { TimeTest.date(2026, 10, 31, h, m) }

    /// The founder's morning: at 11:40, a reminder at 15:00 beside Tomorrow in a narrow column.
    @Test func aReminderStartsAtItsTimeEvenNearTheEnd() {
        let span = DayLine.range(now: at(11, 40), starts: [at(15)], ends: [at(15)], calendar: cal)
        #expect(span == at(10)...at(16))
        for width in stride(from: 160.0, through: 1200, by: 40) {
            let placed = DayLine.place([.init(start: at(15), end: at(15), readable: 170)], in: span, width: width)[0]
            let time = DayLine.x(at(15), in: span, width: width)
            #expect(placed.at == time)
            if placed.endsAtTime {
                #expect(abs(placed.x + placed.width - time) < 0.001, "width \(width)")
            } else {
                #expect(placed.x == time, "width \(width)")
            }
            #expect(placed.x >= 0 && placed.x + placed.width <= width + 0.001, "width \(width)")
        }
    }

    @Test func aChipIsCutShortRatherThanMoved() {
        let span = at(10)...at(16)
        // 15:00 is 500 points into 600: a chip that wants 170 gets the 100 left, still starting at 15:00.
        let placed = DayLine.place([.init(start: at(15), end: at(15), readable: 170)], in: span, width: 600)[0]
        #expect(placed.x == 500)
        #expect(placed.width == 100)
        #expect(!placed.endsAtTime)
    }

    @Test func onlyTheVeryEndTurnsAChipAround() {
        let span = at(10)...at(16)
        let placed = DayLine.place([.init(start: at(16), end: at(16), readable: 120)], in: span, width: 600)[0]
        #expect(placed.endsAtTime)
        #expect(placed.x + placed.width == 600)
    }

    @Test func anEventKeepsItsLengthAndItsStart() {
        let span = at(10)...at(16)
        let placed = DayLine.place([.init(start: at(13), end: at(14), readable: 40)], in: span, width: 600)[0]
        #expect(placed.x == 300)
        #expect(placed.length == 100)
        #expect(placed.width == 100)
    }

    @Test func overlappingThingsTakeTheNextLane() {
        let span = at(10)...at(16)
        let placed = DayLine.place([.init(start: at(12), end: at(12), readable: 150),
                                    .init(start: at(12, 30), end: at(12, 30), readable: 150),
                                    .init(start: at(14), end: at(14), readable: 80)], in: span, width: 600)
        #expect(placed.map(\.lane) == [0, 1, 0])
    }

    @Test func theLineLeavesRoomAfterTheLastThing() {
        let span = DayLine.range(now: at(9), starts: [at(17, 30)], ends: [at(17, 30)], calendar: cal)
        #expect(span.upperBound == at(19))
        // Never past midnight, though.
        let late = DayLine.range(now: at(21), starts: [at(23, 30)], ends: [at(23, 30)], calendar: cal)
        #expect(late.upperBound == TimeTest.date(2026, 11, 1))
    }

    @Test func hourLabelsNeverTouch() {
        let spans = [at(10)...at(16), at(6)...at(19), at(0)...TimeTest.date(2026, 11, 1)]
        for span in spans {
            for width in stride(from: 80.0, through: 1400, by: 20) {
                for labelWidth in [30.0, 34, 48] {
                    let labels = DayLine.ticks(in: span, width: width, labelWidth: labelWidth, calendar: cal).compactMap(\.labelX)
                    for (a, b) in zip(labels, labels.dropFirst()) {
                        #expect(b - (a + labelWidth) >= DayLine.gap, "\(width) \(labelWidth)")
                    }
                    #expect(labels.allSatisfy { $0 >= 0 && $0 + labelWidth <= width + 0.001 })
                }
            }
        }
    }

    @Test func everyHourHasItsMarkAtItsTime() {
        let span = at(10)...at(16)
        let ticks = DayLine.ticks(in: span, width: 600, labelWidth: 32, calendar: cal)
        #expect(ticks.map(\.x) == [0, 100, 200, 300, 400, 500, 600])
        // Roomy: every hour labelled, centred on its mark except where the edges hold it in.
        #expect(ticks.compactMap(\.labelX) == [0, 84, 184, 284, 384, 484, 568])
        // Crowded: every third hour, on round hours.
        let tight = DayLine.ticks(in: span, width: 180, labelWidth: 32, calendar: cal)
        #expect(tight.filter { $0.labelX != nil }.map { cal.component(.hour, from: $0.date) }.allSatisfy { $0 % 2 == 0 || $0 % 3 == 0 })
    }
}
