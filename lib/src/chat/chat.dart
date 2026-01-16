import 'dart:async';
import 'dart:math';

import '../models/chat_models.dart';
import '../models/messages.dart';
import '../models/chunks.dart';
import '../transport/chat_transport.dart';
import 'streaming_state.dart';

class Chat {
  Chat({
    String? id,
    ChatState? state,
    String Function()? generateId,
    this.onError,
    this.onFinish,
    this.onToolCall,
    this.onData,
    this.sendAutomaticallyWhen,
    ChatTransport? transport,
    ChatTransportApiConfig? defaultChatTransportApiConfig,
    this.maxToolCalls = 10,
  }) : _generateId = generateId ?? _defaultIdGenerator,
       state = state ?? ChatState(),
       transport =
           transport ?? _resolveTransport(defaultChatTransportApiConfig, id) {
    this.id = id ?? _generateId();
    _messages = List.of(this.state.messages);
    _syncStateMessages();
  }

  late final String id;
  final ChatState state;
  final String Function() _generateId;
  final ChatOnErrorCallback? onError;
  final ChatOnFinishCallback? onFinish;
  final ChatOnToolCallCallback? onToolCall;
  final ChatOnDataCallback? onData;
  final SendAutomaticallyWhen? sendAutomaticallyWhen;
  final ChatTransport transport;
  final int maxToolCalls;

  late List<UiMessage> _messages;
  ActiveResponse? _activeResponse;
  StreamSubscription<UiMessageChunk>? _activeStreamSubscription;
  int _autoSendRecursionCount = 0;

  ChatStatus get status => state.status;
  Object? get error => state.error;

  UiMessage? get lastMessage => _messages.isEmpty ? null : _messages.last;

  List<UiMessage> get messages => List.unmodifiable(_messages);

  ActiveResponse? get activeResponse => _activeResponse;

  Future<void> sendMessage({
    required SendMessageInput input,
    ChatRequestOptions? options,
  }) async {
    if (input is SendNone) {
      await makeRequest(
        input: MakeRequestInput(
          trigger: ChatRequestTrigger.submitMessage,
          messageId: lastMessage?.id,
          options: options,
        ),
      );
      return;
    }

    if (input is SendExistingMessage) {
      _insertOrReplaceUserMessage(input.message, targetId: input.messageId);
      await makeRequest(
        input: MakeRequestInput(
          trigger: ChatRequestTrigger.submitMessage,
          messageId: input.messageId,
          options: options,
        ),
      );
      return;
    }

    if (input is SendText) {
      final fileParts = _convertFilesToParts(input.files);
      final textPart = TextPart(text: input.text);
      final parts = <MessagePart>[...fileParts, textPart];
      final newMessage = UiMessage(
        id: input.messageId ?? _generateId(),
        role: UiMessageRole.user,
        parts: parts,
        metadata: input.metadata,
      );
      _insertOrReplaceUserMessage(newMessage, targetId: input.messageId);
      await makeRequest(
        input: MakeRequestInput(
          trigger: ChatRequestTrigger.submitMessage,
          messageId: input.messageId,
          options: options,
        ),
      );
      return;
    }

    if (input is SendFiles) {
      final fileParts = _convertFilesToParts(input.files);
      final newMessage = UiMessage(
        id: input.messageId ?? _generateId(),
        role: UiMessageRole.user,
        parts: fileParts,
        metadata: input.metadata,
      );
      _insertOrReplaceUserMessage(newMessage, targetId: input.messageId);
      await makeRequest(
        input: MakeRequestInput(
          trigger: ChatRequestTrigger.submitMessage,
          messageId: input.messageId,
          options: options,
        ),
      );
      return;
    }

    throw ArgumentError('Unsupported send message input: ${input.runtimeType}');
  }

  Future<void> makeRequest({required MakeRequestInput input}) async {
    _setStatus(ChatStatus.submitted);

    final streamingState = _createStreamingUiMessageState(
      lastMessage: lastMessage,
      messageId: _generateId(),
    );

    _activeResponse = ActiveResponse(state: streamingState);

    Stream<UiMessageChunk>? stream;

    try {
      if (input.trigger == ChatRequestTrigger.resumeStream) {
        stream = await _resumeStream(input);
        if (stream == null) {
          _setStatus(ChatStatus.ready);
          _activeResponse = null;
          return;
        }
      } else {
        stream = await transport.sendMessages(
          chatId: id,
          messages: _messages,
          message: lastMessage,
          abortSignal: null,
          metadata: input.options?.metadata,
          headers: input.options?.headers,
          body: input.options?.body,
          trigger: input.trigger,
          messageId: input.messageId,
        );
      }

      Object? thrownError;
      final processedStream = processUiMessageStream(
        ProcessUiMessageStreamOptions(
          stream: stream,
          runUpdateMessageJob: (chunk) async {
            _setStatus(ChatStatus.streaming);
            await _handleChunk(chunk);
          },
          onError: (error) {
            thrownError = error;
            onError?.call(error);
          },
        ),
      );

      final streamCompleter = Completer<void>();
      var wasCancelled = false;

      late final StreamSubscription<UiMessageChunk> subscription;
      subscription = processedStream.listen(
        (_) {},
        onError: (error, stackTrace) {
          if (!streamCompleter.isCompleted) {
            streamCompleter.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!streamCompleter.isCompleted) {
            streamCompleter.complete();
          }
        },
      );

      _activeStreamSubscription = subscription;
      _activeResponse?.cancel = () async {
        if (wasCancelled) {
          return;
        }
        wasCancelled = true;
        await subscription.cancel();
        if (!streamCompleter.isCompleted) {
          streamCompleter.complete();
        }
      };

      try {
        await streamCompleter.future;
      } finally {
        await subscription.cancel();
        _activeStreamSubscription = null;
      }

      if (wasCancelled) {
        _setStatus(ChatStatus.ready);
        return;
      }

      if (thrownError != null) {
        throw thrownError!;
      }

      final lastSessionMessage = _activeResponse?.state.message ?? lastMessage;
      if (lastSessionMessage == null) {
        throw ChatException(
          ChatExceptionCode.invalidLastSessionMessage,
          messageId: input.messageId ?? 'unknown',
        );
      }

      onFinish?.call(lastSessionMessage);
      _setStatus(ChatStatus.ready);
    } catch (error) {
      if (error is ChatException &&
          error.code == ChatExceptionCode.invalidLastSessionMessage) {
        _setStatus(ChatStatus.ready);
      } else {
        onError?.call(error);
        _setStatus(ChatStatus.error, error: error);
      }
      rethrow;
    } finally {
      _activeResponse = null;
    }

    if (sendAutomaticallyWhen != null && sendAutomaticallyWhen!(_messages)) {
      if (_autoSendRecursionCount >= maxToolCalls) {
        throw ChatException(
          ChatExceptionCode.tooManyRecursionAttempts,
          messageId: input.messageId ?? 'unknown',
        );
      }
      _autoSendRecursionCount += 1;
      try {
        await makeRequest(
          input: MakeRequestInput(
            trigger: ChatRequestTrigger.submitMessage,
            messageId: lastMessage?.id,
            options: input.options,
          ),
        );
      } finally {
        _autoSendRecursionCount -= 1;
      }
    }
  }

  void _setStatus(ChatStatus status, {Object? error}) {
    if (state.status == status && error == null) {
      return;
    }
    state.setStatus(status, error: error);
  }

  void clearError() {
    state.clearError();
  }

  Future<void> cancelActiveResponse() async {
    final active = _activeResponse;
    if (active == null) {
      return;
    }

    final cancel = active.cancel;
    if (cancel != null) {
      await cancel();
      _activeStreamSubscription = null;
    } else {
      await _activeStreamSubscription?.cancel();
      _activeStreamSubscription = null;
    }

    _removeMessageById(active.state.message.id);
    _activeResponse = null;
    _setStatus(ChatStatus.ready);
  }

  Future<void> _handleChunk(UiMessageChunk chunk) async {
    final active = _activeResponse;
    if (active == null) {
      return;
    }

    var shouldUpdateList = false;

    if (chunk is TextStartChunk) {
      final textPart = TextPart(
        text: '',
        state: MessagePartState.streaming,
        providerMetadata: chunk.providerMetadata,
      );
      active.state.activeTextParts[chunk.id] = textPart;
      active.state.message.parts.add(textPart);
      shouldUpdateList = true;
    } else if (chunk is TextDeltaChunk) {
      final textPart = active.state.activeTextParts[chunk.id];
      if (textPart != null) {
        textPart.text += chunk.delta;
        if (chunk.providerMetadata != null) {
          textPart.providerMetadata = chunk.providerMetadata;
        }
        shouldUpdateList = true;
      }
    } else if (chunk is TextEndChunk) {
      final textPart = active.state.activeTextParts.remove(chunk.id);
      if (textPart != null) {
        if (chunk.providerMetadata != null) {
          textPart.providerMetadata = chunk.providerMetadata;
        }
        textPart.state = MessagePartState.done;
        shouldUpdateList = true;
      }
    } else if (chunk is ReasoningStartChunk) {
      final reasoningPart = ReasoningPart(
        text: '',
        state: MessagePartState.streaming,
        providerMetadata: chunk.providerMetadata,
      );
      active.state.activeReasoningParts[chunk.id] = reasoningPart;
      active.state.message.parts.add(reasoningPart);
      shouldUpdateList = true;
    } else if (chunk is ReasoningDeltaChunk) {
      final reasoningPart = active.state.activeReasoningParts[chunk.id];
      if (reasoningPart is ReasoningPart) {
        reasoningPart.text += chunk.delta;
        if (chunk.providerMetadata != null) {
          reasoningPart.providerMetadata = chunk.providerMetadata;
        }
        shouldUpdateList = true;
      }
    } else if (chunk is ReasoningEndChunk) {
      final reasoningPart = active.state.activeReasoningParts.remove(chunk.id);
      if (reasoningPart is ReasoningPart) {
        if (chunk.providerMetadata != null) {
          reasoningPart.providerMetadata = chunk.providerMetadata;
        }
        reasoningPart.state = MessagePartState.done;
        shouldUpdateList = true;
      }
    } else if (chunk is ReasoningChunk) {
      final reasoningPart = ReasoningPart(
        text: chunk.text,
        providerMetadata: chunk.providerMetadata,
      );
      active.state.message.parts.add(reasoningPart);
      shouldUpdateList = true;
    } else if (chunk is ReasoningPartFinishChunk) {
      // No-op
    } else if (chunk is ErrorChunk) {
      onError?.call(Exception(chunk.errorText));
      return;
    } else if (chunk is ToolInputStartChunk) {
      if (chunk.isDynamic == true) {
        final dynamicToolPart = DynamicToolPart(
          toolName: chunk.toolName,
          toolCallId: chunk.toolCallId,
          state: ToolCallState.inputStreaming,
        );
        active.state.message.parts.add(dynamicToolPart);
      } else {
        final toolPart = ToolPart(
          toolName: chunk.toolName,
          toolCallId: chunk.toolCallId,
          state: ToolCallState.inputStreaming,
          providerExecuted: chunk.providerExecuted,
        );
        active.state.message.parts.add(toolPart);
      }
      shouldUpdateList = true;
    } else if (chunk is ToolInputDeltaChunk) {
      final toolPart = _findToolPart(active.state, chunk.toolCallId);
      if (toolPart != null) {
        final current = toolPart.input is String
            ? toolPart.input as String
            : '';
        toolPart.input = '$current${chunk.inputTextDelta}';
        shouldUpdateList = true;
      } else {
        final dynamicToolPart = _findDynamicToolPart(
          active.state,
          chunk.toolCallId,
        );
        if (dynamicToolPart != null) {
          final current = dynamicToolPart.input is String
              ? dynamicToolPart.input as String
              : '';
          dynamicToolPart.input = '$current${chunk.inputTextDelta}';
          shouldUpdateList = true;
        }
      }
    } else if (chunk is ToolInputAvailableChunk) {
      if (chunk.isDynamic == true) {
        final dynamicToolPart = _findDynamicToolPart(
          active.state,
          chunk.toolCallId,
        );
        if (dynamicToolPart != null) {
          dynamicToolPart.state = ToolCallState.inputAvailable;
          dynamicToolPart.input = chunk.input;
          dynamicToolPart.callProviderMetadata = chunk.providerMetadata;
        } else {
          active.state.message.parts.add(
            DynamicToolPart(
              toolName: chunk.toolName,
              toolCallId: chunk.toolCallId,
              state: ToolCallState.inputAvailable,
              input: chunk.input,
              callProviderMetadata: chunk.providerMetadata,
            ),
          );
        }
      } else {
        final toolPart = _findToolPart(active.state, chunk.toolCallId);
        if (toolPart != null) {
          toolPart.state = ToolCallState.inputAvailable;
          toolPart.input = chunk.input;
          toolPart.providerExecuted = chunk.providerExecuted;
          toolPart.callProviderMetadata = chunk.providerMetadata;
        } else {
          active.state.message.parts.add(
            ToolPart(
              toolName: chunk.toolName,
              toolCallId: chunk.toolCallId,
              state: ToolCallState.inputAvailable,
              input: chunk.input,
              providerExecuted: chunk.providerExecuted,
              callProviderMetadata: chunk.providerMetadata,
            ),
          );
        }
      }
      if (chunk.providerExecuted != true) {
        onToolCall?.call(chunk);
      }
      shouldUpdateList = true;
    } else if (chunk is ToolInputErrorChunk) {
      if (chunk.isDynamic == true) {
        final dynamicToolPart = _findDynamicToolPart(
          active.state,
          chunk.toolCallId,
        );
        if (dynamicToolPart != null) {
          dynamicToolPart.state = ToolCallState.outputError;
          dynamicToolPart.input = chunk.input;
          dynamicToolPart.errorText = chunk.errorText;
          dynamicToolPart.callProviderMetadata = chunk.providerMetadata;
        } else {
          active.state.message.parts.add(
            DynamicToolPart(
              toolName: chunk.toolName,
              toolCallId: chunk.toolCallId,
              state: ToolCallState.outputError,
              input: chunk.input,
              errorText: chunk.errorText,
              callProviderMetadata: chunk.providerMetadata,
            ),
          );
        }
      } else {
        final toolPart = _findToolPart(active.state, chunk.toolCallId);
        if (toolPart != null) {
          toolPart.state = ToolCallState.outputError;
          toolPart.input = chunk.input;
          toolPart.errorText = chunk.errorText;
          toolPart.providerExecuted = chunk.providerExecuted;
          toolPart.callProviderMetadata = chunk.providerMetadata;
        } else {
          active.state.message.parts.add(
            ToolPart(
              toolName: chunk.toolName,
              toolCallId: chunk.toolCallId,
              state: ToolCallState.outputError,
              input: chunk.input,
              errorText: chunk.errorText,
              providerExecuted: chunk.providerExecuted,
              callProviderMetadata: chunk.providerMetadata,
            ),
          );
        }
      }
      shouldUpdateList = true;
    } else if (chunk is ToolOutputAvailableChunk) {
      if (chunk.isDynamic == true) {
        final dynamicToolPart = _findDynamicToolPart(
          active.state,
          chunk.toolCallId,
        );
        if (dynamicToolPart != null) {
          dynamicToolPart.state = ToolCallState.outputAvailable;
          dynamicToolPart.output = chunk.output;
          dynamicToolPart.preliminary = chunk.preliminary;
          shouldUpdateList = true;
        }
      } else {
        final toolPart = _findToolPart(active.state, chunk.toolCallId);
        if (toolPart != null) {
          toolPart.state = ToolCallState.outputAvailable;
          toolPart.output = chunk.output;
          toolPart.providerExecuted = chunk.providerExecuted;
          toolPart.preliminary = chunk.preliminary;
          shouldUpdateList = true;
        }
      }
    } else if (chunk is ToolOutputErrorChunk) {
      if (chunk.isDynamic == true) {
        final dynamicToolPart = _findDynamicToolPart(
          active.state,
          chunk.toolCallId,
        );
        if (dynamicToolPart != null) {
          dynamicToolPart.state = ToolCallState.outputError;
          dynamicToolPart.errorText = chunk.errorText;
          shouldUpdateList = true;
        }
      } else {
        final toolPart = _findToolPart(active.state, chunk.toolCallId);
        if (toolPart != null) {
          toolPart.state = ToolCallState.outputError;
          toolPart.errorText = chunk.errorText;
          toolPart.providerExecuted = chunk.providerExecuted;
          shouldUpdateList = true;
        }
      }
    } else if (chunk is FileChunk) {
      final filePart = FilePart(
        url: chunk.url,
        mediaType: chunk.mediaType,
        providerMetadata: chunk.providerMetadata,
      );
      active.state.message.parts.add(filePart);
      shouldUpdateList = true;
    } else if (chunk is SourceUrlChunk) {
      final sourceUrlPart = SourceUrlPart(
        sourceId: chunk.sourceId,
        url: chunk.url,
        title: chunk.title,
        providerMetadata: chunk.providerMetadata,
      );
      active.state.message.parts.add(sourceUrlPart);
      shouldUpdateList = true;
    } else if (chunk is SourceDocumentChunk) {
      final sourceDocumentPart = SourceDocumentPart(
        sourceId: chunk.sourceId,
        mediaType: chunk.mediaType,
        title: chunk.title,
        filename: chunk.filename,
        providerMetadata: chunk.providerMetadata,
      );
      active.state.message.parts.add(sourceDocumentPart);
      shouldUpdateList = true;
    } else if (chunk is StartStepChunk) {
      active.state.message.parts.add(const StepStartPart());
      shouldUpdateList = true;
    } else if (chunk is FinishStepChunk) {
      active.state.activeTextParts.clear();
      active.state.activeReasoningParts.clear();
    } else if (chunk is StartChunk) {
      if (chunk.messageId != null) {
        active.state.message.id = chunk.messageId!;
      }
      if (chunk.messageMetadata is Map<String, dynamic>) {
        active.state.message.metadata = Map<String, Object?>.from(
          chunk.messageMetadata as Map<String, dynamic>,
        );
      }
      shouldUpdateList = true;
    } else if (chunk is FinishChunk) {
      if (chunk.messageMetadata is Map<String, dynamic>) {
        active.state.message.metadata = Map<String, Object?>.from(
          chunk.messageMetadata as Map<String, dynamic>,
        );
      }
      shouldUpdateList = true;
    } else if (chunk is MessageMetadataChunk) {
      if (chunk.messageMetadata is Map<String, dynamic>) {
        active.state.message.metadata = Map<String, Object?>.from(
          chunk.messageMetadata as Map<String, dynamic>,
        );
      }
      shouldUpdateList = true;
    } else if (chunk is DataChunk) {
      if (chunk.transient != true) {
        final dataPart = DataPart(
          dataName: chunk.dataName,
          data: chunk.data,
          id: chunk.id,
        );
        active.state.message.parts.add(dataPart);
        shouldUpdateList = true;
      }
      onData?.call(chunk);
    } else if (chunk is AbortChunk) {
      return;
    } else {
      return;
    }

    if (!shouldUpdateList) {
      return;
    }

    final latest = lastMessage;
    if (latest != null &&
        latest.id == active.state.message.id &&
        _messages.isNotEmpty) {
      _messages[_messages.length - 1] = active.state.message;
    } else {
      _messages.add(active.state.message);
    }

    _syncStateMessages();
  }

  Future<Stream<UiMessageChunk>?> _resumeStream(MakeRequestInput input) async {
    final stream = await transport.reconnectToStream(
      chatId: id,
      metadata: input.options?.metadata,
      headers: input.options?.headers,
      body: input.options?.body,
      path: null,
    );
    return stream;
  }

  void _insertOrReplaceUserMessage(UiMessage message, {String? targetId}) {
    if (targetId != null) {
      final index = _messages.indexWhere((element) => element.id == targetId);
      if (index == -1) {
        throw ChatException(
          ChatExceptionCode.messageNotFound,
          messageId: targetId,
        );
      }
      if (_messages[index].role != UiMessageRole.user) {
        throw ChatException(
          ChatExceptionCode.notUserMessage,
          messageId: targetId,
        );
      }
      _messages = _messages.sublist(0, index + 1);
      _messages[index] = message;
    } else {
      _messages.add(message);
    }
    _syncStateMessages();
  }

  ToolPart? _findToolPart(StreamingUiMessageState state, String toolCallId) {
    for (final part in state.message.parts) {
      if (part is ToolPart && part.toolCallId == toolCallId) {
        return part;
      }
    }
    return null;
  }

  DynamicToolPart? _findDynamicToolPart(
    StreamingUiMessageState state,
    String toolCallId,
  ) {
    for (final part in state.message.parts) {
      if (part is DynamicToolPart && part.toolCallId == toolCallId) {
        return part;
      }
    }
    return null;
  }

  List<FilePart> _convertFilesToParts(List<FileReference>? files) {
    if (files == null || files.isEmpty) {
      return const <FilePart>[];
    }
    return files
        .map(
          (file) => FilePart(
            filename: file.filename,
            url: file.url.toString(),
            mediaType: file.mediaType,
          ),
        )
        .toList();
  }

  StreamingUiMessageState _createStreamingUiMessageState({
    required UiMessage? lastMessage,
    required String messageId,
  }) {
    if (lastMessage != null && lastMessage.role == UiMessageRole.assistant) {
      return StreamingUiMessageState(message: lastMessage);
    }
    return StreamingUiMessageState(
      message: UiMessage(
        id: messageId,
        role: UiMessageRole.assistant,
        parts: <MessagePart>[],
      ),
    );
  }

  void _removeMessageById(String messageId) {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index == -1) {
      return;
    }
    _messages.removeAt(index);
    _syncStateMessages();
  }

  void _syncStateMessages() {
    state.replaceAll(_messages);
  }

  static final Random _random = Random();

  static String _defaultIdGenerator() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(0x7fffffff).toRadixString(16);
    return '$timestamp-$randomPart';
  }

  static ChatTransport _resolveTransport(
    ChatTransportApiConfig? apiConfig,
    String? id,
  ) {
    if (apiConfig == null) {
      throw ChatException(
        ChatExceptionCode.invalidTransportConfiguration,
        messageId: id ?? 'unknown',
      );
    }
    return DefaultChatTransport(apiConfig: apiConfig);
  }
}

sealed class SendMessageInput {
  const SendMessageInput();
}

class SendNone extends SendMessageInput {
  const SendNone();
}

class SendExistingMessage extends SendMessageInput {
  const SendExistingMessage(this.message, {this.messageId});

  final UiMessage message;
  final String? messageId;
}

class SendText extends SendMessageInput {
  const SendText(this.text, {this.files, this.metadata, this.messageId});

  final String text;
  final List<FileReference>? files;
  final Map<String, Object?>? metadata;
  final String? messageId;
}

class SendFiles extends SendMessageInput {
  const SendFiles(this.files, {this.metadata, this.messageId});

  final List<FileReference> files;
  final Map<String, Object?>? metadata;
  final String? messageId;
}
