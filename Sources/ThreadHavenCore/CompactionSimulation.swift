import Foundation

public struct CompactionSimulation: Sendable, Equatable {
    public static let defaultSummaryTokens = 20_000

    public let threshold: Int
    public private(set) var actualTokens = 0
    public private(set) var simulatedTokens = 0
    public private(set) var compactions = 0

    public var savedShare: Double {
        actualTokens > 0 ? 1 - Double(simulatedTokens) / Double(actualTokens) : 0
    }

    public init(threshold: Int) {
        self.threshold = threshold
    }

    public mutating func add(contexts: [Int], baseline: Int, summaryTokens: Int = defaultSummaryTokens) {
        let restart = baseline + summaryTokens
        var current = 0
        var previous = 0
        for context in contexts {
            let growth = context - previous
            current = growth >= 0 ? current + growth : min(current, context)
            previous = context
            if current > threshold && threshold > restart {
                simulatedTokens += current
                compactions += 1
                current = restart
            }
            actualTokens += context
            simulatedTokens += current
        }
    }
}
