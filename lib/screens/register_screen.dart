import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/vector_db_service.dart';
import '../services/diagnostic_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final confirmPassword = _confirmPasswordController.text.trim();

      // 验证输入
      if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
        setState(() {
          _errorMessage = '请填写所有字段';
        });
        return;
      }

      // 验证密码匹配
      if (password != confirmPassword) {
        setState(() {
          _errorMessage = '两次输入的密码不匹配';
        });
        return;
      }

      // 验证邮箱格式
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        setState(() {
          _errorMessage = '请输入有效的邮箱地址';
        });
        return;
      }

      // 验证密码长度
      if (password.length < 6) {
        setState(() {
          _errorMessage = '密码长度不能少于6个字符';
        });
        return;
      }

      // 调用实际的注册方法
      final userId = await VectorDBService.registerUser(email, password);

      if (userId > 0) {
        // 注册成功，自动登录
        final user = await VectorDBService.loginUser(email, password);
        if (user != null) {
          UserService().login(user);

          // 返回上一页，添加mounted检查
          if (mounted) {
            Navigator.pop(context);
          }
        } else {
          // 注册成功但登录失败
          if (mounted) {
            setState(() {
              _errorMessage = '注册成功，但自动登录失败，请手动登录';
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = '注册失败，服务器返回无效ID';
          });
        }
      }
    } catch (e) {
      DiagnosticService().log(
        '注册异常',
        level: LogLevel.error,
        error: e,
        stackTrace: StackTrace.current,
      );
      DiagnosticService().log('异常类型: ${e.runtimeType}', level: LogLevel.debug);

      if (mounted) {
        setState(() {
          // 根据错误类型显示不同的提示信息
          if (e.toString().contains('UNIQUE constraint failed')) {
            _errorMessage = '注册失败，该邮箱已被使用';
          } else if (e.toString().contains('Database not initialized')) {
            _errorMessage = '注册失败，数据库未初始化';
          } else if (e.toString().contains('permission')) {
            _errorMessage = '注册失败，应用权限不足';
          } else {
            _errorMessage = '注册失败，请检查网络或稍后重试';
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        title: const Text('注册', style: TextStyle(color: Colors.black)),
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
              const SizedBox(height: 40),

              // 标题
              const Text(
                '创建账号',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '请输入你的信息',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),

              const SizedBox(height: 48),

              // 邮箱输入
              const Text(
                '邮箱',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: '请输入你的邮箱',
                  hintStyle: TextStyle(
                    color: Colors.black.withAlpha(128), // 0.5 * 255 = 128
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.grey.withAlpha(76), // 0.3 * 255 = 76
                    ),
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
                style: const TextStyle(color: Colors.black),
              ),

              const SizedBox(height: 24),

              // 密码输入
              const Text(
                '密码',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  hintText: '请输入你的密码',
                  hintStyle: TextStyle(
                    color: Colors.black.withAlpha(128), // 0.5 * 255 = 128
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.grey.withAlpha(76), // 0.3 * 255 = 76
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.black.withAlpha(128), // 0.5 * 255 = 128
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                style: const TextStyle(color: Colors.black),
              ),

              const SizedBox(height: 24),

              // 确认密码输入
              const Text(
                '确认密码',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmPasswordController,
                obscureText: !_isConfirmPasswordVisible,
                decoration: InputDecoration(
                  hintText: '请再次输入你的密码',
                  hintStyle: TextStyle(
                    color: Colors.black.withAlpha(128), // 0.5 * 255 = 128
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.grey.withAlpha(76), // 0.3 * 255 = 76
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.black.withAlpha(128), // 0.5 * 255 = 128
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                      });
                    },
                  ),
                ),
                style: const TextStyle(color: Colors.black),
              ),

              const SizedBox(height: 32),

              // 错误信息显示
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),

              // 注册按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
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
                          '注册',
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
}
