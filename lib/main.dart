import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/document.dart';
import 'services/vector_db_service.dart';
import 'services/ai_service.dart';
import 'services/file_service.dart';
import 'services/diagnostic_service.dart';
import 'services/user_service.dart';
import 'screens/diagnostic_screen.dart';
import 'screens/document_view_screen.dart';
import 'screens/user_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/diagnostic_runner.dart';
import 'fix_login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    final String envPath = Platform.isAndroid
        ? 'assets/.env' // Android assets目录
        : '.env'; // 其他平台使用项目根目录
    await dotenv.load(fileName: envPath);
  } catch (e) {
    print('Failed to load .env file: $e');
  }

  // 后台初始化服务，避免阻塞UI
  Future.microtask(() async {
    try {
      await DiagnosticService().initialize();
      await VectorDBService.initialize();
      await UserService().initialize();
      // 修复123456@qq.com账号登录问题
      await fix123456QQComLogin();
    } catch (e) {
      // 在此处理初始化失败的情况，例如记录日志
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YouAI',
      theme: ThemeData(
        primarySwatch: const MaterialColor(0xFF9E9E9E, {
          50: Color(0xFFFAFAFA),
          100: Color(0xFFF5F5F5),
          200: Color(0xFFEEEEEE),
          300: Color(0xFFE0E0E0),
          400: Color(0xFFBDBDBD),
          500: Color(0xFF9E9E9E),
          600: Color(0xFF757575),
          700: Color(0xFF616161),
          800: Color(0xFF424242),
          900: Color(0xFF212121),
        }),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: const MaterialColor(0xFF9E9E9E, {
            50: Color(0xFFFAFAFA),
            100: Color(0xFFF5F5F5),
            200: Color(0xFFEEEEEE),
            300: Color(0xFFE0E0E0),
            400: Color(0xFFBDBDBD),
            500: Color(0xFF9E9E9E),
            600: Color(0xFF757575),
            700: Color(0xFF616161),
            800: Color(0xFF424242),
            900: Color(0xFF212121),
          }),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      ),
      home: const KnowledgeBaseScreen(),
    );
  }
}

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key, this.initialConversationId});

  final int? initialConversationId;

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isThinking = false;
  bool _isUploadingFile = false;
  int? _currentConversationId;
  int _messageCount = 0; // 当前会话的消息计数
  static const int _maxMessagesPerSession = 15; // 每个会话最大消息数

  // 添加会话开始时间，用于会话过期检查
  DateTime? _sessionStartTime;

  // 会话过期时间（小时）
  static const int _sessionExpirationHours = 24;

  @override
  void initState() {
    super.initState();
    // 初始化会话开始时间
    _sessionStartTime = DateTime.now();

    // 如果有初始对话ID，加载历史对话
    if (widget.initialConversationId != null) {
      _loadHistoryConversation(widget.initialConversationId!);
    }
  }

  // 加载历史对话
  Future<void> _loadHistoryConversation(int conversationId) async {
    if (!mounted) return;

    setState(() {
      _isThinking = true;
      _messages.clear();
    });

    try {
      // 获取历史消息
      final messages = await VectorDBService.getMessages(conversationId);

      // 计算当前会话的消息数量（只计算用户消息）
      _messageCount = messages.where((msg) => msg['role'] == 'user').length;

      // 转换为UI消息格式
      final uiMessages = messages.map((msg) {
        final Map<String, dynamic> uiMessage = {
          'role': msg['role'] == 'assistant'
              ? 'assistant'
              : msg['role'], // 确保角色正确
          'content': msg['content'],
          'time': DateTime.fromMillisecondsSinceEpoch(msg['createdAt'] as int),
        };

        // 如果有文件信息，解析并添加到消息中
        if (msg['files'] != null &&
            msg['files'] is String &&
            (msg['files'] as String).isNotEmpty) {
          try {
            final List<dynamic> filesData = jsonDecode(msg['files'] as String);
            final List<Document> files = filesData.map<Document>((fileData) {
              // 根据文件类型处理内容
              String rawContent = fileData['content'] as String;
              String aiContent = fileData.containsKey('aiContent')
                  ? fileData['aiContent'] as String
                  : fileData['content'] as String; // 兼容旧数据

              // 对于Excel和Word文件，需要分别处理rawContent和aiContent
              if (fileData['type'] == 'excel' &&
                  !fileData.containsKey('aiContent')) {
                // 旧数据，需要重新处理
                aiContent = FileService.processExcelForAI(rawContent);
              } else if (fileData['type'] == 'word' &&
                  !fileData.containsKey('aiContent')) {
                // 旧数据，需要重新处理
                rawContent = FileService.formatWordForPreview(rawContent);
              }

              return Document(
                id: fileData['id'],
                title: fileData['title'],
                type: fileData['type'],
                rawContent: rawContent,
                aiContent: aiContent,
                embedding: [], // 空嵌入向量，因为这里只是显示历史消息
                createdAt: DateTime.now(), // 使用当前时间作为默认值
                filePath: fileData['filePath'],
              );
            }).toList();
            uiMessage['files'] = files;
          } catch (e) {
            DiagnosticService().log(
              '解析文件信息失败',
              level: LogLevel.error,
              error: e,
            );
          }
        }

        return uiMessage;
      }).toList();

      if (!mounted) return;

      setState(() {
        _messages.addAll(uiMessages);
        _currentConversationId = conversationId;
      });
    } catch (e) {
      DiagnosticService().log('加载历史对话失败', level: LogLevel.error, error: e);
    } finally {
      if (mounted) {
        setState(() {
          _isThinking = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 检查会话是否过期
  bool _isSessionExpired() {
    if (_sessionStartTime == null) return true;

    final now = DateTime.now();
    final difference = now.difference(_sessionStartTime!);
    return difference.inHours >= _sessionExpirationHours;
  }

  // 重置会话
  void _resetSession() {
    setState(() {
      _messages.clear();
      _currentConversationId = null;
      _inputFiles.clear();
      _messageCount = 0;
      _sessionStartTime = DateTime.now(); // 重置会话开始时间
    });
  }

  // 显示会话限制对话框
  void _showSessionLimitDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.amber[600]),
            const SizedBox(width: 8),
            const Text('会话限制'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('您已达到单次会话的对话次数上限（15次）。', style: TextStyle(fontSize: 16)),
            SizedBox(height: 12),
            Text(
              '为了获得更好的体验，请创建新的会话继续对话。',
              style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // 关闭对话框
            },
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // 关闭对话框
              _resetSession(); // 重置会话
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: const Color(0xFFFFFFFF),
            ),
            child: const Text('新建会话'),
          ),
        ],
      ),
    );
  }

  // 创建新会话
  void _createNewSession() {
    _resetSession(); // 使用统一的会话重置方法
  }

  Future<void> _uploadFile() async {
    final result = await showDialog<File?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择文件类型'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('支持以下文件格式：'),
            SizedBox(height: 8),
            Text('• PDF文档 (.pdf)', style: TextStyle(fontSize: 12)),
            Text('• Word文档 (.docx, .doc)', style: TextStyle(fontSize: 12)),
            Text('• Excel表格 (.xlsx, .xls)', style: TextStyle(fontSize: 12)),
            Text(
              '• 图片文件 (.jpg, .png, .gif, .bmp)',
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 8),
            Text(
              '文件大小限制：10MB',
              style: TextStyle(fontSize: 12, color: Color(0xFFF44336)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final file = await FileService.pickDocument();
              if (context.mounted) Navigator.pop(context, file);
            },
            icon: const Icon(Icons.description),
            label: const Text('文档'),
          ),
          TextButton.icon(
            onPressed: () async {
              final file = await FileService.pickImage();
              if (context.mounted) Navigator.pop(context, file);
            },
            icon: const Icon(Icons.image),
            label: const Text('图片'),
          ),
        ],
      ),
    );

    if (result == null) return;

    // 设置文件上传状态
    setState(() {
      _isUploadingFile = true;
    });

    try {
      // 检查文件大小，限制为10MB
      final fileSizeInBytes = await result.length();
      final maxFileSizeInBytes = 10 * 1024 * 1024; // 10MB

      if (fileSizeInBytes > maxFileSizeInBytes) {
        // 重置上传状态
        setState(() {
          _isUploadingFile = false;
        });
        return;
      }

      String type;
      String title = result.path.split(Platform.pathSeparator).last;
      final filePath = result.path.toLowerCase();

      // 使用新的解析方法，获取原始内容和AI内容
      final parseResult = await FileService.parseFileWithSeparateContent(
        result,
      );
      final rawContent = parseResult['rawContent']!;
      final aiContent = parseResult['aiContent']!;

      if (filePath.endsWith('.pdf')) {
        type = 'pdf';
      } else if (filePath.endsWith('.docx') || filePath.endsWith('.doc')) {
        type = 'word';
      } else if (filePath.endsWith('.xlsx') || filePath.endsWith('.xls')) {
        type = 'excel';
      } else {
        type = 'image';
      }

      // 生成嵌入向量，使用AI内容
      final embedding = await AIService.generateEmbedding(aiContent);
      if (embedding.every((e) => e == 0.0)) {
        throw Exception('无法为此文件生成有效的向量嵌入，请检查AI服务。');
      }

      final document = Document(
        title: title,
        type: type,
        rawContent: rawContent,
        aiContent: aiContent,
        embedding: embedding,
        createdAt: DateTime.now(),
        filePath: result.path,
      );

      await VectorDBService.storeDocument(document);

      // 将文件添加到输入区域的文件卡片中
      setState(() {
        _inputFiles.add(document);
      });

      // 重置上传状态
      setState(() {
        _isUploadingFile = false;
      });
    } catch (e) {
      // 重置上传状态
      setState(() {
        _isUploadingFile = false;
      });
    }
  }

  void _sendMessage() async {
    // 检查用户是否登录
    if (!UserService().isLoggedIn) {
      // 显示登录提示
      if (mounted) {
        // 使用顶部灰底白字提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '请先登录',
              style: TextStyle(color: Color(0xFFFFFFFF)),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 200, left: 16, right: 16),
            backgroundColor: const Color(0xFF9E9E9E),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            duration: const Duration(seconds: 5),
            elevation: 4,
          ),
        );

        // 跳转到登录页面
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
      return;
    }

    // 检查会话是否过期
    if (_isSessionExpired()) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('会话已过期'),
            content: const Text('您的会话已超过24小时，请创建新会话继续对话。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _resetSession();
                },
                child: const Text('创建新会话'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final query = _queryController.text.trim();
    // 检查是否有输入：如果有文件，必须有查询；如果没有文件，查询不能为空
    if (query.isEmpty) {
      if (_inputFiles.isNotEmpty) {
        // 显示错误提示
        if (mounted) {
          // 使用顶部灰底白字提示
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '发送图片时请输入问题描述',
                style: TextStyle(color: Color(0xFFFFFFFF)),
              ),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 200, left: 16, right: 16),
              backgroundColor: const Color(0xFF9E9E9E),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              duration: const Duration(seconds: 5),
              elevation: 4,
            ),
          );
        }
        return;
      } else {
        return;
      }
    }

    // 检查是否超过单次会话的对话次数限制
    if (_messageCount >= _maxMessagesPerSession) {
      _showSessionLimitDialog();
      return;
    }

    // 获取当前时间
    final currentTime = DateTime.now();

    // 构建用户消息
    final userMessage = {'role': 'user', 'content': query, 'time': currentTime};

    // 如果有上传的文件，将文件信息添加到消息中
    if (_inputFiles.isNotEmpty) {
      userMessage['files'] = _inputFiles;
    }

    setState(() {
      _messages.add(userMessage);
      _queryController.clear();
      _isThinking = true;
      _messageCount++; // 增加消息计数
    });
    _scrollToBottom();

    try {
      // 从Sqflite读取所有文档，确保使用最新内容
      final allDocuments = await VectorDBService.getAllDocuments();

      // 提取查询关键词
      final queryEmbedding = await AIService.generateEmbedding(query);

      // 获取相关文档，包括与查询相似的文档和上传的文件
      List<Document> allRelevantDocs = [];

      // 如果有上传的文件，优先使用上传的文件
      if (_inputFiles.isNotEmpty) {
        // 只使用上传的文件，不进行相似性搜索
        allRelevantDocs.addAll(_inputFiles);
      } else {
        // 没有上传文件时，才进行相似性搜索
        final similarDocs = await VectorDBService.similaritySearch(
          queryEmbedding,
          2, // 减少相似文档数量
        );
        allRelevantDocs.addAll(similarDocs);
      }

      // 确保文档内容是最新的（从数据库中获取）
      final updatedRelevantDocs = allRelevantDocs.map((doc) {
        // 查找数据库中对应的最新文档
        final updatedDoc = allDocuments.firstWhere(
          (d) => d.id == doc.id,
          orElse: () => doc, // 如果没找到，使用原来的文档
        );
        return updatedDoc;
      }).toList();

      // 处理所有文档：提取相关内容发给AI，包括PDF、Word、Excel和图片
      final contextDocs = updatedRelevantDocs.map((doc) {
        // 使用智能文档内容处理，替代简单截取，使用aiContent字段
        return FileService.processDocumentContent(doc.aiContent, doc.type);
      }).toList();

      // 检查是否有图片文件
      final imageFiles = _inputFiles
          .where((file) => file.type == 'image')
          .toList();
      String? imageBase64;
      String? imageFormat;

      // 如果有图片，获取Base64编码和格式
      if (imageFiles.isNotEmpty) {
        final firstImageFile = File(imageFiles.first.filePath!);
        final imageData = await FileService.getImageBase64WithFormat(
          firstImageFile,
        );
        imageBase64 = imageData['base64'];
        imageFormat = imageData['format'];
      }

      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': '',
          'time': DateTime.now(),
        });
      });
      _scrollToBottom();

      // 准备历史消息（如果有当前会话ID）
      List<Map<String, dynamic>>? historyMessages;
      if (_currentConversationId != null) {
        final dbMessages = await VectorDBService.getMessages(
          _currentConversationId!,
        );
        // 转换为AI服务需要的格式，只包含用户和AI消息，过滤掉系统消息
        historyMessages = dbMessages
            .where((msg) => msg['role'] == 'user' || msg['role'] == 'assistant')
            .map(
              (msg) => {
                'role': msg['role'] == 'assistant' ? 'assistant' : msg['role'],
                'content': msg['content'],
              },
            )
            .toList();

        // 确保历史消息格式正确，移除可能导致400错误的消息
        historyMessages = historyMessages.where((msg) {
          // 检查消息是否有有效的角色和内容
          final role = msg['role'] as String?;
          final content = msg['content'] as String?;
          return role != null &&
              content != null &&
              content.isNotEmpty &&
              (role == 'user' || role == 'assistant');
        }).toList();
      }

      // 根据是否有图片选择调用不同的AI服务方法
      final stream = imageBase64 != null && imageFormat != null
          ? AIService.sendMessageWithImageStream(
              query,
              contextDocs,
              imageBase64,
              imageFormat,
              historyMessages: historyMessages,
            )
          : AIService.sendMessageStream(
              query,
              contextDocs,
              historyMessages: historyMessages,
            );

      // 如果用户已登录，保存用户消息
      if (UserService().isLoggedIn) {
        // 如果没有当前对话ID，创建新对话
        _currentConversationId ??= await VectorDBService.createConversation(
          UserService().currentUserId!,
          query.length > 20 ? '${query.substring(0, 20)}...' : query,
        );
        // 将文件信息序列化为JSON字符串
        String? filesJson;
        if (_inputFiles.isNotEmpty) {
          filesJson = jsonEncode(
            _inputFiles
                .map(
                  (file) => {
                    'id': file.id,
                    'title': file.title,
                    'type': file.type,
                    'content': file.rawContent, // 保存原始内容，用于预览
                    'aiContent': file.aiContent, // 保存AI内容，用于解析
                    'filePath': file.filePath,
                  },
                )
                .toList(),
          );
        }

        await VectorDBService.addMessage(
          _currentConversationId!,
          'user',
          query,
          files: filesJson,
        );
      }

      // 收集AI回复
      String aiResponse = '';
      await for (final chunk in stream) {
        aiResponse += chunk;
        if (mounted) {
          setState(() {
            _messages.last['content'] = aiResponse;
          });
        }
        _scrollToBottom();
      }

      // 如果用户已登录，保存AI回复
      if (UserService().isLoggedIn && _currentConversationId != null) {
        await VectorDBService.addMessage(
          _currentConversationId!,
          'assistant', // 使用'assistant'角色而不是'ai'
          aiResponse,
        );
      }

      // 发送成功后清空输入区域的文件卡片
      if (mounted) {
        setState(() {
          _inputFiles.clear();
        });
      }
    } catch (e) {
      // 分析错误类型，提供更具体的错误信息
      String errorMessage = '抱歉，处理请求时出错';
      String errorDetail = '';

      // 根据错误信息提供更具体的提示
      if (e.toString().contains('连接超时') ||
          e.toString().contains('connection timeout')) {
        errorMessage = '网络连接超时';
        errorDetail = '请检查您的网络连接，然后重试。';
      } else if (e.toString().contains('API密钥') ||
          e.toString().contains('401')) {
        errorMessage = 'API认证失败';
        errorDetail = 'API密钥无效或已过期，请联系管理员。';
      } else if (e.toString().contains('请求频率') ||
          e.toString().contains('429')) {
        errorMessage = '请求过于频繁';
        errorDetail = '您发送请求的频率过高，请稍后再试。';
      } else if (e.toString().contains('服务器') || e.toString().contains('500')) {
        errorMessage = '服务器内部错误';
        errorDetail = '服务器暂时无法处理请求，请稍后再试。';
      } else if (e.toString().contains('网络') ||
          e.toString().contains('network')) {
        errorMessage = '网络连接错误';
        errorDetail = '请检查您的网络设置，确保设备已连接到互联网。';
      } else {
        errorDetail = e.toString();
      }

      final fullErrorMessage = errorDetail.isNotEmpty
          ? '$errorMessage：$errorDetail'
          : '$errorMessage：$e';

      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty &&
              _messages.last['role'] == 'assistant' &&
              _messages.last['content']!.isEmpty) {
            _messages.last['content'] = fullErrorMessage;
            _messages.last['time'] = DateTime.now();
          } else {
            _messages.add({
              'role': 'assistant', // 使用'assistant'角色而不是'ai'
              'content': fullErrorMessage,
              'time': DateTime.now(),
            });
          }
        });

        // 显示错误提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Color(0xFFFFFFFF)),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 200, left: 16, right: 16),
            backgroundColor: const Color(0xFFF44336),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            duration: const Duration(seconds: 5),
            elevation: 4,
            action: SnackBarAction(
              label: '重试',
              textColor: const Color(0xFFFFFFFF),
              onPressed: () {
                // 清除错误消息并重试发送
                setState(() {
                  if (_messages.isNotEmpty &&
                      _messages.last['role'] == 'assistant') {
                    _messages.removeLast();
                  }
                });
                _sendMessage();
              },
            ),
          ),
        );
      }

      // 如果用户已登录，保存错误信息
      if (UserService().isLoggedIn && _currentConversationId != null) {
        await VectorDBService.addMessage(
          _currentConversationId!,
          'assistant', // 使用'assistant'角色而不是'ai'
          fullErrorMessage,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isThinking = false);
      }
      _scrollToBottom();
    }
  }

  // 用于存储当前输入区域的文件卡片
  final List<Document> _inputFiles = [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      resizeToAvoidBottomInset: true, // 确保键盘弹出时布局调整
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 5 / 6, // 覆盖主页5/6
        child: const UserScreen(),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF000000),
        title: const Text('YouAI', style: TextStyle(color: Color(0xFF000000))),
        elevation: 0,
        actions: [
          // 新建对话按钮
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF000000)),
            onPressed: () {
              _createNewSession();
            },
            tooltip: '新建对话',
          ),
          PopupMenuButton(
            color: const Color(0xFFFFFFFF),
            surfaceTintColor: const Color(0xFFFFFFFF),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Text('诊断信息', style: TextStyle(color: Color(0xFF000000))),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiagnosticScreen(),
                    ),
                  );
                },
              ),
              PopupMenuItem(
                child: Text(
                  '运行诊断测试',
                  style: TextStyle(color: Color(0xFF000000)),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiagnosticRunner(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: const Color(0xFFFFFFFF),
          child: Column(
            children: [
              // 对话区域 - 占据大部分空间
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  // 移除边框和阴影，让对话框更简洁
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 80,
                                color: const Color(
                                  0xFF000000,
                                ).withAlpha(51), // 0.2 * 255 = 51
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '向你的知识库问点什么吧',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: const Color(
                                    0xFF000000,
                                  ).withAlpha(178), // 0.7 * 255 = 178
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isUser = message['role'] == 'user';
                            final messageTime = message['time'] as DateTime;
                            final bool showTime =
                                index == 0 ||
                                messageTime
                                        .difference(
                                          _messages[index - 1]['time']
                                              as DateTime,
                                        )
                                        .inMinutes >=
                                    5;

                            return Column(
                              children: [
                                // 显示时间（如果需要）
                                if (showTime)
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF9E9E9E,
                                      ).withAlpha(25), // 0.1 * 255 = 25
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      messageTime.toString().substring(11, 16),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: const Color(
                                          0xFF000000,
                                        ).withAlpha(128), // 0.5 * 255 = 128
                                      ),
                                    ),
                                  ),

                                // 消息内容
                                isUser
                                    ? // 用户消息：白底黑字，减小气泡体积
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topLeft: Radius.circular(16),
                                                  topRight: Radius.circular(16),
                                                  bottomLeft: Radius.circular(
                                                    16,
                                                  ),
                                                  bottomRight: Radius.circular(
                                                    4,
                                                  ),
                                                ),
                                            color: const Color(0xFFFFFFFF),
                                            boxShadow: [
                                              BoxShadow(
                                                color: theme.colorScheme.shadow
                                                    .withAlpha(
                                                      25,
                                                    ), // 0.1 * 255 = 25
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.85,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              // 文本消息内容：使用SelectableText，黑字
                                              if ((message['content']
                                                          as String? ??
                                                      '')
                                                  .isNotEmpty)
                                                SelectableText(
                                                  message['content']
                                                          as String? ??
                                                      '',
                                                  style: TextStyle(
                                                    color: const Color(
                                                      0xFF000000,
                                                    ),
                                                    fontSize: 16,
                                                  ),
                                                ),

                                              // 如果有文件，显示文件预览
                                              if ((message['files']
                                                          as List<Document>? ??
                                                      [])
                                                  .isNotEmpty)
                                                const SizedBox(height: 8),

                                              // 遍历文件列表并显示
                                              for (var file
                                                  in (message['files']
                                                          as List<Document>? ??
                                                      []))
                                                GestureDetector(
                                                  onTap: () {
                                                    // 点击预览文件
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            DocumentViewScreen(
                                                              document: file,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          top: 6,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          const BorderRadius.all(
                                                            Radius.circular(6),
                                                          ),
                                                      color:
                                                          const Color(
                                                            0xFF9E9E9E,
                                                          ).withAlpha(
                                                            25,
                                                          ), // 0.1 * 255 = 25
                                                    ),
                                                    child: file.type == 'image'
                                                        ? Image.file(
                                                            File(
                                                              file.filePath!,
                                                            ),
                                                            width: 180,
                                                            height: 180,
                                                            fit: BoxFit.cover,
                                                          )
                                                        : Row(
                                                            children: [
                                                              // 根据文件类型显示不同的图标
                                                              Icon(
                                                                file.type ==
                                                                        'pdf'
                                                                    ? Icons
                                                                          .picture_as_pdf
                                                                    : file.type ==
                                                                          'word'
                                                                    ? Icons
                                                                          .description
                                                                    : file.type ==
                                                                          'excel'
                                                                    ? Icons
                                                                          .table_chart
                                                                    : Icons
                                                                          .image,
                                                                size: 28,
                                                                color: Colors
                                                                    .black,
                                                              ),
                                                              const SizedBox(
                                                                width: 6,
                                                              ),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Text(
                                                                      file.title,
                                                                      style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        color: Colors
                                                                            .black,
                                                                      ),
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                    // 根据文件类型显示不同的信息
                                                                    Text(
                                                                      file.type ==
                                                                              'pdf'
                                                                          ? () {
                                                                              // 安全提取PDF页数
                                                                              final content = file.rawContent;
                                                                              final pagesMatch =
                                                                                  RegExp(
                                                                                    r'页数: (\d+)',
                                                                                  ).firstMatch(
                                                                                    content,
                                                                                  );
                                                                              if (pagesMatch !=
                                                                                      null &&
                                                                                  pagesMatch.groupCount >
                                                                                      0) {
                                                                                return '${pagesMatch.group(1)}页';
                                                                              }
                                                                              return 'PDF文档';
                                                                            }()
                                                                          : file.type ==
                                                                                'word'
                                                                          ? 'Word文档'
                                                                          : file.type ==
                                                                                'excel'
                                                                          ? 'Excel表格'
                                                                          : '图片',
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                        color: Colors
                                                                            .black
                                                                            .withAlpha(
                                                                              178,
                                                                            ), // 0.7 * 255 = 178
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : // AI消息：从屏幕最左侧到最右侧，使用SelectableText
                                      Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        color: const Color(0xFFFFFFFF),
                                        child: SelectableText(
                                          message['content'] as String? ?? '',
                                          style: TextStyle(
                                            color: const Color(0xFF000000),
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                              ],
                            );
                          },
                        ),
                ),
              ),

              // 输入区域的文件卡片
              if (_inputFiles.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _inputFiles.map((document) {
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 150,
                          height: 150,
                          child: GestureDetector(
                            onTap: () {
                              // 点击卡片预览文件
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      DocumentViewScreen(document: document),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 2,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              surfaceTintColor: const Color(0xFFFFFFFF),
                              color: const Color(0xFFFFFFFF),
                              child: Stack(
                                children: [
                                  // 显示实际的图片或文件预览
                                  if (document.type == 'image')
                                    Positioned.fill(
                                      child: Image.file(
                                        File(document.filePath!),
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else
                                    Positioned.fill(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            document.type == 'pdf'
                                                ? Icons.picture_as_pdf
                                                : document.type == 'word'
                                                ? Icons.description
                                                : document.type == 'excel'
                                                ? Icons.table_chart
                                                : Icons.image,
                                            size: 48,
                                            color: const Color(0xFF000000),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            document.title,
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFF000000,
                                                  ),
                                                ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            document.type == 'pdf'
                                                ? () {
                                                    // 安全提取PDF页数
                                                    final content =
                                                        document.rawContent;
                                                    final pagesMatch = RegExp(
                                                      r'页数: (\d+)',
                                                    ).firstMatch(content);
                                                    if (pagesMatch != null &&
                                                        pagesMatch.groupCount >
                                                            0) {
                                                      return '${pagesMatch.group(1)}页';
                                                    }
                                                    return 'PDF文档';
                                                  }()
                                                : document.type == 'word'
                                                ? 'Word文档'
                                                : document.type == 'excel'
                                                ? 'Excel表格'
                                                : '图片',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: const Color(0xFF000000)
                                                      .withAlpha(
                                                        128,
                                                      ), // 0.5 * 255 = 128
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  // 右上角X号删除按钮
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFFFFFFF,
                                        ).withAlpha(204), // 0.8 * 255 = 204
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.close,
                                          size: 16,
                                          color: const Color(0xFF000000),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _inputFiles.remove(document);
                                          });
                                          // 直接删除文档，不显示确认对话框
                                          if (document.id != null) {
                                            VectorDBService.deleteDocument(
                                              document.id!,
                                            );
                                          }
                                        },
                                        tooltip: '删除',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // 底部输入栏
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: const Color(0xFFFFFFFF),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(28)),
                    color: const Color(0xFFFFFFFF),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF000000,
                        ).withAlpha(26), // 0.1 * 255 = 25.5 ≈ 26
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // 左侧：+号/曲别针图标
                      IconButton(
                        icon: Icon(
                          Icons.attach_file,
                          size: 24,
                          color: Color(0xFF000000),
                        ),
                        onPressed: _uploadFile,
                        tooltip: '上传文件',
                      ),

                      // 中间：TextField输入框
                      Expanded(
                        child: TextField(
                          controller: _queryController,
                          decoration: InputDecoration(
                            hintText: '输入你的问题...',
                            hintStyle: TextStyle(
                              color: const Color(
                                0xFF000000,
                              ).withAlpha(128), // 0.5 * 255 = 128
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          style: TextStyle(color: const Color(0xFF000000)),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),

                      // 右侧：发送按钮（仅保留图标，黑色背景）
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (_isThinking || _isUploadingFile)
                              ? null
                              : _sendMessage,
                          style: ElevatedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            backgroundColor: const Color(0xFF000000),
                            foregroundColor: const Color(0xFFFFFFFF),
                          ),
                          child: (_isThinking || _isUploadingFile)
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFFFFF),
                                  ),
                                )
                              : Icon(Icons.send, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
