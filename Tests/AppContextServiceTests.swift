import Foundation

enum AppContextServiceTests {
    static func run() {
        testQwenRawOutputIsSummarized()
        testQwenReasoningOutputIsStripped()
        testNonStrippingModelPreservesExistingBehavior()
        testDeprecatedGroqModelsAreNotPredefined()
        testQwenCleanupDisablesReasoning()
        testContextRequestOmitsTemperatureAndPreservesMessages()
    }

    private static func testQwenRawOutputIsSummarized() {
        let output = """
        The user is replying to an email about the product launch. They likely intend to confirm the next steps. This third sentence should be dropped.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        TestSupport.expectEqual(
            summary,
            "The user is replying to an email about the product launch. They likely intend to confirm the next steps."
        )
    }

    private static func testQwenReasoningOutputIsStripped() {
        let output = """
        <think>
        Hidden chain of thought should never appear in context.
        It contains misleading details.
        </think>
        The user is editing a project note in FreeFlow. They likely intend to tighten the release wording.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        TestSupport.expectEqual(
            summary,
            "The user is editing a project note in FreeFlow. They likely intend to tighten the release wording."
        )
        TestSupport.expect(summary?.contains("Hidden chain of thought") == false, "Qwen reasoning leaked into summary")
    }

    private static func testNonStrippingModelPreservesExistingBehavior() {
        let output = "<think>Visible for non-stripping models.</think> The user is writing a status update."

        let summary = AppContextService.activitySummary(
            from: output,
            model: "meta-llama/llama-4-scout-17b-16e-instruct"
        )

        TestSupport.expectEqual(summary, output)
    }

    private static func testDeprecatedGroqModelsAreNotPredefined() {
        let deprecatedModels = [
            "qwen/qwen3-32b",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "llama-3.1-8b-instant",
            "llama-3.3-70b-versatile"
        ]

        for model in deprecatedModels {
            TestSupport.expect(!ModelConfiguration.llmModels.contains(model), "Deprecated model remains in picker: \(model)")
        }
        TestSupport.expect(ModelConfiguration.llmModels.contains("qwen/qwen3.6-27b"), "New fallback is missing from picker")
    }

    private static func testQwenCleanupDisablesReasoning() {
        let config = ModelConfiguration.config(for: "qwen/qwen3.6-27b")

        TestSupport.expect(config.reasoningEffort == "none", "Qwen cleanup should disable reasoning")
        TestSupport.expect(config.includeReasoning == false, "Qwen cleanup should exclude reasoning output")
    }

    private static func testContextRequestOmitsTemperatureAndPreservesMessages() {
        let screenshotMessage: [[String: Any]] = [
            ["type": "text", "text": "Analyze the screenshot plus metadata."],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,synthetic"]]
        ]
        let payload = AppContextService.contextRequestPayload(
            model: "gpt-6-luna",
            contextSystemPrompt: "Synthetic system prompt",
            userMessage: screenshotMessage
        )
        let messages = payload["messages"] as? [[String: Any]]
        let userContent = messages?.last?["content"] as? [[String: Any]]

        TestSupport.expect(payload["temperature"] == nil, "Context requests must use the provider's default sampling")
        TestSupport.expectEqual(payload["model"] as? String, "gpt-6-luna")
        TestSupport.expectEqual(messages?.first?["content"] as? String, "Synthetic system prompt")
        TestSupport.expectEqual(userContent?.count, 2)
        TestSupport.expectEqual(userContent?.last?["type"] as? String, "image_url")

        let textPayload = AppContextService.contextRequestPayload(
            model: "gpt-6-luna",
            contextSystemPrompt: "Synthetic system prompt",
            userMessage: "Synthetic text-only metadata"
        )
        let textMessages = textPayload["messages"] as? [[String: Any]]
        TestSupport.expectEqual(textMessages?.last?["content"] as? String, "Synthetic text-only metadata")
        TestSupport.expect(textPayload["temperature"] == nil, "Text fallback requests must also omit temperature")
    }
}
