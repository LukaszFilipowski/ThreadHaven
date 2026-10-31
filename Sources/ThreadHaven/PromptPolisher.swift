import Foundation

enum PromptPolisher {
    static let instruction = """
    Rewrite the dictated note below into a clear, well-structured prompt for Claude Code (a coding agent). \
    Keep the original language of the note. Fix punctuation, typos and speech-recognition mistakes. \
    If the note contains several tasks, list them as bullet points. Do not add requirements that are not in the note. \
    Output only the final prompt text, with no preamble.
    """

    static func polish(_ text: String, model: String) async throws -> String {
        try await ClaudeCLI.run(instruction, input: text, model: model)
    }
}
