import Testing
@testable import ThreadHavenCore

struct CompactionSimulationTests {
    @Test func belowThresholdNothingChanges() {
        var simulation = CompactionSimulation(threshold: 100)
        simulation.add(contexts: [10, 20, 30], baseline: 10, summaryTokens: 5)
        #expect(simulation.actualTokens == 60)
        #expect(simulation.simulatedTokens == 60)
        #expect(simulation.compactions == 0)
        #expect(simulation.savedShare == 0)
    }

    @Test func compactsAndKeepsObservedGrowth() {
        var simulation = CompactionSimulation(threshold: 50)
        simulation.add(contexts: [20, 40, 60, 80, 100], baseline: 10, summaryTokens: 10)
        #expect(simulation.compactions == 2)
        #expect(simulation.actualTokens == 300)
        #expect(simulation.simulatedTokens == 20 + 40 + (60 + 20) + 40 + (60 + 20))
    }

    @Test func respectsCompactionsThatAlreadyHappened() {
        var simulation = CompactionSimulation(threshold: 1_000)
        simulation.add(contexts: [100, 300, 50, 80], baseline: 20, summaryTokens: 10)
        #expect(simulation.simulatedTokens == simulation.actualTokens)
    }

    @Test func ignoresThresholdsBelowRestartSize() {
        var simulation = CompactionSimulation(threshold: 10)
        simulation.add(contexts: [30, 60], baseline: 20, summaryTokens: 10)
        #expect(simulation.compactions == 0)
    }
}
