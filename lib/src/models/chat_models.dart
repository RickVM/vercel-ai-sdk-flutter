import 'package:flutter/foundation.dart';

import 'messages.dart';
import '../chat/streaming_state.dart';

class ChatException implements Exception {
  const ChatException(this.code, {this.messageId});

  final ChatExceptionCode code;
  final String? messageId;

  @override
  String toString() =>
      'ChatException(code: '
      '\$code, messageId: '
      '\$messageId)';
}

enum ChatExceptionCode {
  messageNotFound,
  notUserMessage,
  invalidLastSessionMessage,
  tooManyRecursionAttempts,
  invalidTransportConfiguration,
}

enum ChatRequestTrigger {
  submitMessage('submit-message'),
  resumeStream('resume-stream'),
  regenerateMessage('regenerate-message');

  const ChatRequestTrigger(this.wireValue);

  final String wireValue;
}

class ChatRequestOptions {
  const ChatRequestOptions({this.headers, this.body, this.metadata});

  final Map<String, String>? headers;
  final Map<String, Object?>? body;
  final Map<String, Object?>? metadata;
}

class MakeRequestInput {
  const MakeRequestInput({required this.trigger, this.messageId, this.options});

  final ChatRequestTrigger trigger;
  final String? messageId;
  final ChatRequestOptions? options;
}

class ActiveResponse {
  ActiveResponse({required this.state, this.cancel});

  StreamingUiMessageState state;
  VoidCallback? cancel;
}

enum ChatStatus { submitted, streaming, ready, error }

class ChatState extends ChangeNotifier {
  ChatState({
    List<UiMessage>? messages,
    this.status = ChatStatus.ready,
    this.error,
  }) : _messages = List.of(messages ?? <UiMessage>[]);

  ChatStatus status;
  Object? error;
  final List<UiMessage> _messages;

  List<UiMessage> get messages => List.unmodifiable(_messages);

  void pushMessage(UiMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  void popMessage() {
    if (_messages.isNotEmpty) {
      _messages.removeLast();
      notifyListeners();
    }
  }

  void replaceMessage(int index, UiMessage message) {
    _messages[index] = message;
    notifyListeners();
  }

  void replaceAll(List<UiMessage> messages) {
    _messages
      ..clear()
      ..addAll(messages);
    notifyListeners();
  }

  void setStatus(ChatStatus newStatus, {Object? error}) {
    status = newStatus;
    this.error = error;
    notifyListeners();
  }

  void clearError() {
    if (status == ChatStatus.error) {
      error = null;
      notifyListeners();
    }
  }
}

typedef ChatOnErrorCallback = void Function(Object error);
typedef ChatOnFinishCallback = void Function(UiMessage message);
typedef ChatOnToolCallCallback = void Function(Object toolCall);
typedef ChatOnDataCallback = void Function(Object data);
typedef SendAutomaticallyWhen = bool Function(List<UiMessage> messages);
