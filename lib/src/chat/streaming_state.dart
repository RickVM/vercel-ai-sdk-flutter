import 'dart:async';

import '../models/chunks.dart';
import '../models/messages.dart';

class StreamingUiMessageState {
  StreamingUiMessageState({
    required this.message,
    Map<String, TextPart>? activeTextParts,
    Map<String, MessagePart>? activeReasoningParts,
    Map<String, MessagePart>? partialToolCalls,
  }) : activeTextParts = activeTextParts ?? <String, TextPart>{},
       activeReasoningParts = activeReasoningParts ?? <String, MessagePart>{},
       partialToolCalls = partialToolCalls ?? <String, MessagePart>{};

  UiMessage message;
  Map<String, TextPart> activeTextParts;
  Map<String, MessagePart> activeReasoningParts;
  Map<String, MessagePart> partialToolCalls;
}

typedef UpdateMessageJob = Future<void> Function(UiMessageChunk chunk);
typedef ChunkErrorHandler = void Function(Object error);

class ProcessUiMessageStreamOptions {
  const ProcessUiMessageStreamOptions({
    required this.stream,
    required this.runUpdateMessageJob,
    required this.onError,
  });

  final Stream<UiMessageChunk> stream;
  final Future<void> Function(UiMessageChunk chunk) runUpdateMessageJob;
  final ChunkErrorHandler onError;
}

Stream<UiMessageChunk> processUiMessageStream(
  ProcessUiMessageStreamOptions options,
) {
  return Stream<UiMessageChunk>.multi((controller) {
    final subscription = options.stream.listen(
      (chunk) async {
        try {
          await options.runUpdateMessageJob(chunk);
          controller.add(chunk);
        } catch (error) {
          options.onError(error);
          controller.addError(error);
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    controller
      ..onCancel = subscription.cancel
      ..onPause = subscription.pause
      ..onResume = subscription.resume;
  });
}
