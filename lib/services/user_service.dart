import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'vector_db_service.dart';
import 'diagnostic_service.dart';

class UserService {
  // 单例模式
  static final UserService _instance = UserService._internal();

  factory UserService() {
    return _instance;
  }

  UserService._internal();

  // 当前登录用户信息
  Map<String, dynamic>? _currentUser;

  // SharedPreferences 键名
  static const String _userKey = 'logged_in_user';

  // 是否登录
  bool get isLoggedIn => _currentUser != null;

  // 获取当前用户ID
  int? get currentUserId => _currentUser?['id'] as int?;

  // 获取当前用户邮箱
  String? get currentUserEmail => _currentUser?['email'] as String?;

  // 获取当前用户名
  String? get currentUsername => _currentUser?['username'] as String?;

  // 初始化方法 - 从本地存储加载用户信息
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);

      if (userJson != null && userJson.isNotEmpty) {
        _currentUser = jsonDecode(userJson) as Map<String, dynamic>;
      }
    } catch (e) {
      // 如果加载失败，清除可能损坏的数据
      _currentUser = null;
    }
  }

  // 登录方法
  Future<void> login(Map<String, dynamic> user) async {
    _currentUser = user;

    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user));
    } catch (e) {
      // 保存失败不影响登录，只是下次启动时需要重新登录
    }
  }

  // 登出方法
  Future<void> logout() async {
    _currentUser = null;

    // 从本地存储清除
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
    } catch (e) {
      // 清除失败不影响登出
    }
  }

  // 更新用户信息 - 快速同步更新内存和本地存储，异步更新数据库
  Future<void> updateUser(Map<String, dynamic> userData) async {
    if (_currentUser == null) return;

    final userId = _currentUser!['id'] as int?;

    // 合并更新数据到当前用户信息（立即生效）
    _currentUser!.addAll(userData);

    // 快速更新本地存储（同步完成）
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(_currentUser));
    } catch (e) {
      DiagnosticService().log(
        'UserService: 本地存储更新失败',
        level: LogLevel.error,
        error: e,
      );
    }

    // 后台异步更新数据库（不影响UI响应）
    if (userId != null) {
      _syncToDatabase(userId, userData);
    }
  }

  // 后台同步到数据库
  void _syncToDatabase(int userId, Map<String, dynamic> userData) {
    Future(() async {
      try {
        // 调用 initialize()，内部有重复初始化保护
        await VectorDBService.initialize();
        final result = await VectorDBService.updateUser(userId, userData);
        DiagnosticService().log(
          'UserService: 数据库同步完成，更新行数: $result',
          level: LogLevel.info,
        );
      } catch (e) {
        // 数据库更新失败不影响用户体验，下次登录时会从数据库重新加载
        DiagnosticService().log(
          'UserService: 数据库后台同步失败（不影响本地数据）',
          level: LogLevel.warning,
          error: e,
        );
      }
    });
  }
}
