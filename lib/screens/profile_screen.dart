import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/user_service.dart';
import '../services/vector_db_service.dart';
import '../services/diagnostic_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _usernameController;
  String _avatarUrl = '';
  File? _avatarFile;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 初始化昵称控制器
    _usernameController = TextEditingController(
      text: _userService.currentUsername,
    );
    // 初始化头像 - 直接从 UserService 获取，而不是每次都查询数据库
    _loadUserAvatar();
  }

  // 加载用户头像 - 优先从 UserService 获取，如果没有则从数据库加载
  Future<void> _loadUserAvatar() async {
    try {
      // 首先尝试从 UserService 获取用户信息
      if (_userService.isLoggedIn && _userService.currentUserId != null) {
        // 如果有本地保存的头像路径，直接使用
        final userId = _userService.currentUserId!;

        // 从数据库获取最新的头像信息
        final user = await VectorDBService.getUser(userId);

        if (user != null) {
          final avatarPath = user['avatar'] as String?;

          if (avatarPath != null && avatarPath.isNotEmpty) {
            final avatarFile = File(avatarPath);

            if (await avatarFile.exists()) {
              setState(() {
                _avatarFile = avatarFile;
                _avatarUrl = '';
              });
              return;
            }
          }
        }

        // 如果没有本地头像，生成默认头像
        final username = _userService.currentUsername ?? '用户';
        setState(() {
          _avatarFile = null;
          _avatarUrl = _getDefaultAvatar(username);
        });
        return;
      }

      // 如果未登录，使用默认头像
      setState(() {
        _avatarFile = null;
        _avatarUrl = _getDefaultAvatar('用户');
      });
    } catch (e) {
      DiagnosticService().log('加载头像失败', level: LogLevel.error, error: e);
      setState(() {
        _avatarFile = null;
        _avatarUrl = _getDefaultAvatar('用户');
      });
    }
  }

  // 根据用户名生成默认头像
  String _getDefaultAvatar(String username) {
    // 这里可以实现更复杂的头像生成逻辑
    return 'https://ui-avatars.com/api/?name=$username&background=random&color=fff';
  }

  // 选择头像
  Future<void> _selectAvatar() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _avatarFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      DiagnosticService().log('选择头像失败', level: LogLevel.error, error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '选择头像失败，请重试',
              style: TextStyle(color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 200, left: 16, right: 16),
            backgroundColor: Colors.grey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            duration: const Duration(seconds: 5),
            elevation: 4,
          ),
        );
      }
    }
  }

  // 保存个人资料
  Future<void> _saveProfile() async {
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

      DiagnosticService().log('开始保存用户资料，用户ID: $userId', level: LogLevel.info);

      // 准备更新数据
      final updateData = <String, dynamic>{};

      // 更新用户名
      final newUsername = _usernameController.text.trim();
      if (newUsername.isNotEmpty &&
          newUsername != _userService.currentUsername) {
        updateData['username'] = newUsername;
        DiagnosticService().log('准备更新用户名: $newUsername', level: LogLevel.info);
      }

      // 更新头像（如果有选择新头像）
      if (_avatarFile != null) {
        // 检查文件是否存在
        if (await _avatarFile!.exists()) {
          // 这里简化处理，实际项目中应该上传到服务器或保存到本地存储
          // 这里只保存文件路径
          updateData['avatar'] = _avatarFile!.path;
          DiagnosticService().log(
            '准备更新头像: ${_avatarFile!.path}',
            level: LogLevel.info,
          );
        } else {
          DiagnosticService().log('头像文件不存在，跳过头像更新', level: LogLevel.warning);
        }
      }

      DiagnosticService().log('更新数据: $updateData', level: LogLevel.info);

      // 如果有数据需要更新
      if (updateData.isNotEmpty) {
        // 确保VectorDBService已初始化
        await VectorDBService.initialize();

        // 使用新的updateUser方法更新数据库中的用户信息
        final result = await VectorDBService.updateUser(userId, updateData);
        DiagnosticService().log('数据库更新结果: $result', level: LogLevel.info);

        // 检查更新是否成功
        if (result > 0) {
          // 更新UserService中的用户信息
          await _userService.updateUser(updateData);
          DiagnosticService().log('已更新UserService中的用户信息', level: LogLevel.info);

          // 显示成功提示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '个人资料更新成功',
                  style: TextStyle(color: Colors.white),
                ),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 200, left: 16, right: 16),
                backgroundColor: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                duration: const Duration(seconds: 5),
                elevation: 4,
              ),
            );

            // 延迟返回，让用户能看到成功提示
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                Navigator.pop(context);
              }
            });
          }
        } else {
          throw Exception('更新失败，未找到用户或数据未更改');
        }

        // 重新加载用户信息，确保显示最新数据
        await _loadUserAvatar();
      } else {
        // 如果没有数据需要更新，显示提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '没有需要更新的信息',
                style: TextStyle(color: Colors.white),
              ),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 200, left: 16, right: 16),
              backgroundColor: Colors.grey,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              duration: const Duration(seconds: 3),
              elevation: 4,
            ),
          );
        }
      }

      // 如果没有数据需要更新，显示提示
      if (updateData.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '没有需要更新的信息',
              style: TextStyle(color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 200, left: 16, right: 16),
            backgroundColor: Colors.grey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            duration: const Duration(seconds: 3),
            elevation: 4,
          ),
        );
      }
    } catch (e) {
      setState(() {
        // 提供更具体的错误信息
        String errorMessage = '保存失败，请重试';
        if (e.toString().contains('read-only')) {
          errorMessage = '数据库权限错误，请重启应用后重试';
        } else if (e.toString().contains('database')) {
          errorMessage = '数据库错误，请重试';
        }
        _errorMessage = errorMessage;
        DiagnosticService().log('保存个人资料失败: $errorMessage', level: LogLevel.error, error: e);
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
        title: const Text('个人资料', style: TextStyle(color: Colors.black)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? const CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 2,
                  )
                : const Text('保存', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 头像
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _avatarFile != null
                          ? FileImage(_avatarFile!)
                          : null,
                      child: _avatarFile == null && _avatarUrl.isNotEmpty
                          ? Image.network(
                              _avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.grey,
                                );
                              },
                            )
                          : (_avatarFile == null && _avatarUrl.isEmpty)
                          ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                          ),
                          onPressed: _selectAvatar,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 昵称编辑
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '昵称',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  hintText: '请输入昵称',
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
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 16),

              // 邮箱显示
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '邮箱',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withAlpha(76)),
                ),
                child: Text(
                  _userService.currentUserEmail ?? '',
                  style: const TextStyle(color: Colors.black),
                ),
              ),
              const SizedBox(height: 16),

              // 错误信息
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }
}
