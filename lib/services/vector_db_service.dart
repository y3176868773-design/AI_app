import 'dart:async';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/document.dart';
import './diagnostic_service.dart';

class VectorDBService {
  static Database? _database;
  static bool _isInitialized = false;
  static Completer<void>? _initializationCompleter;

  VectorDBService._();

  static Database get database {
    if (!_isInitialized || _database == null) {
      throw StateError('VectorDBService has not been initialized');
    }
    return _database!;
  }

  static Future<void> initialize() async {
    if (_isInitialized && _database != null) {
      return;
    }

    if (_initializationCompleter != null) {
      try {
        await _initializationCompleter!.future;
        return;
      } catch (e) {
        _initializationCompleter = null;
      }
    }

    _initializationCompleter = Completer<void>();

    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'vector_db.db');

      DiagnosticService().log('数据库路径: $path', level: LogLevel.info);

      _database = await openDatabase(
        path,
        version: 5, // 增加版本号，确保onUpgrade被调用
        onCreate: _onCreate,
        onUpgrade: _onUpgrade, // 添加升级回调
      );

      _isInitialized = true;
      _initializationCompleter!.complete();
      DiagnosticService().log('数据库初始化成功', level: LogLevel.info);
    } catch (e, stackTrace) {
      _isInitialized = false;
      _database = null;
      _initializationCompleter!.completeError(e, stackTrace);
      DiagnosticService().log(
        '数据库初始化失败',
        level: LogLevel.error,
        error: e,
        stackTrace: stackTrace,
      );
      // 不要重新抛出异常，让应用能够继续运行
      // rethrow;
    } finally {
      _initializationCompleter = null;
    }
  }

  // 单独的创建表方法
  static Future<void> _onCreate(Database db, int version) async {
    DiagnosticService().log('执行onCreate，创建所有表', level: LogLevel.info);

    // 创建documents表
    await db.execute('''
      CREATE TABLE documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        ai_content TEXT NOT NULL,
        embedding TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        filePath TEXT,
        userId INTEGER
      )
    ''');
    DiagnosticService().log('documents表创建成功', level: LogLevel.info);

    // 创建users表
    await db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          username TEXT,
          createdAt INTEGER NOT NULL,
          avatar TEXT
        )
      ''');
    DiagnosticService().log('users表创建成功', level: LogLevel.info);

    // 创建conversations表
    await db.execute('''
      CREATE TABLE conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        title TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    DiagnosticService().log('conversations表创建成功', level: LogLevel.info);

    // 创建messages表
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversationId INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        files TEXT,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY (conversationId) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    DiagnosticService().log('messages表创建成功', level: LogLevel.info);
  }

  // 升级回调，确保所有表都存在
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    DiagnosticService().log(
      '执行onUpgrade，从版本$oldVersion升级到$newVersion',
      level: LogLevel.info,
    );

    // 检查并创建缺失的表
    try {
      // 向users表添加avatar字段（如果不存在）
      if (oldVersion < 3) {
        try {
          // 先检查列是否已存在
          final tableInfo = await db.rawQuery("PRAGMA table_info(users)");
          final hasAvatarColumn = tableInfo.any(
            (column) => column['name'] == 'avatar',
          );

          if (!hasAvatarColumn) {
            await db.execute('ALTER TABLE users ADD COLUMN avatar TEXT');
            DiagnosticService().log('已向users表添加avatar字段', level: LogLevel.info);
          } else {
            DiagnosticService().log(
              'users表已存在avatar字段，跳过添加',
              level: LogLevel.info,
            );
          }
        } catch (e) {
          DiagnosticService().log(
            '添加avatar字段失败',
            level: LogLevel.error,
            error: e,
          );
        }
      }

      // 检查users表是否存在
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          username TEXT,
          createdAt INTEGER NOT NULL,
          avatar TEXT
        )
      ''');
      DiagnosticService().log('检查并创建users表完成', level: LogLevel.info);

      // 检查documents表是否存在
      await db.execute('''
        CREATE TABLE IF NOT EXISTS documents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          type TEXT NOT NULL,
          content TEXT NOT NULL,
          embedding TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          filePath TEXT,
          userId INTEGER
        )
      ''');
      DiagnosticService().log('检查并创建documents表完成', level: LogLevel.info);

      // 检查conversations表是否存在
      await db.execute('''
        CREATE TABLE IF NOT EXISTS conversations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          title TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');
      DiagnosticService().log('检查并创建conversations表完成', level: LogLevel.info);

      // 检查messages表是否存在
      await db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          conversationId INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          files TEXT,
          createdAt INTEGER NOT NULL,
          FOREIGN KEY (conversationId) REFERENCES conversations(id) ON DELETE CASCADE
        )
      ''');
      DiagnosticService().log('检查并创建messages表完成', level: LogLevel.info);

      // 向messages表添加files字段（如果不存在）
      if (oldVersion < 4) {
        try {
          // 先检查列是否已存在
          final tableInfo = await db.rawQuery("PRAGMA table_info(messages)");
          final hasFilesColumn = tableInfo.any(
            (column) => column['name'] == 'files',
          );

          if (!hasFilesColumn) {
            await db.execute('ALTER TABLE messages ADD COLUMN files TEXT');
            DiagnosticService().log(
              '已向messages表添加files字段',
              level: LogLevel.info,
            );
          } else {
            DiagnosticService().log(
              'messages表已存在files字段，跳过添加',
              level: LogLevel.info,
            );
          }
        } catch (e) {
          DiagnosticService().log(
            '添加files字段失败',
            level: LogLevel.error,
            error: e,
          );
        }
      }

      // 向documents表添加ai_content字段（如果不存在）
      if (oldVersion < 5) {
        try {
          // 先检查列是否已存在
          final tableInfo = await db.rawQuery("PRAGMA table_info(documents)");
          final hasAiContentColumn = tableInfo.any(
            (column) => column['name'] == 'ai_content',
          );

          if (!hasAiContentColumn) {
            await db.execute(
              'ALTER TABLE documents ADD COLUMN ai_content TEXT NOT NULL DEFAULT ""',
            );
            DiagnosticService().log(
              '已向documents表添加ai_content字段',
              level: LogLevel.info,
            );
          } else {
            DiagnosticService().log(
              'documents表已存在ai_content字段，跳过添加',
              level: LogLevel.info,
            );
          }
        } catch (e) {
          DiagnosticService().log(
            '添加ai_content字段失败',
            level: LogLevel.error,
            error: e,
          );
        }
      }
    } catch (e) {
      DiagnosticService().log('升级表结构时出错', level: LogLevel.error, error: e);
    }
  }

  static Future<void> _ensureInitialized() async {
    if (_isInitialized && _database != null) {
      return;
    }

    try {
      await initialize();
    } catch (e) {
      DiagnosticService().log(
        '确保数据库初始化失败，但继续执行',
        level: LogLevel.error,
        error: e,
      );
      // 不重新抛出异常，允许应用继续运行
    }
  }

  static Future<void> storeDocument(Document document) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法存储文档', level: LogLevel.error);
      return;
    }
    await _database!.insert(
      'documents',
      document.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteDocument(int documentId) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法删除文档', level: LogLevel.error);
      return;
    }
    await _database!.delete(
      'documents',
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  static Future<List<Document>> getAllDocuments() async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法获取文档', level: LogLevel.error);
      return [];
    }
    final List<Map<String, dynamic>> maps = await _database!.query('documents');
    return List.generate(maps.length, (i) => Document.fromMap(maps[i]));
  }

  static Future<List<Document>> similaritySearch(
    List<double> queryEmbedding,
    int limit,
  ) async {
    await _ensureInitialized();
    final allDocs = await getAllDocuments();

    final results = <Map<String, dynamic>>[];
    for (final doc in allDocs) {
      if (doc.embedding.isEmpty ||
          doc.embedding.length != queryEmbedding.length) {
        continue;
      }
      final similarity = _cosineSimilarity(doc.embedding, queryEmbedding);
      results.add({'document': doc, 'similarity': similarity});
    }

    results.sort(
      (a, b) =>
          (b['similarity'] as double).compareTo(a['similarity'] as double),
    );
    return results.take(limit).map((e) => e['document'] as Document).toList();
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return 0.0;
    }

    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final normProduct = sqrt(normA) * sqrt(normB);
    if (normProduct == 0) return 0.0;
    return dotProduct / normProduct;
  }

  static Future<int> registerUser(
    String email,
    String password, {
    String? username,
  }) async {
    // 1. 确保数据库初始化
    await _ensureInitialized();

    // 2. 确保users表存在
    await _ensureUsersTableExists();

    // 3. 记录调试信息
    DiagnosticService().log('=== 开始注册用户 ===', level: LogLevel.info);
    DiagnosticService().log('邮箱: $email', level: LogLevel.debug);
    DiagnosticService().log(
      '用户名: ${username ?? email.split('@')[0]}',
      level: LogLevel.debug,
    );

    final now = DateTime.now().millisecondsSinceEpoch;

    // 4. 执行插入操作
    try {
      if (_database == null) {
        DiagnosticService().log('数据库未初始化，无法注册用户', level: LogLevel.error);
        throw Exception('数据库未初始化');
      }

      final result = await _database!.insert('users', {
        'email': email,
        'password': password,
        'username': username ?? email.split('@')[0],
        'createdAt': now,
      });

      DiagnosticService().log('=== 注册成功 ===', level: LogLevel.info);
      DiagnosticService().log('插入结果: $result', level: LogLevel.debug);
      return result;
    } catch (e, stackTrace) {
      DiagnosticService().log('=== 注册失败 ===', level: LogLevel.error);
      DiagnosticService().log('错误信息: $e', level: LogLevel.error, error: e);
      DiagnosticService().log(
        '堆栈跟踪: $stackTrace',
        level: LogLevel.error,
        stackTrace: stackTrace,
      );

      // 如果还是表不存在的错误，尝试再次创建表
      if (e.toString().contains('no such table: users')) {
        DiagnosticService().log('再次尝试创建users表...', level: LogLevel.warning);
        await _createUsersTableDirectly();
        // 重新执行插入操作
        return await _database!.insert('users', {
          'email': email,
          'password': password,
          'username': username ?? email.split('@')[0],
          'createdAt': now,
        });
      }

      rethrow;
    }
  }

  // 确保users表存在的方法
  static Future<void> _ensureUsersTableExists() async {
    DiagnosticService().log('检查users表是否存在...', level: LogLevel.debug);

    if (_database == null) {
      await _ensureInitialized();
    }

    try {
      if (_database == null) {
        DiagnosticService().log('数据库未初始化，无法检查users表', level: LogLevel.error);
        return;
      }

      // 尝试查询表信息
      await _database!.query('users', limit: 1);
      DiagnosticService().log('users表已存在', level: LogLevel.debug);
    } catch (e) {
      DiagnosticService().log('users表不存在，尝试创建...', level: LogLevel.debug);
      await _createUsersTableDirectly();
    }
  }

  // 直接创建users表的方法
  static Future<void> _createUsersTableDirectly() async {
    if (_database == null) {
      await _ensureInitialized();
    }

    try {
      if (_database == null) {
        DiagnosticService().log('数据库未初始化，无法创建users表', level: LogLevel.error);
        return;
      }

      await _database!.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          username TEXT,
          createdAt INTEGER NOT NULL,
          avatar TEXT
        )
      ''');
      DiagnosticService().log('users表创建成功', level: LogLevel.info);
    } catch (e) {
      DiagnosticService().log(
        '创建users表失败: $e',
        level: LogLevel.error,
        error: e,
      );
      throw Exception('创建users表失败: $e');
    }
  }

  static Future<Map<String, dynamic>?> loginUser(
    String email,
    String password,
  ) async {
    await _ensureInitialized();
    final users = await _database!.query(
      'users',
      where: 'email = ? AND password = ?',
      whereArgs: [email, password],
    );
    return users.isNotEmpty ? users.first : null;
  }

  static Future<Map<String, dynamic>?> getUser(int userId) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法获取用户', level: LogLevel.error);
      return null;
    }

    final users = await _database!.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    );
    return users.isNotEmpty ? users.first : null;
  }

  static Future<int> updateUser(
    int userId,
    Map<String, dynamic> userData,
  ) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法更新用户', level: LogLevel.error);
      return -1;
    }

    // 过滤掉不允许更新的字段（如id, email等）
    final filteredData = Map<String, dynamic>.from(userData);
    filteredData.remove('id');
    filteredData.remove('email');
    filteredData.remove('password');
    filteredData.remove('createdAt');

    try {
      DiagnosticService().log(
        '准备更新用户数据: userId=$userId, data=$filteredData',
        level: LogLevel.info,
      );
      final result = await _database!.update(
        'users',
        filteredData,
        where: 'id = ?',
        whereArgs: [userId],
      );
      DiagnosticService().log('数据库更新结果: $result', level: LogLevel.info);
      return result;
    } catch (e) {
      DiagnosticService().log('更新用户数据失败: $e', level: LogLevel.error, error: e);
      rethrow;
    }
  }

  static Future<int> createConversation(int userId, String title) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法创建对话', level: LogLevel.error);
      return -1;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return await _database!.insert('conversations', {
      'userId': userId,
      'title': title,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  static Future<List<Map<String, dynamic>>> getConversations(int userId) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法获取对话', level: LogLevel.error);
      return [];
    }
    return await _database!.query(
      'conversations',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'updatedAt DESC',
    );
  }

  static Future<int> updateConversationTitle(
    int conversationId,
    String title,
  ) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法更新对话标题', level: LogLevel.error);
      return -1;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return await _database!.update(
      'conversations',
      {'title': title, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  static Future<int> deleteConversation(int conversationId) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法删除对话', level: LogLevel.error);
      return -1;
    }
    return await _database!.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  static Future<int> addMessage(
    int conversationId,
    String role,
    String content, {
    String? files,
  }) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法添加消息', level: LogLevel.error);
      return -1;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database!.update(
      'conversations',
      {'updatedAt': now},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    return await _database!.insert('messages', {
      'conversationId': conversationId,
      'role': role,
      'content': content,
      'files': files,
      'createdAt': now,
    });
  }

  static Future<List<Map<String, dynamic>>> getMessages(
    int conversationId,
  ) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法获取消息', level: LogLevel.error);
      return [];
    }
    return await _database!.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'createdAt ASC',
    );
  }

  static Future<int> deleteMessage(int messageId) async {
    await _ensureInitialized();
    if (_database == null) {
      DiagnosticService().log('数据库未初始化，无法删除消息', level: LogLevel.error);
      return -1;
    }
    return await _database!.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }
}
