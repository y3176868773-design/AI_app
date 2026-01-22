import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import './diagnostic_service.dart';

// 智能 Token 管理器
class TokenManager {
  static const int _maxTokens = 8192;
  static const int _reservedTokens = 1024;

  static String selectRelevantContext(
    String query,
    List<String> contextDocs, {
    int? maxTokens,
  }) {
    if (contextDocs.isEmpty) return '';

    final effectiveMaxTokens = maxTokens ?? (_maxTokens - _reservedTokens);

    // 计算每个文档的相关性分数
    final queryTerms = _extractQueryTerms(query);
    final scoredDocs = contextDocs.asMap().entries.map((entry) {
      final relevanceScore = _calculateRelevanceScore(entry.value, queryTerms);
      return {
        'index': entry.key,
        'content': entry.value,
        'score': relevanceScore,
        'length': entry.value.length,
      };
    }).toList();

    // 按相关性分数排序
    scoredDocs.sort((a, b) {
      final scoreA = (a['score'] as double?) ?? 0.0;
      final scoreB = (b['score'] as double?) ?? 0.0;
      return scoreB.compareTo(scoreA);
    });

    // 选择并截断文档
    StringBuffer result = StringBuffer();
    int totalTokens = 0;

    for (final doc in scoredDocs) {
      if (totalTokens >= effectiveMaxTokens) break;

      final content = doc['content'] as String;
      final availableTokens = effectiveMaxTokens - totalTokens;
      final truncatedContent = _truncateToTokens(content, availableTokens);

      if (truncatedContent.isNotEmpty) {
        if (result.isNotEmpty) {
          result.write('\n\n---\n\n');
        }
        result.write(truncatedContent);
        totalTokens += _estimateTokenCount(truncatedContent);
      }
    }

    return result.toString();
  }

  static List<String> _extractQueryTerms(String query) {
    // 提取查询关键词
    final terms = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((term) => term.length > 1)
        .toSet()
        .toList();
    return terms;
  }

  static double _calculateRelevanceScore(
    String content,
    List<String> queryTerms,
  ) {
    if (queryTerms.isEmpty) return 1.0;

    final lowerContent = content.toLowerCase();
    double score = 0.0;

    for (final term in queryTerms) {
      if (lowerContent.contains(term)) {
        score += 1.0;
        // 匹配越完整，分数越高
        if (lowerContent.contains(' $term ') || lowerContent.startsWith(term)) {
          score += 0.5;
        }
      }
    }

    // 归一化分数
    return score / queryTerms.length;
  }

  static int _estimateTokenCount(String text) {
    // 粗略估计 token 数量（中英文混合）
    final chineseChars = RegExp(r'[\u4e00-\u9fa5]').allMatches(text).length;
    final englishWords = text.split(RegExp(r'\s+')).length;
    return (chineseChars * 0.5 + englishWords * 0.75).round();
  }

  static String _truncateToTokens(String content, int maxTokens) {
    final estimatedTokens = _estimateTokenCount(content);

    if (estimatedTokens <= maxTokens) {
      return content;
    }

    // 按比例截断
    final ratio = maxTokens / estimatedTokens;
    final targetLength = (content.length * ratio).round();

    // 尝试在句子边界截断
    final truncated = _smartTruncate(content, targetLength);
    return truncated;
  }

  static String _smartTruncate(String content, int maxLength) {
    if (content.length <= maxLength) return content;

    // 尝试在段落边界截断
    final paragraphs = content.split('\n\n');
    StringBuffer result = StringBuffer();

    for (final paragraph in paragraphs) {
      if (result.length + paragraph.length + 2 > maxLength) {
        // 尝试在句子边界截断
        final sentences = paragraph.split(RegExp(r'[。！？.!?]'));
        for (final sentence in sentences) {
          if (result.length + sentence.length + 1 > maxLength) {
            // 在单词边界截断
            final words = sentence.split(' ');
            for (final word in words) {
              if (result.length + word.length + 1 > maxLength) {
                return result.toString();
              }
              if (result.isNotEmpty) result.write(' ');
              result.write(word);
            }
          }
          if (result.isNotEmpty) result.write('。');
          result.write(sentence);
        }
        break;
      }

      if (result.isNotEmpty) result.write('\n\n');
      result.write(paragraph);
    }

    return result.toString().substring(
      0,
      min(maxLength, result.toString().length),
    );
  }
}

// 添加网络状态监听器
class NetworkStatus {
  static final NetworkStatus _instance = NetworkStatus._internal();
  factory NetworkStatus() => _instance;
  NetworkStatus._internal();

  bool _isConnected = true;
  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();

  Stream<bool> get statusStream => _statusController.stream;
  bool get isConnected => _isConnected;

  void updateStatus(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      _statusController.add(connected);
    }
  }
}

class AIService {
  static String get _apiKey {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      DiagnosticService().log(
        'API Key 为空，请检查 .env 文件中的 GEMINI_API_KEY 设置',
        level: LogLevel.error,
      );
    }
    return apiKey;
  }

  static const _chatBaseUrl =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  static const _embeddingBaseUrl =
      'https://open.bigmodel.cn/api/paas/v4/embeddings';
  static const _visionChatBaseUrl =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions'; // GLM-4V模型使用相同的URL

  // 初始化诊断服务引用
  static final DiagnosticService _diagnosticService = DiagnosticService();

  static Future<Response<T>> _postWithRetry<T>(
    String url, {
    required dynamic data,
    required Options options,
    int retries = 3,
  }) async {
    // 为每个请求创建新的Dio实例，避免连接复用问题
    final requestDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        // 添加更多连接配置
        headers: {
          'Connection': 'keep-alive',
          'Keep-Alive': 'timeout=30',
          'Accept': '*/*',
        },
      ),
    );

    // 添加请求拦截器，用于日志记录
    requestDio.interceptors.add(
      LogInterceptor(
        requestBody: false, // 不记录请求体，避免日志过大
        responseBody: false, // 不记录响应体
        logPrint: (object) {
          _diagnosticService.log('Dio请求: $object', level: LogLevel.debug);
        },
      ),
    );

    for (var i = 0; i < retries; i++) {
      try {
        _diagnosticService.log(
          '发送API请求 (尝试 ${i + 1}/$retries)',
          level: LogLevel.info,
          error: 'URL: $url',
        );

        final response = await requestDio.post<T>(
          url,
          data: data,
          options: options,
        );

        _diagnosticService.log(
          'API请求成功',
          level: LogLevel.info,
          error: '状态码: ${response.statusCode}',
        );

        return response;
      } on DioException catch (e) {
        String errorMessage = '网络请求失败';

        // 根据不同的错误类型提供更具体的错误信息
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
            errorMessage = '连接超时，请检查网络连接';
            break;
          case DioExceptionType.sendTimeout:
            errorMessage = '发送请求超时';
            break;
          case DioExceptionType.receiveTimeout:
            errorMessage = '接收响应超时';
            break;
          case DioExceptionType.connectionError:
            errorMessage = '网络连接错误，请检查网络设置';
            break;
          case DioExceptionType.badCertificate:
            errorMessage = '证书验证失败，请检查网络环境';
            break;
          case DioExceptionType.badResponse:
            errorMessage = '服务器响应错误: ${e.response?.statusCode}';
            if (e.response?.statusCode == 401) {
              errorMessage = 'API密钥无效或已过期';
            } else if (e.response?.statusCode == 429) {
              errorMessage = '请求频率过高，请稍后再试';
            } else if (e.response?.statusCode == 500) {
              errorMessage = '服务器内部错误';
            }
            break;
          case DioExceptionType.cancel:
            errorMessage = '请求已取消';
            break;
          case DioExceptionType.unknown:
            errorMessage = '未知错误: ${e.message}';
            break;
        }

        _diagnosticService.log(
          'API请求失败 (尝试 ${i + 1}/$retries)',
          level: LogLevel.error,
          error: errorMessage,
          stackTrace: e.stackTrace,
        );

        // 如果是最后一次重试，抛出带有具体错误信息的异常
        if (i == retries - 1) {
          throw Exception(errorMessage);
        }

        // 对于可重试的错误，等待一段时间后重试
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.response?.statusCode ?? 0) >= 500) {
          // 指数退避策略
          final waitTime = Duration(seconds: (i + 1) * 2);
          _diagnosticService.log('等待 $waitTime 秒后重试', level: LogLevel.info);
          await Future.delayed(waitTime);
        } else {
          // 对于不可重试的错误，直接抛出
          throw Exception(errorMessage);
        }
      } catch (e) {
        _diagnosticService.log(
          'API请求异常 (尝试 ${i + 1}/$retries)',
          level: LogLevel.error,
          error: e.toString(),
        );

        if (i == retries - 1) {
          throw Exception('请求失败: $e');
        }

        // 等待一段时间后重试
        await Future.delayed(Duration(seconds: i + 1));
      }
    }
    throw Exception('请求失败，已重试 $retries 次');
  }

  // 发送带图片的消息流
  static Stream<String> sendMessageWithImageStream(
    String query,
    List<String> contextDocs,
    String? imageBase64,
    String? imageFormat, {
    List<Map<String, dynamic>>? historyMessages,
  }) async* {
    try {
      // 验证查询内容
      if (query.trim().isEmpty) {
        yield "\n\n请求失败: 查询内容不能为空\n请输入您的问题或描述。";
        return;
      }

      _diagnosticService.log(
        '发送AI请求开始',
        level: LogLevel.info,
        error:
            '查询: $query, 上下文文档数: ${contextDocs.length}, 包含图片: ${imageBase64 != null}',
      );

      // 构建消息内容
      List<Map<String, dynamic>> messages = [];

      // 如果有上下文文档，使用 TokenManager 智能选择和截断
      if (contextDocs.isNotEmpty) {
        final relevantContext = TokenManager.selectRelevantContext(
          query,
          contextDocs,
        );

        if (relevantContext.isNotEmpty) {
          messages.add({
            "role": "system",
            "content":
                "请根据以下上下文信息准确回答问题。如果上下文中没有相关信息，请明确说明：\n\n$relevantContext",
          });

          _diagnosticService.log(
            '使用智能上下文选择（带图片）',
            level: LogLevel.info,
            error:
                '原始文档数: ${contextDocs.length}, 选择后长度: ${relevantContext.length}',
          );
        }
      }

      // 添加历史消息（如果有）
      if (historyMessages != null && historyMessages.isNotEmpty) {
        // 限制历史消息数量，避免上下文过长
        final maxHistoryLength = 10;
        final limitedHistory = historyMessages.length > maxHistoryLength
            ? historyMessages.sublist(historyMessages.length - maxHistoryLength)
            : historyMessages;

        // 验证并过滤历史消息，确保格式正确
        final validHistoryMessages = limitedHistory
            .where((msg) {
              final role = msg['role'] as String?;
              final content = msg['content'] as String?;

              // 只接受有效的角色和内容
              return role != null &&
                  content != null &&
                  content.isNotEmpty &&
                  (role == 'user' || role == 'assistant' || role == 'system');
            })
            .map((msg) => {'role': msg['role'], 'content': msg['content']})
            .toList();

        messages.addAll(validHistoryMessages);

        // 记录历史消息数量
        _diagnosticService.log(
          '添加历史消息',
          level: LogLevel.info,
          error: '历史消息数量: ${validHistoryMessages.length}',
        );
      }

      // 构建用户消息
      Map<String, dynamic> userMessage = {
        "role": "user",
        "content": <Map<String, dynamic>>[
          {"type": "text", "text": query},
        ],
      };

      // 如果有图片，添加图片内容
      if (imageBase64 != null && imageFormat != null) {
        userMessage["content"].add(<String, dynamic>{
          "type": "image_url",
          "image_url": <String, dynamic>{
            "url": "data:image/$imageFormat;base64,$imageBase64",
          },
        });
      }

      messages.add(userMessage);

      final response = await _postWithRetry<ResponseBody>(
        _visionChatBaseUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        data: {"model": "glm-4v-flash", "messages": messages, "stream": true},
      );

      _diagnosticService.log('AI请求成功获取响应流', level: LogLevel.info);

      String buffer = '';
      final responseData = response.data;
      if (responseData == null) {
        yield "\n\n请求失败：响应数据为空";
        return;
      }

      try {
        await for (final chunk in responseData.stream) {
          final decoded = utf8.decode(chunk, allowMalformed: true);
          buffer += decoded;

          while (buffer.contains('\n')) {
            final lineEndIndex = buffer.indexOf('\n');
            final line = buffer.substring(0, lineEndIndex);
            buffer = buffer.substring(lineEndIndex + 1);

            if (line.startsWith('data: ') && line != 'data: [DONE]') {
              try {
                final jsonStr = line.substring(6).trim();
                if (jsonStr.isEmpty) continue;

                final data = jsonDecode(jsonStr);

                if (data['error'] != null) {
                  yield "\n\nAPI 错误: ${data['error']['message']}";
                  return;
                }

                if (data['choices'] != null && data['choices'].isNotEmpty) {
                  final delta = data['choices'][0]['delta'] ?? {};
                  final content = delta['content'] ?? "";
                  if (content.isNotEmpty) {
                    _diagnosticService.log(
                      '收到AI响应内容: $content',
                      level: LogLevel.debug,
                    );
                    yield content;
                  }
                }
              } catch (e) {
                yield "\n\nJSON解析错误: $e\n";
                buffer = '';
              }
            }
          }
        }

        if (buffer.isNotEmpty) {
          if (buffer.startsWith('data: ') && buffer != 'data: [DONE]') {
            try {
              final jsonStr = buffer.substring(6).trim();
              if (jsonStr.isNotEmpty) {
                final data = jsonDecode(jsonStr);

                if (data['error'] != null) {
                  yield "\n\nAPI 错误: ${data['error']['message']}";
                  return;
                }

                if (data['choices'] != null && data['choices'].isNotEmpty) {
                  final delta = data['choices'][0]['delta'] ?? {};
                  final content = delta['content'] ?? "";
                  if (content.isNotEmpty) {
                    yield content;
                  }
                }
              }
            } catch (e) {
              // 忽略最后部分的JSON解析错误
            }
          }
        }
      } finally {
        // 流会自动关闭，无需手动处理
      }
    } catch (e, stackTrace) {
      _diagnosticService.log(
        'AI请求失败',
        level: LogLevel.error,
        error: e.toString(),
        stackTrace: stackTrace,
      );
      yield "\n\n请求失败: $e\n请检查您的网络连接或API密钥。";
    }
  }

  // 发送文本消息流
  static Stream<String> sendMessageStream(
    String query,
    List<String> contextDocs, {
    List<Map<String, dynamic>>? historyMessages,
  }) async* {
    // 验证查询内容
    if (query.trim().isEmpty) {
      yield "\n\n请求失败: 查询内容不能为空\n请输入您的问题或描述。";
      return;
    }

    // 构建消息内容
    List<Map<String, dynamic>> messages = [];

    // 如果有上下文文档，使用 TokenManager 智能选择和截断
    if (contextDocs.isNotEmpty) {
      final relevantContext = TokenManager.selectRelevantContext(
        query,
        contextDocs,
      );

      if (relevantContext.isNotEmpty) {
        messages.add({
          "role": "system",
          "content": "请根据以下上下文信息准确回答问题。如果上下文中没有相关信息，请明确说明：\n\n$relevantContext",
        });

        _diagnosticService.log(
          '使用智能上下文选择',
          level: LogLevel.info,
          error:
              '原始文档数: ${contextDocs.length}, 选择后长度: ${relevantContext.length}',
        );
      }
    }

    // 添加历史消息（如果有）
    if (historyMessages != null && historyMessages.isNotEmpty) {
      // 限制历史消息数量，避免上下文过长
      final maxHistoryLength = 10;
      final limitedHistory = historyMessages.length > maxHistoryLength
          ? historyMessages.sublist(historyMessages.length - maxHistoryLength)
          : historyMessages;

      // 验证并过滤历史消息，确保格式正确
      final validHistoryMessages = limitedHistory
          .where((msg) {
            final role = msg['role'] as String?;
            final content = msg['content'] as String?;

            // 只接受有效的角色和内容
            return role != null &&
                content != null &&
                content.isNotEmpty &&
                (role == 'user' || role == 'assistant' || role == 'system');
          })
          .map((msg) => {'role': msg['role'], 'content': msg['content']})
          .toList();

      messages.addAll(validHistoryMessages);

      // 记录历史消息数量
      _diagnosticService.log(
        '添加历史消息',
        level: LogLevel.info,
        error: '历史消息数量: ${validHistoryMessages.length}',
      );
    }

    // 添加用户消息
    messages.add({"role": "user", "content": query});

    try {
      _diagnosticService.log(
        '发送AI请求开始',
        level: LogLevel.info,
        error: '查询: $query, 上下文文档数: ${contextDocs.length}',
      );

      // 添加 API Key 长度检查（不记录完整 API Key）
      if (_apiKey.isEmpty) {
        yield "\n\n请求失败: API Key 为空，请检查配置";
        return;
      }
      _diagnosticService.log(
        'API Key 长度: ${_apiKey.length}',
        level: LogLevel.debug,
      );

      final response = await _postWithRetry<ResponseBody>(
        _chatBaseUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        data: {"model": "glm-4-flash", "messages": messages, "stream": true},
      );

      _diagnosticService.log('AI请求成功获取响应流', level: LogLevel.info);

      String buffer = '';
      // 确保response.data不为null
      final responseData = response.data;
      if (responseData == null) {
        yield "\n\n请求失败：响应数据为空";
        return;
      }

      try {
        await for (final chunk in responseData.stream) {
          final decoded = utf8.decode(chunk, allowMalformed: true);
          buffer += decoded;

          // 处理所有完整的行
          while (buffer.contains('\n')) {
            final lineEndIndex = buffer.indexOf('\n');
            final line = buffer.substring(0, lineEndIndex);
            buffer = buffer.substring(lineEndIndex + 1);

            if (line.startsWith('data: ') && line != 'data: [DONE]') {
              try {
                final jsonStr = line.substring(6).trim();
                if (jsonStr.isEmpty) continue;

                final data = jsonDecode(jsonStr);

                if (data['error'] != null) {
                  yield "\n\nAPI 错误: ${data['error']['message']}";
                  return;
                }

                if (data['choices'] != null && data['choices'].isNotEmpty) {
                  final delta = data['choices'][0]['delta'] ?? {};
                  final content = delta['content'] ?? "";
                  if (content.isNotEmpty) {
                    yield content;
                  }
                }
              } catch (e) {
                // JSON解析错误，记录但继续处理
                yield "\n\nJSON解析错误: $e\n";
                // 清空缓冲区，避免错误数据累积
                buffer = '';
              }
            }
          }
        }

        // 处理最后可能剩余的部分
        if (buffer.isNotEmpty) {
          if (buffer.startsWith('data: ') && buffer != 'data: [DONE]') {
            try {
              final jsonStr = buffer.substring(6).trim();
              if (jsonStr.isNotEmpty) {
                final data = jsonDecode(jsonStr);

                if (data['error'] != null) {
                  yield "\n\nAPI 错误: ${data['error']['message']}";
                  return;
                }

                if (data['choices'] != null && data['choices'].isNotEmpty) {
                  final delta = data['choices'][0]['delta'] ?? {};
                  final content = delta['content'] ?? "";
                  if (content.isNotEmpty) {
                    yield content;
                  }
                }
              }
            } catch (e) {
              // 最后部分的JSON解析错误，忽略
            }
          }
        }
      } finally {
        // 流会自动关闭，无需手动处理
      }
    } catch (e, stackTrace) {
      _diagnosticService.log(
        'AI请求失败',
        level: LogLevel.error,
        error: e.toString(),
        stackTrace: stackTrace,
      );
      yield "\n\n请求失败: $e\n请检查您的网络连接或API密钥。";
    }
  }

  static Future<List<double>> generateEmbedding(String text) async {
    // 重试次数
    final int maxRetries = 3;

    for (int retry = 0; retry < maxRetries; retry++) {
      try {
        _diagnosticService.log(
          '生成嵌入向量开始',
          level: LogLevel.info,
          error: '文本长度: ${text.length}, 重试次数: $retry',
        );

        // 优化文本处理，确保内容适合生成嵌入向量
        String processedText = text.trim();

        // 移除可能导致问题的特殊字符
        processedText = processedText.replaceAll(
          RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),
          '',
        );

        // 限制文本长度，确保不超过API限制
        final limitedText = processedText.length > 8192
            ? processedText.substring(0, 8192)
            : processedText;

        // 如果文本为空，使用默认文本
        final finalText = limitedText.isEmpty ? '空内容' : limitedText;

        final response = await _postWithRetry<Map<String, dynamic>>(
          _embeddingBaseUrl,
          options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
          data: {"model": "embedding-3", "input": finalText},
        );

        _diagnosticService.log('生成嵌入向量成功', level: LogLevel.info);

        final embedding = List<double>.from(
          response.data!['data'][0]['embedding'],
        );

        // 检查嵌入向量是否有效
        if (embedding.isNotEmpty && !embedding.every((e) => e == 0.0)) {
          return embedding;
        }

        // 如果嵌入向量无效，继续重试
        _diagnosticService.log('生成的嵌入向量无效，继续重试', level: LogLevel.warning);
      } catch (e, stackTrace) {
        _diagnosticService.log(
          '生成嵌入向量失败',
          level: LogLevel.error,
          error: '重试 $retry 失败: $e',
          stackTrace: stackTrace,
        );

        // 如果不是最后一次重试，等待一段时间后重试
        if (retry < maxRetries - 1) {
          await Future.delayed(Duration(seconds: retry + 1));
        }
      }
    }

    // 所有重试都失败，生成一个随机嵌入向量，避免全0向量
    _diagnosticService.log('所有重试都失败，生成随机嵌入向量', level: LogLevel.error);

    final random = Random();
    return List<double>.generate(
      1536,
      (_) => random.nextDouble() * 2 - 1,
    ); // 生成-1到1之间的随机数
  }
}
