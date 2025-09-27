import 'dart:convert';

sealed class UiMessageChunk {
  const UiMessageChunk();

  factory UiMessageChunk.fromDynamic(Object? json) {
    if (json is UiMessageChunk) {
      return json;
    }
    if (json is Map<String, dynamic>) {
      return UiMessageChunk.fromJson(json);
    }
    throw ArgumentError('Unsupported chunk payload: $json');
  }

  static UiMessageChunk fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null) {
      throw const FormatException('Missing chunk type');
    }
    switch (type) {
      case 'text-start':
        return TextStartChunk(
          id: json['id'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'text-delta':
        return TextDeltaChunk(
          id: json['id'] as String? ?? '',
          delta: json['delta'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'text-end':
        return TextEndChunk(
          id: json['id'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'reasoning-start':
        return ReasoningStartChunk(
          id: json['id'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'reasoning-delta':
        return ReasoningDeltaChunk(
          id: json['id'] as String? ?? '',
          delta: json['delta'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'reasoning-end':
        return ReasoningEndChunk(
          id: json['id'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'reasoning':
        return ReasoningChunk(
          text: json['text'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'reasoning-part-finish':
        return const ReasoningPartFinishChunk();
      case 'error':
        return ErrorChunk(errorText: json['errorText'] as String? ?? '');
      case 'tool-input-available':
        return ToolInputAvailableChunk(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '',
          input: json.containsKey('input') ? json['input'] : null,
          providerExecuted: json['providerExecuted'] as bool?,
          providerMetadata: json['providerMetadata'],
          isDynamic: json['dynamic'] as bool?,
        );
      case 'tool-input-error':
        return ToolInputErrorChunk(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '',
          input: json.containsKey('input') ? json['input'] : null,
          providerExecuted: json['providerExecuted'] as bool?,
          providerMetadata: json['providerMetadata'],
          isDynamic: json['dynamic'] as bool?,
          errorText: json['errorText'] as String? ?? '',
        );
      case 'tool-output-available':
        return ToolOutputAvailableChunk(
          toolCallId: json['toolCallId'] as String? ?? '',
          output: json.containsKey('output') ? json['output'] : null,
          providerExecuted: json['providerExecuted'] as bool?,
          isDynamic: json['dynamic'] as bool?,
          preliminary: json['preliminary'] as bool?,
        );
      case 'tool-output-error':
        return ToolOutputErrorChunk(
          toolCallId: json['toolCallId'] as String? ?? '',
          errorText: json['errorText'] as String? ?? '',
          providerExecuted: json['providerExecuted'] as bool?,
          isDynamic: json['dynamic'] as bool?,
        );
      case 'tool-input-start':
        return ToolInputStartChunk(
          toolCallId: json['toolCallId'] as String? ?? '',
          toolName: json['toolName'] as String? ?? '',
          providerExecuted: json['providerExecuted'] as bool?,
          isDynamic: json['dynamic'] as bool?,
        );
      case 'tool-input-delta':
        return ToolInputDeltaChunk(
          toolCallId: json['toolCallId'] as String? ?? '',
          inputTextDelta: json['inputTextDelta'] as String? ?? '',
        );
      case 'source-url':
        return SourceUrlChunk(
          sourceId: json['sourceId'] as String? ?? '',
          url: json['url'] as String? ?? '',
          title: json['title'] as String?,
          providerMetadata: json['providerMetadata'],
        );
      case 'source-document':
        return SourceDocumentChunk(
          sourceId: json['sourceId'] as String? ?? '',
          mediaType: json['mediaType'] as String? ?? '',
          title: json['title'] as String? ?? '',
          filename: json['filename'] as String?,
          providerMetadata: json['providerMetadata'],
        );
      case 'file':
        return FileChunk(
          url: json['url'] as String? ?? '',
          mediaType: json['mediaType'] as String? ?? '',
          providerMetadata: json['providerMetadata'],
        );
      case 'start-step':
        return const StartStepChunk();
      case 'finish-step':
        return const FinishStepChunk();
      case 'start':
        return StartChunk(
          messageId: json['messageId'] as String?,
          messageMetadata: json['messageMetadata'],
        );
      case 'finish':
        return FinishChunk(messageMetadata: json['messageMetadata']);
      case 'abort':
        return const AbortChunk();
      case 'message-metadata':
        if (!json.containsKey('messageMetadata')) {
          throw const FormatException('Missing messageMetadata');
        }
        return MessageMetadataChunk(messageMetadata: json['messageMetadata']);
      default:
        if (type.startsWith('data-')) {
          return DataChunk(
            type: type,
            id: json['id'] as String?,
            data: json.containsKey('data') ? json['data'] : null,
            transient: json['transient'] as bool?,
          );
        }
        throw FormatException('Unsupported chunk type: $type');
    }
  }
}

class TextStartChunk extends UiMessageChunk {
  const TextStartChunk({required this.id, this.providerMetadata});

  final String id;
  final Object? providerMetadata;
}

class TextDeltaChunk extends UiMessageChunk {
  const TextDeltaChunk({
    required this.id,
    required this.delta,
    this.providerMetadata,
  });

  final String id;
  final String delta;
  final Object? providerMetadata;
}

class TextEndChunk extends UiMessageChunk {
  const TextEndChunk({required this.id, this.providerMetadata});

  final String id;
  final Object? providerMetadata;
}

class ReasoningStartChunk extends UiMessageChunk {
  const ReasoningStartChunk({required this.id, this.providerMetadata});

  final String id;
  final Object? providerMetadata;
}

class ReasoningDeltaChunk extends UiMessageChunk {
  const ReasoningDeltaChunk({
    required this.id,
    required this.delta,
    this.providerMetadata,
  });

  final String id;
  final String delta;
  final Object? providerMetadata;
}

class ReasoningEndChunk extends UiMessageChunk {
  const ReasoningEndChunk({required this.id, this.providerMetadata});

  final String id;
  final Object? providerMetadata;
}

class ReasoningChunk extends UiMessageChunk {
  const ReasoningChunk({required this.text, this.providerMetadata});

  final String text;
  final Object? providerMetadata;
}

class ReasoningPartFinishChunk extends UiMessageChunk {
  const ReasoningPartFinishChunk();
}

class ErrorChunk extends UiMessageChunk {
  const ErrorChunk({required this.errorText});

  final String errorText;
}

class ToolInputAvailableChunk extends UiMessageChunk {
  const ToolInputAvailableChunk({
    required this.toolCallId,
    required this.toolName,
    this.input,
    this.providerExecuted,
    this.providerMetadata,
    this.isDynamic,
  });

  final String toolCallId;
  final String toolName;
  final Object? input;
  final bool? providerExecuted;
  final Object? providerMetadata;
  final bool? isDynamic;
}

class ToolInputErrorChunk extends UiMessageChunk {
  const ToolInputErrorChunk({
    required this.toolCallId,
    required this.toolName,
    this.input,
    this.providerExecuted,
    this.providerMetadata,
    this.isDynamic,
    required this.errorText,
  });

  final String toolCallId;
  final String toolName;
  final Object? input;
  final bool? providerExecuted;
  final Object? providerMetadata;
  final bool? isDynamic;
  final String errorText;
}

class ToolOutputAvailableChunk extends UiMessageChunk {
  const ToolOutputAvailableChunk({
    required this.toolCallId,
    this.output,
    this.providerExecuted,
    this.isDynamic,
    this.preliminary,
  });

  final String toolCallId;
  final Object? output;
  final bool? providerExecuted;
  final bool? isDynamic;
  final bool? preliminary;
}

class ToolOutputErrorChunk extends UiMessageChunk {
  const ToolOutputErrorChunk({
    required this.toolCallId,
    required this.errorText,
    this.providerExecuted,
    this.isDynamic,
  });

  final String toolCallId;
  final String errorText;
  final bool? providerExecuted;
  final bool? isDynamic;
}

class ToolInputStartChunk extends UiMessageChunk {
  const ToolInputStartChunk({
    required this.toolCallId,
    required this.toolName,
    this.providerExecuted,
    this.isDynamic,
  });

  final String toolCallId;
  final String toolName;
  final bool? providerExecuted;
  final bool? isDynamic;
}

class ToolInputDeltaChunk extends UiMessageChunk {
  const ToolInputDeltaChunk({
    required this.toolCallId,
    required this.inputTextDelta,
  });

  final String toolCallId;
  final String inputTextDelta;
}

class SourceUrlChunk extends UiMessageChunk {
  const SourceUrlChunk({
    required this.sourceId,
    required this.url,
    this.title,
    this.providerMetadata,
  });

  final String sourceId;
  final String url;
  final String? title;
  final Object? providerMetadata;
}

class SourceDocumentChunk extends UiMessageChunk {
  const SourceDocumentChunk({
    required this.sourceId,
    required this.mediaType,
    required this.title,
    this.filename,
    this.providerMetadata,
  });

  final String sourceId;
  final String mediaType;
  final String title;
  final String? filename;
  final Object? providerMetadata;
}

class FileChunk extends UiMessageChunk {
  const FileChunk({
    required this.url,
    required this.mediaType,
    this.providerMetadata,
  });

  final String url;
  final String mediaType;
  final Object? providerMetadata;
}

class StartStepChunk extends UiMessageChunk {
  const StartStepChunk();
}

class FinishStepChunk extends UiMessageChunk {
  const FinishStepChunk();
}

class StartChunk extends UiMessageChunk {
  const StartChunk({this.messageId, this.messageMetadata});

  final String? messageId;
  final Object? messageMetadata;
}

class FinishChunk extends UiMessageChunk {
  const FinishChunk({this.messageMetadata});

  final Object? messageMetadata;
}

class AbortChunk extends UiMessageChunk {
  const AbortChunk();
}

class MessageMetadataChunk extends UiMessageChunk {
  const MessageMetadataChunk({required this.messageMetadata});

  final Object? messageMetadata;
}

class DataChunk extends UiMessageChunk {
  const DataChunk({required this.type, this.id, this.data, this.transient});

  final String type;
  final String? id;
  final Object? data;
  final bool? transient;

  String get dataName => type.startsWith('data-') ? type.substring(5) : type;
}

UiMessageChunk parseChunkLine(String line) {
  final data = jsonDecode(line);
  if (data is Map<String, dynamic>) {
    return UiMessageChunk.fromJson(data);
  }
  throw const FormatException('Chunk root must be an object');
}
