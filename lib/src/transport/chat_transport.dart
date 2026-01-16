import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import '../models/chunks.dart';
import '../models/messages.dart';

class ChatTransportApiConfig {
  ChatTransportApiConfig({
    required this.apiBaseUrl,
    required this.apiChatPath,
    this.apiReconnectToStreamPath,
    this.includeMessages = true,
  });

  final String apiBaseUrl;
  final String apiChatPath;
  final String? apiReconnectToStreamPath;
  final bool includeMessages;
}

abstract class ChatTransport {
  Future<Stream<UiMessageChunk>> sendMessages({
    required String chatId,
    required List<UiMessage> messages,
    Future<void>? abortSignal,
    Map<String, Object?>? metadata,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    required ChatRequestTrigger trigger,
    String? messageId,
  });

  Future<Stream<UiMessageChunk>?> reconnectToStream({
    required String chatId,
    Map<String, Object?>? metadata,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    String? path,
  });
}

class DefaultChatTransport implements ChatTransport {
  DefaultChatTransport({required this.apiConfig, http.Client? client})
    : client = client ?? http.Client();

  final ChatTransportApiConfig apiConfig;
  final http.Client client;

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
    final payload = <String, Object?>{
      'id': chatId,
      'trigger': trigger.wireValue,
    };
    if (apiConfig.includeMessages) {
      payload['messages'] = messages.map((message) => message.toJson()).toList();
    }
    if (messageId != null) {
      payload['messageId'] = messageId;
    }
    if (metadata != null) {
      payload['metadata'] = metadata;
    }
    if (body != null) {
      for (final entry in body.entries) {
        payload.putIfAbsent(entry.key, () => entry.value);
      }
    }

    final uri = _buildUri(apiConfig.apiBaseUrl, apiConfig.apiChatPath);
    final request = http.Request('POST', uri)
      ..headers['content-type'] = 'application/json';
    if (headers != null) {
      request.headers.addAll(headers);
    }
    request.body = jsonEncode(payload);

    final response = await client.send(request);
    _assertSuccess(response.statusCode);
    return _parseEventStream(response.stream);
  }

  @override
  Future<Stream<UiMessageChunk>?> reconnectToStream({
    required String chatId,
    Map<String, Object?>? metadata,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    String? path,
  }) async {
    final reconnectPath = path ?? apiConfig.apiReconnectToStreamPath;
    if (reconnectPath == null) {
      throw TransportHttpException(400, 'Reconnect path is not set');
    }
    final uri = _buildUri(apiConfig.apiBaseUrl, reconnectPath);
    final request = http.Request('GET', uri);
    if (headers != null) {
      request.headers.addAll(headers);
    }

    final response = await client.send(request);
    if (response.statusCode == _httpNoContent) {
      return null;
    }
    _assertSuccess(response.statusCode);
    return _parseEventStream(response.stream);
  }

  void _assertSuccess(int statusCode) {
    if (statusCode < _httpOk || statusCode >= _httpMultipleChoices) {
      throw TransportHttpException(
        statusCode,
        'Failed to fetch the chat response',
      );
    }
  }

  Stream<UiMessageChunk> _parseEventStream(
    Stream<List<int>> byteStream,
  ) async* {
    final decoded = utf8.decoder.bind(byteStream);
    final lines = const LineSplitter().bind(decoded);

    await for (final rawLine in lines) {
      if (rawLine.isEmpty) {
        continue;
      }

      final line = rawLine.trim();
      if (!line.startsWith('data:')) {
        continue;
      }

      final payload = line.substring(5).trimLeft();
      if (payload.isEmpty) {
        continue;
      }

      if (payload == '[DONE]') {
        break;
      }

      try {
        final chunk = parseChunkLine(payload);
        yield chunk;
      } catch (error, stackTrace) {
        debugPrint('Failed to parse chunk: $error');
        debugPrint('$stackTrace');
      }
    }
  }

  Uri _buildUri(String base, String path) {
    final baseUri = Uri.parse(base);
    if (path.isEmpty) {
      return baseUri;
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    return baseUri.resolve(path);
  }
}

const int _httpOk = 200;
const int _httpMultipleChoices = 300;
const int _httpNoContent = 204;

class TransportHttpException implements Exception {
  TransportHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'TransportHttpException(statusCode: $statusCode, message: $message)';
}
