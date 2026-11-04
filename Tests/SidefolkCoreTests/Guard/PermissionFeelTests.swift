import Foundation
import Testing
@testable import SidefolkCore

/// The modes after D185: Full access is full access, and Auto is easygoing. These are the new rows of `ModeMatrixTests`,
/// independent of the table in `ModeMatrixTests`, so a slip in one shows against the other.
@Suite struct PermissionFeelTests {
    typealias Outcome = ModeMatrixTests.Outcome

    /// What Sidefolk's own agent gets in Full access: nothing asks, except text to read in full (a skill). A low-risk step that
    /// can't carry anything still just runs.
    static func fullAccess(_ shape: ModeMatrixTests.Shape, _ risk: Risk, tainted: Bool) -> Outcome {
        if shape == .fullText { return risk == .low ? .run : .ask }
        let carriesTaint = tainted && (shape == .network || shape == .memory)
        return risk == .low && !carriesTaint ? .run : .full
    }

    /// Auto: a step that can't carry data out runs even after outside content; the carry-out classes and high risk still ask.
    /// A file change asks here because the matrix names no folder: the folder tests below say when it runs.
    static func auto(_ shape: ModeMatrixTests.Shape, _ risk: Risk, tainted: Bool) -> Outcome {
        if shape == .fullText { return risk == .low ? .run : .ask }
        let carriesOut = [.network, .files, .memory, .shell, .extensionTool].contains(shape)
        switch risk {
        case .low: return tainted && (shape == .network || shape == .memory) ? .ask : .run
        case .medium: return tainted && carriesOut ? .ask : .auto
        case .high: return .ask
        }
    }

    @Test func fullAccessAsksNothing() {
        let matrix = ModeMatrixTests()
        for shape in ModeMatrixTests.Shape.allCases {
            for risk in Risk.allCases {
                for tainted in [false, true] {
                    let got = ModeMatrixTests.outcome(matrix.decide(shape, risk, tainted: tainted, caller: .agent(runId: "r"), mode: .fullAccess))
                    #expect(got == Self.fullAccess(shape, risk, tainted: tainted), "\(shape) \(risk) tainted=\(tainted)")
                }
            }
        }
    }

    @Test func autoOnlyAsksForWhatCanLeaveOrBeLost() {
        let matrix = ModeMatrixTests()
        for shape in ModeMatrixTests.Shape.allCases {
            for risk in Risk.allCases {
                for tainted in [false, true] {
                    let got = ModeMatrixTests.outcome(matrix.decide(shape, risk, tainted: tainted, caller: .agent(runId: "r"), mode: .auto))
                    #expect(got == Self.auto(shape, risk, tainted: tainted), "\(shape) \(risk) tainted=\(tainted)")
                }
            }
        }
    }

    /// The other modes and the other callers do not move.
    @Test func everythingElseIsAsItWas() {
        let matrix = ModeMatrix()
        for row in ModeMatrixTests.rows {
            for mode in [GuardMode.askEveryTime, .askOncePerKind] {
                let got = ModeMatrixTests.outcome(matrix.decide(row.shape, row.risk, tainted: row.tainted, caller: .agent(runId: "r"), mode: mode))
                #expect(got == row.agent[mode == .askEveryTime ? 0 : 1])
            }
            for caller in [Caller.external(client: "codex"), .extension(id: "dev.x.y"), .routine(id: "daily")] {
                for mode in ModeMatrixTests.modes where mode != .askEveryTime {
                    let got = ModeMatrixTests.outcome(matrix.decide(row.shape, row.risk, tainted: row.tainted, caller: caller, mode: mode))
                    #expect(got == row.agent[1], "\(row.shape) \(caller.kind) \(mode)")
                }
            }
        }
    }
}

private typealias ModeMatrix = ModeMatrixTests
