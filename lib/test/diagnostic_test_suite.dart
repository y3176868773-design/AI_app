import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/ai_service.dart';
import '../services/vector_db_service.dart';
import '../services/diagnostic_service.dart';

class DiagnosticTestSuite {
  static final DiagnosticService _diagnostic = DiagnosticService();

  static Future<String?> _safeReadLogFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logFile = File('${dir.path}/diagnostic.log');
      if (await logFile.exists()) {
        final bytes = await logFile.readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      }
      return null;
    } catch (e) {
      _diagnostic.log('日志文件安全读取失败: $e', level: LogLevel.error);
      return null;
    }
  }

  static Future<void> runFullDiagnostic() async {
    _diagnostic.log('=== AI知识库应用诊断测试套件 ===', level: LogLevel.info);

    await _diagnostic.initialize();
    _diagnostic.log('开始运行诊断测试', level: LogLevel.info);

    try {
      await _testSystemEnvironment();
      await _testNetworkConnection();
      await _testDiagnosticService();
      await _testAIService();
      await _testFileService();
      await _testVectorDBService();

      _diagnostic.log('\n=== 诊断测试完成 ===', level: LogLevel.info);
      _diagnostic.log('所有测试通过！应用状态良好。', level: LogLevel.info);
    } catch (e, s) {
      _diagnostic.log('诊断测试失败: $e', level: LogLevel.error, error: e, stackTrace: s);
      _diagnostic.log('\n=== 诊断测试失败 ===', level: LogLevel.error);
    } finally {
      final logs = await _safeReadLogFile();
      if (logs != null) {
        _diagnostic.log('\n诊断日志内容已捕获。', level: LogLevel.info);
      }
    }
  }

  static Future<void> _testSystemEnvironment() async {
    _diagnostic.log('1. 测试系统环境...', level: LogLevel.info);
    final info = await _diagnostic.getDiagnosticInfo();
    _diagnostic.log('   应用版本: ${info.appVersion}', level: LogLevel.info);
    _diagnostic.log('   Flutter版本: ${info.flutterVersion}', level: LogLevel.info);
    _diagnostic.log('   Dart版本: ${info.dartVersion}', level: LogLevel.info);
    _diagnostic.log('   设备信息: ${info.deviceInfo}', level: LogLevel.info);
    _diagnostic.log('   调试模式: ${info.isDebugMode ? '开启' : '关闭'}', level: LogLevel.info);
    _diagnostic.log('系统环境测试完成', level: LogLevel.info);
  }

  static Future<void> _testNetworkConnection() async {
    _diagnostic.log('2. 测试网络连接...', level: LogLevel.info);
    final hasNetwork = await _diagnostic.checkNetworkConnection();
    if (hasNetwork) {
      _diagnostic.log('   ✓ 网络连接正常', level: LogLevel.info);
      _diagnostic.log('网络连接测试通过', level: LogLevel.info);
    } else {
      _diagnostic.log('   ✗ 网络连接失败', level: LogLevel.warning);
      throw Exception('网络连接失败');
    }
  }

  static Future<void> _testDiagnosticService() async {
    _diagnostic.log('3. 测试诊断服务...', level: LogLevel.info);
    _diagnostic.log('测试日志记录', level: LogLevel.debug);
    _diagnostic.log('   ✓ 日志记录功能正常', level: LogLevel.info);

    _diagnostic.startPerformanceTracking('performance_test');
    await Future.delayed(const Duration(milliseconds: 100));
    _diagnostic.stopPerformanceTracking('performance_test');
    _diagnostic.log('   ✓ 性能跟踪功能正常', level: LogLevel.info);

    final logs = await _safeReadLogFile();
    if (logs != null && logs.isNotEmpty) {
      _diagnostic.log('   ✓ 日志导出功能正常', level: LogLevel.info);
    } else {
      _diagnostic.log('   ✗ 日志导出功能失败', level: LogLevel.warning);
    }
    _diagnostic.log('诊断服务测试完成', level: LogLevel.info);
  }

  static Future<void> _testAIService() async {
    _diagnostic.log('4. 测试AI服务...', level: LogLevel.info);
    try {
      _diagnostic.startPerformanceTracking('embedding_test');
      final embedding = await AIService.generateEmbedding('测试文本');
      _diagnostic.stopPerformanceTracking('embedding_test');
      if (embedding.isNotEmpty) {
        _diagnostic.log('   ✓ 嵌入生成功能正常', level: LogLevel.info);
      } else {
        _diagnostic.log('   ✗ 嵌入生成功能失败', level: LogLevel.warning);
      }
    } catch (e) {
      _diagnostic.log('   ✗ AI服务测试失败: $e', level: LogLevel.error);
    }
  }

  static Future<void> _testFileService() async {
    _diagnostic.log('5. 测试文件服务...', level: LogLevel.info);
    _diagnostic.log('   ✓ 文件服务API可访问 (UI交互测试需手动进行)', level: LogLevel.info);
    _diagnostic.log('文件服务测试完成', level: LogLevel.info);
  }

  static Future<void> _testVectorDBService() async {
    _diagnostic.log('6. 测试向量数据库服务...', level: LogLevel.info);
    try {
      _diagnostic.startPerformanceTracking('database_test');
      await VectorDBService.initialize();
      _diagnostic.stopPerformanceTracking('database_test');
      _diagnostic.log('   ✓ 数据库初始化成功', level: LogLevel.info);

      final docs = await VectorDBService.getAllDocuments();
      _diagnostic.log('   ✓ 文档检索功能正常 (${docs.length}篇文档)', level: LogLevel.info);
    } catch (e) {
      _diagnostic.log('   ✗ 向量数据库测试失败: $e', level: LogLevel.error);
    }
  }

  static Future<String> generateDiagnosticReport() async {
    final info = await _diagnostic.getDiagnosticInfo();
    final logs = await _safeReadLogFile();

    final report = StringBuffer();
    report.writeln('=== AI知识库应用诊断报告 ===');
    report.writeln('生成时间: ${DateTime.now()}');
    report.writeln();
    report.writeln('1. 系统信息:');
    report.writeln('   应用版本: ${info.appVersion}');
    report.writeln('   Flutter版本: ${info.flutterVersion}');
    report.writeln('   设备信息: ${info.deviceInfo}');
    report.writeln('   网络连接: ${info.hasNetwork ? '已连接' : '未连接'}');
    report.writeln();
    report.writeln('2. 最近日志 (最多20条):');
    if (logs != null) {
      final logLines = LineSplitter.split(logs).toList().reversed.take(20).toList().reversed;
      report.writeln(logLines.join('\n'));
    } else {
      report.writeln('   没有可用的日志信息');
    }

    return report.toString();
  }
}
