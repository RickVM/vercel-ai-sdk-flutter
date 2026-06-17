import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vercel_ai_sdk/vercel_ai_sdk.dart';

void main() {
  test('throws HTTP exception with response body details', () async {
    const responseBody =
        'Your credit balance is too low to access the Anthropic API.';
    final transport = DefaultChatTransport(
      apiConfig: ChatTransportApiConfig(
        apiBaseUrl: 'https://example.com',
        apiChatPath: '/api/chat',
      ),
      client: _RespondingClient(
        http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(responseBody)),
          402,
        ),
      ),
    );

    await expectLater(
      transport.sendMessages(
        chatId: 'chat-1',
        trigger: ChatRequestTrigger.submitMessage,
      ),
      throwsA(
        isA<TransportHttpException>()
            .having((error) => error.statusCode, 'statusCode', 402)
            .having(
              (error) => error.message,
              'message',
              contains('credit balance'),
            )
            .having(
              (error) => error.responseBody,
              'responseBody',
              contains('Anthropic API'),
            ),
      ),
    );
  });

  test('uses JSON error message when available', () async {
    final transport = DefaultChatTransport(
      apiConfig: ChatTransportApiConfig(
        apiBaseUrl: 'https://example.com',
        apiChatPath: '/api/chat',
      ),
      client: _RespondingClient(
        http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(jsonEncode(<String, String>{
              'message': 'Chat provider is unavailable.',
            })),
          ),
          503,
        ),
      ),
    );

    await expectLater(
      transport.sendMessages(
        chatId: 'chat-1',
        trigger: ChatRequestTrigger.submitMessage,
      ),
      throwsA(
        isA<TransportHttpException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.message,
              'message',
              'Chat provider is unavailable.',
            ),
      ),
    );
  });
}

class _RespondingClient extends http.BaseClient {
  _RespondingClient(this.response);

  final http.StreamedResponse response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return response;
  }
}
