import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/vector_db_service.dart';
import '../services/diagnostic_service.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final UserService _userService = UserService();

  // 密码修改相关控制器
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // 修改密码
  Future<void> _changePassword() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // 验证输入
      final oldPassword = _oldPasswordController.text.trim();
      final newPassword = _newPasswordController.text.trim();
      final confirmPassword = _confirmPasswordController.text.trim();

      if (oldPassword.isEmpty ||
          newPassword.isEmpty ||
          confirmPassword.isEmpty) {
        throw Exception('请填写所有字段');
      }

      if (newPassword != confirmPassword) {
        throw Exception('两次输入的新密码不匹配');
      }

      if (newPassword.length < 6) {
        throw Exception('新密码长度不能少于6个字符');
      }

      // 获取当前用户ID和邮箱
      final userId = _userService.currentUserId;
      final email = _userService.currentUserEmail;

      if (userId == null || email == null) {
        throw Exception('用户未登录');
      }

      // 验证旧密码
      final user = await VectorDBService.loginUser(email, oldPassword);
      if (user == null) {
        throw Exception('旧密码错误');
      }

      // 更新密码
      await VectorDBService.database.update(
        'users',
        {'password': newPassword},
        where: 'id = ?',
        whereArgs: [userId],
      );

      // 显示成功信息
      setState(() {
        _successMessage = '密码修改成功';
        // 清空密码输入框
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        DiagnosticService().log('修改密码失败', level: LogLevel.error, error: e);
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 注销账号
  Future<void> _deleteAccount() async {
    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认注销账号'),
        content: const Text('注销账号后，所有数据将被永久删除，无法恢复。确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定注销'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 获取当前用户ID
      final userId = _userService.currentUserId;
      if (userId == null) {
        throw Exception('用户未登录');
      }

      // 删除用户相关数据
      // 1. 删除用户的所有消息
      await VectorDBService.database.delete(
        'messages',
        where:
            'conversationId IN (SELECT id FROM conversations WHERE userId = ?)',
        whereArgs: [userId],
      );

      // 2. 删除用户的所有对话
      await VectorDBService.database.delete(
        'conversations',
        where: 'userId = ?',
        whereArgs: [userId],
      );

      // 3. 删除用户的所有文档
      await VectorDBService.database.delete(
        'documents',
        where: 'userId = ?',
        whereArgs: [userId],
      );

      // 4. 删除用户
      await VectorDBService.database.delete(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );

      // 5. 退出登录
      _userService.logout();

      // 返回首页，检查Widget是否仍然挂载
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '注销失败，请重试';
        DiagnosticService().log('注销账号失败', level: LogLevel.error, error: e);
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('账号管理', style: TextStyle(color: Colors.black)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 密码修改部分
              const Text(
                '修改密码',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 旧密码
              const Text(
                '旧密码',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _oldPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '请输入旧密码',
                  hintStyle: TextStyle(color: Colors.black.withAlpha(128)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withAlpha(76)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 新密码
              const Text(
                '新密码',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '请输入新密码（至少6个字符）',
                  hintStyle: TextStyle(color: Colors.black.withAlpha(128)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withAlpha(76)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 确认新密码
              const Text(
                '确认新密码',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '请再次输入新密码',
                  hintStyle: TextStyle(color: Colors.black.withAlpha(128)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withAlpha(76)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 错误信息
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),

              // 成功信息
              if (_successMessage != null)
                Text(
                  _successMessage!,
                  style: const TextStyle(color: Colors.green, fontSize: 14),
                ),

              const SizedBox(height: 16),

              // 修改密码按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '修改密码',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 48),

              // 账号注销部分
              const Text(
                '账号注销',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                '注销账号后，所有数据将被永久删除，无法恢复。',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // 注销账号按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _deleteAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '注销账号',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
