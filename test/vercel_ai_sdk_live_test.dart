import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vercel_ai_sdk/vercel_ai_sdk.dart';

Map<String, String>? _decodeHeaders(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map((key, value) => MapEntry(key, value.toString()));
}

Map<String, Object?>? _decodeJsonMap(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  throw FormatException('Expected JSON object for integration test payload');
}

void main() {
  final baseUrl = Platform.environment['VERCEL_AI_SDK_BASE_URL'];
  final chatPath = Platform.environment['VERCEL_AI_SDK_CHAT_PATH'];
  final shouldRun =
      Platform.environment['VERCEL_AI_SDK_LIVE_TEST'] == '1' &&
      baseUrl != null &&
      chatPath != null;

  test(
    'live stream produces assistant response',
    () async {
      final headers =
          _decodeHeaders(Platform.environment['VERCEL_AI_SDK_HEADERS_JSON']);
      final body =
          _decodeJsonMap(Platform.environment['VERCEL_AI_SDK_BODY_JSON']);
      final metadata =
          _decodeJsonMap(Platform.environment['VERCEL_AI_SDK_METADATA_JSON']);

      final finishCompleter = Completer<UiMessage>();
      final errors = <Object>[];

      final chat = Chat(
        generateId: () => DateTime.now().microsecondsSinceEpoch.toString(),
        state: ChatState(),
        transport: DefaultChatTransport(
          apiConfig: ChatTransportApiConfig(
            apiBaseUrl: baseUrl!,
            apiChatPath: chatPath!,
            apiReconnectToStreamPath:
                Platform.environment['VERCEL_AI_SDK_RECONNECT_PATH'],
          ),
        ),
        onError: errors.add,
        onFinish: finishCompleter.complete,
      );

      final options = ChatRequestOptions(
        headers: headers,
        body: body,
        metadata: metadata,
      );

      await chat.sendMessage(
        input: const SendText('Hello from vercel_ai_sdk live test'),
        options: options,
      );

      final message = await finishCompleter.future
          .timeout(const Duration(seconds: 30));

      final assistantText = message.parts
          .whereType<TextPart>()
          .map((part) => part.text)
          .join()
          .trim();

      expect(errors, isEmpty, reason: 'chat reported unexpected errors');
      expect(assistantText, isNotEmpty,
          reason: 'expected at least one text chunk from assistant');
    },
    skip: shouldRun
        ? false
        : 'Set VERCEL_AI_SDK_LIVE_TEST=1, VERCEL_AI_SDK_BASE_URL, and '
            'VERCEL_AI_SDK_CHAT_PATH (optionally *_JSON for headers/body) to run',
  );
}
