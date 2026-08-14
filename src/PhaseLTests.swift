import Foundation

// ============================================================================
// Phase L — bounded hostile property campaign contract.
// The campaign uses only deterministic disposable fixtures rooted in /private/tmp.
// It is evidence for its fixed seed and count, not a universal proof.
// ============================================================================

final class PhaseLTests {
    private var pass = 0
    private var fail = 0

    private func check(_ id: String, _ description: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("PASS  \(id)  \(description)")
            pass += 1
        } else {
            print("FAIL  \(id)  \(description)\(detail.isEmpty ? "" : " — \(detail)")")
            fail += 1
        }
    }

    func runAll() -> Bool {
        let output = URL(fileURLWithPath: "/private/tmp/desktidy-phase-l-test-\(PhaseLCampaignConfiguration.seed).jsonl")
        defer { try? FileManager.default.removeItem(at: output) }
        do {
            let result = try PhaseLCampaign(outputURL: output).run()
            let records = try PhaseLRawRecord.readJSONL(from: output)
            check(
                "L01",
                "the canonical core and mover complete exactly the fixed hostile matrix with unique IDs and nonzero checks",
                result.totalCases == PhaseLCampaignConfiguration.expectedCaseCount
                    && result.passedCases == PhaseLCampaignConfiguration.expectedCaseCount
                    && result.failedCases == 0
                    && result.timedOutCases == 0
                    && records.count == PhaseLCampaignConfiguration.expectedCaseCount
                    && Set(records.map(\.id)).count == PhaseLCampaignConfiguration.expectedCaseCount
                    && records.allSatisfy { $0.checks > 0 && $0.status == .passed }
            )
        } catch {
            check("L01", "the bounded hostile campaign produces verifiable raw evidence", false, error.localizedDescription)
        }
        print("PHASE L GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }
}
