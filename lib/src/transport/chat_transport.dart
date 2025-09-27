import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import '../models/chunks.dart';
import '../models/messages.dart';

class ChatTransportApiConfig {
  ChatTransportApiConfig({
    required this.apiBaseUrl,
    required this.apiChatPath,
    this.apiReconnectToStreamPath,
  });

  final String apiBaseUrl;
  final String apiChatPath;
  final String? apiReconnectToStreamPath;
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
  DefaultChatTransport({required this.apiConfig, HttpClient? client})
    : client = client ?? HttpClient();

  final ChatTransportApiConfig apiConfig;
  final HttpClient client;

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
      'messages': messages.map((message) => message.toJson()).toList(),
      'trigger': trigger.wireValue,
    };
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
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (headers != null) {
      headers.forEach(request.headers.set);
    }
    request.add(utf8.encode(jsonEncode(payload)));

    final response = await request.close();
    _assertSuccess(response);
    return _parseEventStream(response);
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
    final request = await client.getUrl(uri);
    if (headers != null) {
      headers.forEach(request.headers.set);
    }

    final response = await request.close();
    if (response.statusCode == HttpStatus.noContent) {
      return null;
    }
    _assertSuccess(response);
    return _parseEventStream(response);
  }

  void _assertSuccess(HttpClientResponse response) {
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices) {
      throw TransportHttpException(
        response.statusCode,
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

class TransportHttpException implements Exception {
  TransportHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() =>
      'TransportHttpException(statusCode: $statusCode, message: $message)';
}
