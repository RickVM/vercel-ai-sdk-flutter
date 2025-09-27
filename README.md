# vercel_ai_sdk

A Flutter-first client for consuming streaming responses from [Vercel AI SDK](https://sdk.vercel.ai/) chat endpoints. The package mirrors the structure of the companion Swift implementation so you can share concepts across iOS and Flutter apps while handling incremental chunks, reasoning traces, tool-call orchestration, and attachments.

## Features

- Handles the full Vercel AI streaming surface: text, reasoning, tool inputs/outputs, files, sources, data payloads, and metadata.
- Maintains chat state with helper models (`UiMessage`, `MessagePart`, `StreamingUiMessageState`) that match the Swift package semantics.
- Provides a default transport built on `HttpClient` plus an easy-to-mock `ChatTransport` interface for custom networking stacks.
- Supports auto-send recursion hooks and callbacks for finish events, tool invocations, additional data, and error reporting.

## Getting started

Add the dependency to your Flutter package:

```yaml
dependencies:
  vercel_ai_sdk:
    path: ./path/to/vercel_ai_sdk
```

Create a `Chat` instance with either the built-in transport (configure your base URL and path) or your own `ChatTransport` implementation:

```dart
final chat = Chat(
  generateId: () => DateTime.now().microsecondsSinceEpoch.toString(), // plug in your id generator
  state: ChatState(),
  transport: DefaultChatTransport(
    apiConfig: ChatTransportApiConfig(
      apiBaseUrl: 'https://your-api.example',
      apiChatPath: '/api/chat',
    ),
  ),
  onFinish: (message) => debugPrint('assistant finished with: ${message.id}'),
  onError: (error) => debugPrint('chat error: $error'),
);
```

## Usage

Send user input as text (files and richer inputs are supported via `SendFiles` and `SendExistingMessage`):

```dart
await chat.sendMessage(
  input: const SendText('How do I stream results from Vercel?'),
);

final assistant = chat.state.messages.last;
final streamedText = assistant.parts.whereType<TextPart>().map((part) => part.text).join();
```

You can listen to streaming progress by tapping into `chat.state` (via `ChangeNotifier`) or by supplying callbacks:

```dart
final chat = Chat(
  state: ChatState(),
  transport: myTransport,
  onToolCall: (toolChunk) {
    // React to tool-call requests from the model.
  },
  onData: (dataChunk) {
    // Receive custom `data-*` payloads as they arrive.
  },
);
```

To mock networking in tests, implement `ChatTransport` and return a `Stream<UiMessageChunk>`—see `test/vercel_ai_sdk_test.dart` for an example.

## Additional information

- Swift reference implementation: `/Users/oren.s/projects/personal/life-stats/life-stats-ios/swift-ai-sdk`
- The library is designed for extensibility—override `DefaultChatTransport` if you need custom authentication, retry policies, or platform-specific networking.
- Contributions and issues are welcome in your project repository.
