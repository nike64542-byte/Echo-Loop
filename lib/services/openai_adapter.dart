/// OpenAI 兼容 API 适配器。
///
/// 将 App 内部的 AI 请求格式（翻译/解析/意群/词析）转换为 OpenAI Chat Completions 格式，
/// 直接调用用户配置的 LLM API，绕过 Echo Loop 后端。
///
/// 支持所有 OpenAI 兼容接口：OpenAI、DeepSeek、Moonshot、通义千问、Groq、Ollama 等。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../services/app_logger.dart';
import '../services/ndjson_stream.dart';

/// OpenAI Chat Completions 请求体。
class _ChatCompletionRequest {
  final String model;
  final List<Map<String, String>> messages;
  final bool stream;

  const _ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.stream = true,
  });

  Map<String, dynamic> toJson() => {
    'model': model,
    'messages': messages,
    'stream': stream,
  };
}

/// OpenAI 兼容 API 适配器。
///
/// 把 App 的翻译/解析/意群/词析请求转换为 OpenAI Chat Completions 格式。
class OpenAiAdapter {
  final Dio _dio;
  final String _modelId;

  OpenAiAdapter({
    required String baseUrl,
    required String apiKey,
    required String modelId,
  }) : _modelId = modelId,
       _dio = Dio(BaseOptions(
         baseUrl: baseUrl,
         connectTimeout: const Duration(seconds: 30),
         receiveTimeout: const Duration(minutes: 2),
         headers: {
           'Authorization': 'Bearer $apiKey',
           'Content-Type': 'application/json',
         },
       ));

  /// 翻译句子。
  Stream<String> translate({
    required String text,
    required String targetLanguage,
    String? previousText,
    String? nextText,
    CancelToken? cancelToken,
  }) async* {
    final contextParts = <String>[];
    if (previousText != null) contextParts.add('上文：$previousText');
    if (nextText != null) contextParts.add('下文：$nextText');

    final userContent = contextParts.isEmpty
        ? text
        : '${contextParts.join("\n")}\n\n请翻译以下句子：$text';

    final request = _ChatCompletionRequest(
      model: _modelId,
      messages: [
        {
          'role': 'system',
          'content': '你是一位专业翻译助手。请将用户提供的英文句子翻译成${_languageName(targetLanguage)}。'
              '只输出翻译结果，不要解释，不要多余内容。',
        },
        {'role': 'user', 'content': userContent},
      ],
    );

    yield* _streamRequest(request, cancelToken: cancelToken);
  }

  /// 解析句子（语法/词汇/听力要点）。
  Stream<String> analyze({
    required String text,
    required String targetLanguage,
    CancelToken? cancelToken,
  }) async* {
    final request = _ChatCompletionRequest(
      model: _modelId,
      messages: [
        {
          'role': 'system',
          'content': '你是一位英语教学专家。请对用户提供的英文句子进行详细分析，包括：\n'
              '1. 语法结构分析\n'
              '2. 重点词汇和短语\n'
              '3. 听力要点（连读、弱读、重音等）\n'
              '用${_languageName(targetLanguage)}回复。',
        },
        {'role': 'user', 'content': text},
      ],
    );

    yield* _streamRequest(request, cancelToken: cancelToken);
  }

  /// 意群切分。
  Stream<String> senseGroups({
    required String text,
    CancelToken? cancelToken,
  }) async* {
    final request = _ChatCompletionRequest(
      model: _modelId,
      messages: [
        {
          'role': 'system',
          'content': '你是一位英语教学专家。请将用户提供的英文句子按意群（sense group）切分。\n'
              '用 "|" 分隔不同意群，用 "/" 表示可选停顿。\n'
              '只输出切分结果，不要解释。',
        },
        {'role': 'user', 'content': text},
      ],
    );

    yield* _streamRequest(request, cancelToken: cancelToken);
  }

  /// 单词解析。
  Stream<String> lookupWord({
    required String word,
    CancelToken? cancelToken,
  }) async* {
    final request = _ChatCompletionRequest(
      model: _modelId,
      messages: [
        {
          'role': 'system',
          'content': '你是一位词典专家。请提供用户查询的英文单词的详细信息，包括：\n'
              '1. 音标（美式和英式）\n'
              '2. 词性\n'
              '3. 中文释义\n'
              '4. 常见搭配和例句\n'
              '5. 词源或记忆技巧（可选）\n'
              '用简洁的格式输出。',
        },
        {'role': 'user', 'content': word},
      ],
    );

    yield* _streamRequest(request, cancelToken: cancelToken);
  }

  /// 通用聊天对话。
  Stream<String> chat({
    required List<Map<String, String>> messages,
    CancelToken? cancelToken,
  }) async* {
    final request = _ChatCompletionRequest(
      model: _modelId,
      messages: messages,
    );

    yield* _streamRequest(request, cancelToken: cancelToken);
  }

  /// 发送流式请求并逐帧 yield 文本。
  Stream<String> _streamRequest(
    _ChatCompletionRequest request, {
    CancelToken? cancelToken,
  }) async* {
    AppLogger.log('OpenAI-Adapter', '请求: model=${request.modelId}');

    try {
      final response = await _dio.post<ResponseBody>(
        '/chat/completions',
        data: request.toJson(),
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      );

      final body = response.data;
      final status = response.statusCode ?? 0;

      if (body == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }

      if (status != 200) {
        final errorText = await utf8.decodeStream(body.stream);
        AppLogger.log('OpenAI-Adapter', '请求失败: status=$status body=$errorText');
        throw DioException(
          requestOptions: response.requestOptions,
          response: Response(
            requestOptions: response.requestOptions,
            statusCode: status,
            data: errorText,
          ),
          type: DioExceptionType.badResponse,
        );
      }

      // 解析 SSE 流：每行格式为 "data: {...}" 或 "data: [DONE]"
      await for (final line
          in body.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                yield content;
              }
            }
          } catch (_) {
            // 跳过解析失败的行
          }
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      rethrow;
    }
  }

  /// BCP 47 语言代码转中文名。
  String _languageName(String code) {
    return switch (code) {
      'zh-CN' || 'zh' => '中文',
      'zh-TW' => '繁体中文',
      'en' => 'English',
      'ja' => '日本語',
      'ko' => '한국어',
      _ => code,
    };
  }

  void dispose() => _dio.close();
}
