import 'package:flutter/material.dart';
import '../services/user_service.dart';
import 'profile_screen.dart';
import 'account_management_screen.dart';
import '../main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('设置', style: TextStyle(color: Colors.black)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // 个人资料选项
            ListTile(
              leading: const Icon(Icons.person, color: Colors.black),
              title: const Text(
                '个人资料',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
            ),
            const Divider(),

            // 账号管理选项
            ListTile(
              leading: const Icon(Icons.security, color: Colors.black),
              title: const Text(
                '账号管理',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountManagementScreen(),
                  ),
                );
              },
            ),
            const Divider(),

            // 退出登录选项
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                '退出登录',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
              onTap: () {
                // 显示确认对话框
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认退出登录'),
                    content: const Text('确定要退出登录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () async {
                          // 执行退出登录操作
                          await UserService().logout();
                          // 关闭当前对话框
                          if (context.mounted) {
                            Navigator.pop(context);
                            // 关闭设置页面
                            Navigator.pop(context);
                            // 关闭抽屉（如果打开）
                            Navigator.pop(context);
                            // 显示退出登录成功提示
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  '退出登录成功',
                                  style: TextStyle(color: Colors.white),
                                ),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.only(
                                  bottom: 200,
                                  left: 16,
                                  right: 16,
                                ),
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
                            // 重新导航到主页面
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const KnowledgeBaseScreen(),
                              ),
                            );
                          }
                        },
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
