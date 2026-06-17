import 'package:flutter_test/flutter_test.dart';
import 'package:vercel_ai_sdk/vercel_ai_sdk.dart';

class FakeTransport implements ChatTransport {
  FakeTransport(this.chunks);

  final List<UiMessageChunk> chunks;
  List<UiMessage>? capturedMessages;
  ChatRequestTrigger? capturedTrigger;

  @override
  Future<Stream<UiMessageChunk>> sendMessages({
    required String chatId,
    List<UiMessage>? messages,
    UiMessage? message,
    Future<void>? abortSignal,
    Map<String, Object?>? metadata,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    required ChatRequestTrigger trigger,
    String? messageId,
  }) async {
    capturedMessages = messages == null ? null : List.of(messages);
    capturedTrigger = trigger;
    return Stream<UiMessageChunk>.fromIterable(chunks);
  }

  @override
  Future<Stream<UiMessageChunk>?> reconnectToStream({
    required String chatId,
    Map<String, Object?>? metadata,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    String? path,
  }) async {
    return null;
  }
}

void main() {
  test('chat processes streaming text chunks', () async {
    final transport = FakeTransport([
      StartChunk(messageId: 'assistant-1', messageMetadata: null),
      TextStartChunk(id: 'text-part', providerMetadata: null),
      TextDeltaChunk(id: 'text-part', delta: 'Hello', providerMetadata: null),
      TextEndChunk(id: 'text-part', providerMetadata: null),
      FinishChunk(messageMetadata: null),
    ]);

    var counter = 0;
    String generateId() => 'id-${counter++}';

    final chat = Chat(
      generateId: generateId,
      state: ChatState(),
      transport: transport,
    );

    await chat.sendMessage(input: const SendText('Hi there'));

    final messages = chat.state.messages;
    expect(messages.length, 2);
    expect(messages.first.role, UiMessageRole.user);
    expect(messages.first.parts.whereType<TextPart>().first.text, 'Hi there');
    expect(messages.last.role, UiMessageRole.assistant);
    final assistantText = messages.last.parts.whereType<TextPart>().first;
    expect(assistantText.text, 'Hello');
    expect(transport.capturedTrigger, ChatRequestTrigger.submitMessage);
  });

  test('chat treats stream error chunks as request failures', () async {
    final transport = FakeTransport([
      const ErrorChunk(
        errorText:
            'Your credit balance is too low to access the Anthropic API.',
      ),
    ]);
    final errors = <Object>[];

    var counter = 0;
    String generateId() => 'id-${counter++}';

    final chat = Chat(
      generateId: generateId,
      state: ChatState(),
      transport: transport,
      onError: errors.add,
    );

    await expectLater(
      chat.sendMessage(input: const SendText('Hi there')),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('credit balance'),
        ),
      ),
    );

    expect(chat.state.status, ChatStatus.error);
    expect(chat.state.error, isA<Exception>());
    expect(errors, hasLength(1));
    expect(errors.single.toString(), contains('credit balance'));
  });
}
