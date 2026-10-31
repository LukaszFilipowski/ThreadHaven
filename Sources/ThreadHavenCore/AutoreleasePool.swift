import Foundation

func withAutoreleasePool<Result>(_ body: () throws -> Result) rethrows -> Result {
    #if canImport(ObjectiveC)
    try autoreleasepool(invoking: body)
    #else
    try body()
    #endif
}
