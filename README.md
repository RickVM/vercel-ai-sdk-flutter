## Contributions Are Welcome

# Flutter AI SDK

Flutter package for consuming AI chat streams from a [Vercel AI SDK](https://ai-sdk.dev/) v5 backend.

## Installation

```yaml
dependencies:
    vercel_ai_sdk: ^1.0.0
```

## Basic Usage

```dart
import 'package:flutter/foundation.dart';
import 'package:vercel_ai_sdk/vercel_ai_sdk.dart';

class ChatManager extends ChangeNotifier {
  ChatManager() {
    chatState.addListener(_stateListener);
    _setupChat();
  }

  final ChatState chatState = ChatState();
  late final VoidCallback _stateListener = notifyListeners;
  Chat? _chat;
  String prompt = '';
  Future<void>? _currentRequest;

  bool get isStreaming => _currentRequest != null;

  void _setupChat() {
    final apiConfig = ChatTransportApiConfig(
      apiBaseUrl: 'https://your-api.com',
      apiChatPath: '/chat',
    );

    _chat = Chat(
      state: chatState,
      defaultChatTransportApiConfig: apiConfig,
      generateId: () => DateTime.now().microsecondsSinceEpoch.toString(),
      onError: (_) => notifyListeners(),
      onFinish: (_) => notifyListeners(),
    );
  }

  Future<void> generate() async {
    final chat = _chat;
    if (chat == null) return;

    final text = prompt.trim();
    if (text.isEmpty) return;

    prompt = '';
    notifyListeners();

    _currentRequest = chat.sendMessage(
      input: SendText(text),
    );

    try {
      await _currentRequest;
    } finally {
      _currentRequest = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    chatState.removeListener(_stateListener);
    super.dispose();
  }
}
```

## Custom Transport with Auth

```dart
import 'package:vercel_ai_sdk/vercel_ai_sdk.dart';

class CustomChatTransport extends DefaultChatTransport {
  CustomChatTransport({required super.apiConfig});

  @override
  Future<Stream<UiMessageChunk>> sendMessages({
    required String chatId,
    required List<UiMessage> messages,
    Future<void>? abortSignal,
    Map<String, Object?>? metadata,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    required ChatRequestTrigger trigger,
    String? messageId,
  }) async {
    final requestBody = <String, Object?>{
      'timezone': DateTime.now().timeZoneName,
      'chatType': 'app',
      ...?body,
    };

    final token = 'your-auth-token';
    final mergedHeaders = {
      ...?headers,
      'Authorization': 'Bearer $token',
    };

    return super.sendMessages(
      chatId: chatId,
      messages: messages,
      abortSignal: abortSignal,
      metadata: metadata,
      headers: mergedHeaders,
      body: requestBody,
      trigger: trigger,
      messageId: messageId,
    );
  }
}

// Usage
final apiConfig = ChatTransportApiConfig(
  apiBaseUrl: 'https://your-api.com',
  apiChatPath: '/chat',
);
final chat = Chat(
  state: ChatState(),
  transport: CustomChatTransport(apiConfig: apiConfig),
  generateId: () => DateTime.now().microsecondsSinceEpoch.toString(),
  onError: (error) => debugPrint('chat error: $error'),
  onFinish: (message) => debugPrint('assistant finished with ${message.id}'),
);
```

## Send Files

```dart
import 'package:vercel_ai_sdk/vercel_ai_sdk.dart';

Future<void> sendMessageWithFiles(Chat chat, String text, List<FileReference> files) async {
  await chat.sendMessage(
    input: SendText(
      text,
      files: files,
    ),
  );
}

// Example usage
final file = FileReference(
  filename: 'transcript.pdf',
  url: Uri.parse('https://storage.example/transcript.pdf'),
  mediaType: 'application/pdf',
);
await sendMessageWithFiles(chat, 'Summarize this document', [file]);
```
