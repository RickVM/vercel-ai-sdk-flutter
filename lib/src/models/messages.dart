enum UiMessageRole { system, user, assistant }

enum MessagePartState { streaming, done }

enum ToolCallState {
  inputStreaming,
  inputAvailable,
  outputAvailable,
  outputError,
}

abstract class MessagePart {
  String get type;

  Map<String, Object?> toJson();
}

class TextPart implements MessagePart {
  TextPart({required this.text, this.state, this.providerMetadata});

  @override
  String get type => 'text';

  String text;
  MessagePartState? state;
  Object? providerMetadata;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'type': type, 'text': text};
    if (state case final state?) {
      json['state'] = state.name;
    }
    if (providerMetadata != null) {
      json['providerMetadata'] = providerMetadata;
    }
    return json;
  }
}

MessagePart messagePartFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String? ?? '';
  switch (type) {
    case 'text':
      return TextPart(
        text: json['text'] as String? ?? '',
        state: _messagePartStateFromJson(json['state']),
        providerMetadata: json['providerMetadata'],
      );
    case 'reasoning':
      return ReasoningPart(
        text: json['text'] as String? ?? '',
        state: _messagePartStateFromJson(json['state']),
        providerMetadata: json['providerMetadata'],
      );
    case 'file':
      return FilePart(
        filename: json['filename'] as String?,
        url: json['url'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? '',
        providerMetadata: json['providerMetadata'],
      );
    case 'source-url':
      return SourceUrlPart(
        sourceId: json['sourceId'] as String? ?? '',
        url: json['url'] as String? ?? '',
        title: json['title'] as String?,
        providerMetadata: json['providerMetadata'],
      );
    case 'source-document':
      return SourceDocumentPart(
        sourceId: json['sourceId'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? '',
        title: json['title'] as String? ?? '',
        filename: json['filename'] as String?,
        providerMetadata: json['providerMetadata'],
      );
    case 'step-start':
      return const StepStartPart();
    case 'dynamic-tool':
      return DynamicToolPart(
        toolName: json['toolName'] as String? ?? '',
        toolCallId: json['toolCallId'] as String? ?? '',
        state: _toolCallStateFromJson(json['state']),
        input: json['input'],
        output: json['output'],
        errorText: json['errorText'] as String?,
        callProviderMetadata: json['callProviderMetadata'],
        preliminary: json['preliminary'] as bool?,
      );
  }

  if (type.startsWith('data-')) {
    return DataPart(
      dataName: type.substring('data-'.length),
      data: json['data'],
      id: json['id'] as String?,
    );
  }
  if (type.startsWith('tool-')) {
    return ToolPart(
      toolName: type.substring('tool-'.length),
      toolCallId: json['toolCallId'] as String? ?? '',
      state: _toolCallStateFromJson(json['state']),
      input: json['input'],
      output: json['output'],
      errorText: json['errorText'] as String?,
      providerExecuted: json['providerExecuted'] as bool?,
      callProviderMetadata: json['callProviderMetadata'],
      preliminary: json['preliminary'] as bool?,
    );
  }

  throw FormatException('Unsupported message part type: $type');
}

MessagePartState? _messagePartStateFromJson(Object? value) {
  switch (value) {
    case 'streaming':
      return MessagePartState.streaming;
    case 'done':
      return MessagePartState.done;
  }
  return null;
}

ToolCallState _toolCallStateFromJson(Object? value) {
  switch (value) {
    case 'input-streaming':
      return ToolCallState.inputStreaming;
    case 'output-available':
      return ToolCallState.outputAvailable;
    case 'output-error':
      return ToolCallState.outputError;
    case 'input-available':
    default:
      return ToolCallState.inputAvailable;
  }
}

class ReasoningPart implements MessagePart {
  ReasoningPart({this.text = '', this.state, this.providerMetadata});

  @override
  String get type => 'reasoning';

  String text;
  MessagePartState? state;
  Object? providerMetadata;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'type': type, 'text': text};
    if (state case final state?) {
      json['state'] = state.name;
    }
    if (providerMetadata != null) {
      json['providerMetadata'] = providerMetadata;
    }
    return json;
  }
}

class FileReference {
  FileReference({
    required this.filename,
    required this.url,
    required this.mediaType,
  });

  final String filename;
  final Uri url;
  final String mediaType;
}

class FilePart implements MessagePart {
  FilePart({
    this.filename,
    required this.url,
    required this.mediaType,
    this.providerMetadata,
  });

  @override
  String get type => 'file';

  final String? filename;
  final String url;
  final String mediaType;
  final Object? providerMetadata;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'url': url,
      'mediaType': mediaType,
    };
    if (filename != null) {
      json['filename'] = filename;
    }
    if (providerMetadata != null) {
      json['providerMetadata'] = providerMetadata;
    }
    return json;
  }
}

class SourceUrlPart implements MessagePart {
  SourceUrlPart({
    required this.sourceId,
    required this.url,
    this.title,
    this.providerMetadata,
  });

  @override
  String get type => 'source-url';

  final String sourceId;
  final String url;
  final String? title;
  final Object? providerMetadata;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'sourceId': sourceId,
      'url': url,
    };
    if (title != null) {
      json['title'] = title;
    }
    if (providerMetadata != null) {
      json['providerMetadata'] = providerMetadata;
    }
    return json;
  }
}

class SourceDocumentPart implements MessagePart {
  SourceDocumentPart({
    required this.sourceId,
    required this.mediaType,
    required this.title,
    this.filename,
    this.providerMetadata,
  });

  @override
  String get type => 'source-document';

  final String sourceId;
  final String mediaType;
  final String title;
  final String? filename;
  final Object? providerMetadata;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'sourceId': sourceId,
      'mediaType': mediaType,
      'title': title,
    };
    if (filename != null) {
      json['filename'] = filename;
    }
    if (providerMetadata != null) {
      json['providerMetadata'] = providerMetadata;
    }
    return json;
  }
}

class ToolPart implements MessagePart {
  ToolPart({
    required this.toolName,
    required this.toolCallId,
    required this.state,
    this.input,
    this.output,
    this.errorText,
    this.providerExecuted,
    this.callProviderMetadata,
    this.preliminary,
  });

  final String toolName;
  final String toolCallId;
  ToolCallState state;
  Object? input;
  Object? output;
  String? errorText;
  bool? providerExecuted;
  Object? callProviderMetadata;
  bool? preliminary;

  @override
  String get type => 'tool-$toolName';

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'toolCallId': toolCallId,
      'state': state.wireValue,
    };
    if (input != null) {
      json['input'] = input;
    }
    if (output != null) {
      json['output'] = output;
    }
    if (errorText != null) {
      json['errorText'] = errorText;
    }
    if (providerExecuted != null) {
      json['providerExecuted'] = providerExecuted;
    }
    if (callProviderMetadata != null) {
      json['callProviderMetadata'] = callProviderMetadata;
    }
    if (preliminary != null) {
      json['preliminary'] = preliminary;
    }
    return json;
  }
}

class DynamicToolPart implements MessagePart {
  DynamicToolPart({
    required this.toolName,
    required this.toolCallId,
    required this.state,
    this.input,
    this.output,
    this.errorText,
    this.callProviderMetadata,
    this.preliminary,
  });

  final String toolName;
  final String toolCallId;
  ToolCallState state;
  Object? input;
  Object? output;
  String? errorText;
  Object? callProviderMetadata;
  bool? preliminary;

  @override
  String get type => 'dynamic-tool';

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'toolName': toolName,
      'toolCallId': toolCallId,
      'state': state.wireValue,
    };
    if (input != null) {
      json['input'] = input;
    }
    if (output != null) {
      json['output'] = output;
    }
    if (errorText != null) {
      json['errorText'] = errorText;
    }
    if (callProviderMetadata != null) {
      json['callProviderMetadata'] = callProviderMetadata;
    }
    if (preliminary != null) {
      json['preliminary'] = preliminary;
    }
    return json;
  }
}

class DataPart implements MessagePart {
  DataPart({required this.dataName, this.data, this.id});

  final String dataName;
  final Object? data;
  final String? id;

  @override
  String get type => 'data-$dataName';

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'type': type, 'data': data};
    if (id != null) {
      json['id'] = id;
    }
    return json;
  }
}

class StepStartPart implements MessagePart {
  const StepStartPart();

  @override
  String get type => 'step-start';

  @override
  Map<String, Object?> toJson() => {'type': type};
}

class UiMessage {
  UiMessage({
    required this.id,
    required this.role,
    required this.parts,
    this.metadata,
  });

  String id;
  final UiMessageRole role;
  final List<MessagePart> parts;
  Map<String, Object?>? metadata;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'id': id,
      'role': role.name,
      'parts': parts.map((part) => part.toJson()).toList(),
    };
    if (metadata != null) {
      json['metadata'] = metadata;
    }
    return json;
  }

  static UiMessage fromJson(Map<String, dynamic> json) {
    final roleValue = json['role'] as String? ?? 'user';
    final partsJson = json['parts'];
    final parts = partsJson is List
        ? partsJson.whereType<Map>().map((part) => messagePartFromJson(Map<String, dynamic>.from(part))).toList()
        : <MessagePart>[];
    final metadataJson = json['metadata'];

    return UiMessage(
      id: json['id'] as String? ?? '',
      role: UiMessageRole.values.firstWhere(
        (role) => role.name == roleValue,
        orElse: () => UiMessageRole.user,
      ),
      parts: parts,
      metadata: metadataJson is Map ? Map<String, Object?>.from(metadataJson) : null,
    );
  }

  bool isCompleteWithToolCalls() {
    if (role != UiMessageRole.assistant) {
      return false;
    }

    var lastStepStartIndex = -1;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] is StepStartPart) {
        lastStepStartIndex = i;
      }
    }

    final relevantParts = parts.sublist(lastStepStartIndex + 1);
    final toolInvocations = relevantParts.where((part) {
      return part is ToolPart || part is DynamicToolPart;
    }).toList();

    if (toolInvocations.isEmpty) {
      return false;
    }

    return toolInvocations.every((part) {
      if (part is ToolPart) {
        return part.state == ToolCallState.outputAvailable;
      }
      if (part is DynamicToolPart) {
        return part.state == ToolCallState.outputAvailable;
      }
      return false;
    });
  }
}

bool lastAssistantMessageIsCompleteWithToolCalls(List<UiMessage> messages) {
  if (messages.isEmpty) {
    return false;
  }
  return messages.last.isCompleteWithToolCalls();
}

extension MessagePartToolHelpers on MessagePart {
  bool get isToolPart => this is ToolPart;

  bool get isDynamicToolPart => this is DynamicToolPart;

  String? get toolName {
    if (this is ToolPart) {
      return (this as ToolPart).toolName;
    }
    if (this is DynamicToolPart) {
      return (this as DynamicToolPart).toolName;
    }
    return null;
  }
}

extension ToolCallStateWire on ToolCallState {
  String get wireValue {
    switch (this) {
      case ToolCallState.inputStreaming:
        return 'input-streaming';
      case ToolCallState.inputAvailable:
        return 'input-available';
      case ToolCallState.outputAvailable:
        return 'output-available';
      case ToolCallState.outputError:
        return 'output-error';
    }
  }
}
