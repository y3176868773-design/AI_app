import 'package:flutter/material.dart';
import 'dart:io';
import '../services/user_service.dart';
import '../services/vector_db_service.dart';
import '../services/diagnostic_service.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import '../main.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  // 用户服务实例
  final UserService _userService = UserService();

  // 历史对话数据
  List<Map<String, dynamic>> _historyConversations = [];
  List<Map<String, dynamic>> _filteredConversations = [];

  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  // 加载状态
  bool _isLoading = false;

  // 头像相关状态
  File? _avatarFile;
  String _avatarUrl = '';
  bool _avatarLoaded = false;

  @override
  void initState() {
    super.initState();
    _filteredConversations = _historyConversations;
    _searchController.addListener(_onSearchChanged);
    _loadUserAvatar();
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 加载用户头像
  Future<void> _loadUserAvatar() async {
    if (!_userService.isLoggedIn) {
      setState(() {
        _avatarFile = null;
        _avatarUrl = '';
        _avatarLoaded = true;
      });
      return;
    }

    try {
      final userId = _userService.currentUserId;
      if (userId != null) {
        // 从数据库获取用户头像
        final user = await VectorDBService.getUser(userId);

        if (user != null) {
          final avatarPath = user['avatar'] as String?;

          if (avatarPath != null && avatarPath.isNotEmpty) {
            final avatarFile = File(avatarPath);

            // 检查文件是否存在
            if (await avatarFile.exists()) {
              setState(() {
                _avatarFile = avatarFile;
                _avatarUrl = '';
                _avatarLoaded = true;
              });
              return;
            }
          }
        }
      }

      // 如果没有头像或文件不存在，使用默认头像
      final username = _userService.currentUsername ?? '用户';
      setState(() {
        _avatarFile = null;
        _avatarUrl = _getDefaultAvatar(username);
        _avatarLoaded = true;
      });
    } catch (e) {
      DiagnosticService().log('加载头像失败', level: LogLevel.error, error: e);
      final username = _userService.currentUsername ?? '用户';
      setState(() {
        _avatarFile = null;
        _avatarUrl = _getDefaultAvatar(username);
        _avatarLoaded = true;
      });
    }
  }

  // 根据用户名生成默认头像URL
  String _getDefaultAvatar(String username) {
    return 'https://ui-avatars.com/api/?name=$username&background=random&color=fff';
  }

  // 加载历史对话
  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_userService.isLoggedIn) {
        final userId = _userService.currentUserId!;
        final conversations = await VectorDBService.getConversations(userId);

        // 格式化对话数据
        final List<Map<String, dynamic>> formattedConversations = [];
        for (var conv in conversations) {
          // 获取消息数量
          final messages = await VectorDBService.getMessages(conv['id'] as int);

          // 格式化日期
          final date = DateTime.fromMillisecondsSinceEpoch(
            conv['updatedAt'] as int,
          );
          final formattedDate =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

          formattedConversations.add({
            'id': conv['id'],
            'title': conv['title'],
            'date': formattedDate,
            'messages': messages.length,
          });
        }

        setState(() {
          _historyConversations = formattedConversations;
          _filteredConversations = formattedConversations;
        });
      } else {
        // 未登录状态，清空对话列表
        setState(() {
          _historyConversations = [];
          _filteredConversations = [];
        });
      }
    } catch (e) {
      // 处理错误
      setState(() {
        _historyConversations = [];
        _filteredConversations = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 搜索功能
  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredConversations = _historyConversations;
      } else {
        _filteredConversations = _historyConversations.where((conversation) {
          return conversation['title'].toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  // 登录功能
  void _login() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    ).then((_) {
      // 登录成功后刷新头像和对话列表
      _loadUserAvatar();
      _loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('个人中心', style: TextStyle(color: Colors.black)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 用户信息区域
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25), // 0.1 * 255 = 25
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // 用户头像
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: _avatarLoaded && _avatarFile != null
                            ? FileImage(_avatarFile!)
                            : null,
                        child: !_avatarLoaded
                            ? const SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : _avatarLoaded &&
                                  _avatarFile == null &&
                                  _avatarUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: Image.network(
                                  _avatarUrl,
                                  fit: BoxFit.cover,
                                  width: 60,
                                  height: 60,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Colors.grey,
                                    );
                                  },
                                ),
                              )
                            : _avatarLoaded &&
                                  _avatarFile == null &&
                                  _avatarUrl.isEmpty
                            ? const Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.grey,
                              )
                            : null,
                      ),

                      const SizedBox(width: 16),

                      // 用户昵称和登录按钮
                      Expanded(
                        child: _userService.isLoggedIn
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userService.currentUsername ?? '用户',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              )
                            : ElevatedButton(
                                onPressed: _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: const Text('登录/注册'),
                              ),
                      ),

                      // 设置按钮
                      if (_userService.isLoggedIn)
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.black),
                          onPressed: () {
                            // 设置页面导航
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 历史对话标题和搜索框
                Row(
                  children: [
                    const Text(
                      '历史对话',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),

                    const Spacer(),

                    // 搜索框
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.withAlpha(25), // 0.1 * 255 = 25
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索历史对话...',
                            hintStyle: TextStyle(
                              color: Colors.black.withAlpha(
                                128,
                              ), // 0.5 * 255 = 128
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.black,
                              size: 18,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 历史对话列表
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(color: Colors.black),
                    ),
                  )
                else if (_filteredConversations.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        _userService.isLoggedIn ? '暂无历史对话' : '请先登录查看历史对话',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _filteredConversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _filteredConversations[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: Colors.white,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            conversation['title'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              children: [
                                Text(
                                  conversation['date'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black.withAlpha(
                                      128,
                                    ), // 0.5 * 255 = 128
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${conversation['messages']}条消息',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black.withAlpha(
                                      128,
                                    ), // 0.5 * 255 = 128
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Colors.black,
                          ),
                          onTap: () {
                            // 先关闭抽屉
                            Navigator.pop(context);
                            // 然后打开历史对话
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => KnowledgeBaseScreen(
                                  initialConversationId: conversation['id'],
                                ),
                              ),
                            );
                          },
                          onLongPress: () {
                            // 显示删除确认对话框
                            showDialog(
                              context: context,
                              barrierDismissible: false, // 防止点击外部关闭对话框
                              builder: (context) => AlertDialog(
                                title: const Text('删除对话'),
                                content: Text(
                                  '确定要删除对话"${conversation['title']}"吗？\n删除后将无法恢复。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      // 保存 context 到局部变量
                                      final dialogContext = context;

                                      // 关闭对话框
                                      Navigator.pop(dialogContext);

                                      // 删除对话
                                      try {
                                        await VectorDBService.deleteConversation(
                                          conversation['id'],
                                        );

                                        // 重新加载对话列表
                                        _loadConversations();

                                        // 显示删除成功提示
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(
                                            dialogContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: const Text('对话已删除'),
                                              backgroundColor: Colors.green,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              margin: const EdgeInsets.only(
                                                bottom: 200,
                                                left: 16,
                                                right: 16,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(20),
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        // 显示删除失败提示
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(
                                            dialogContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('删除对话失败: $e'),
                                              backgroundColor: Colors.red,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              margin: const EdgeInsets.only(
                                                bottom: 200,
                                                left: 16,
                                                right: 16,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(20),
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
