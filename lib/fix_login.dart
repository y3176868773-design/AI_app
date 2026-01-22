import '../services/vector_db_service.dart';

// 修复123456@qq.com账号登录问题的工具函数
Future<void> fix123456QQComLogin() async {
  try {
    // 确保数据库已初始化
    await VectorDBService.initialize();

    // 检查123456@qq.com账号是否存在
    final users = await VectorDBService.database.query(
      'users',
      where: 'email = ?',
      whereArgs: ['123456@qq.com'],
    );

    if (users.isEmpty) {
      // 如果账号不存在，创建一个
      await VectorDBService.registerUser(
        '123456@qq.com',
        '123456', // 默认密码
      );
    }
  } catch (e) {
    // 静默处理错误，不影响应用启动
  }
}
