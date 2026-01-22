import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart'; // 添加FlutterError和FlutterErrorDetails
import 'package:path_provider/path_provider.dart';

class DiagnosticService {
  static final DiagnosticService _instance = DiagnosticService._private();
  factory DiagnosticService() => _instance;
  DiagnosticService._private();

  final List<DiagnosticLog> _logs = [];
  final StreamController<DiagnosticLog> _logController =
      StreamController.broadcast();
  final Map<String, Stopwatch> _performanceTrackers = {};
  bool _isInitialized = false;
  File? _logFile;

  // 初始化诊断服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    // 配置日志文件
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/diagnostic.log');
      // 清除旧日志（超过1MB）
      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > 1024 * 1024) {
          await _logFile!.writeAsString('');
        }
      }
    } catch (e) {
      _log('日志文件初始化失败: $e', LogLevel.error);
    }

    // 设置全局错误处理
    FlutterError.onError = (details) {
      _handleFlutterError(details);
    };

    // 捕获未处理的异步错误
    runZonedGuarded(
      () {
        // 可以在这里放置应用启动代码
      },
      (error, stackTrace) {
        _handleAsyncError(error, stackTrace);
      },
    );

    _log('诊断服务初始化完成', LogLevel.info);
    _isInitialized = true;
  }

  // 日志记录
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(message, level, error, stackTrace);
  }

  // 性能监控 - 开始跟踪
  void startPerformanceTracking(String name) {
    _performanceTrackers[name] = Stopwatch()..start();
    _log('性能跟踪开始: $name', LogLevel.debug);
  }

  // 性能监控 - 结束跟踪
  void stopPerformanceTracking(String name) {
    final stopwatch = _performanceTrackers.remove(name);
    if (stopwatch != null) {
      stopwatch.stop();
      final time = stopwatch.elapsedMilliseconds;
      _log('性能跟踪结束: $name - ${time}ms', LogLevel.debug);
    }
  }

  // 检查网络连接
  Future<bool> checkNetworkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  // 获取诊断信息
  Future<DiagnosticInfo> getDiagnosticInfo() async {
    return DiagnosticInfo(
      appVersion: '1.0.0',
      flutterVersion: Platform.version.split(' ')[0], // 使用实际运行时的Flutter版本
      dartVersion: Platform.version.split(' ')[0],
      deviceInfo:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion} (${Platform.localeName})',
      hasNetwork: await checkNetworkConnection(),
      logs: List.from(_logs),
      isDebugMode: kDebugMode,
      memoryUsage: _getMemoryUsage(),
      logCount: _logs.length,
      performanceStats: _getPerformanceStats(),
    );
  }

  // 获取内存使用情况（简化版）
  Map<String, dynamic> _getMemoryUsage() {
    return {
      'isWeb': kIsWeb,
      'platform': Platform.operatingSystem,
      // 在实际应用中可以添加更多内存监控信息
    };
  }

  // 获取性能统计信息
  Map<String, dynamic> _getPerformanceStats() {
    final stats = <String, dynamic>{};
    // 可以在这里添加更多性能统计信息
    return stats;
  }

  // 导出诊断日志
  Future<String?> exportLogs() async {
    if (_logFile == null || !await _logFile!.exists()) {
      return null;
    }
    try {
      final bytes = await _logFile!.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      _log('读取日志文件失败: $e', LogLevel.error);
      return 'Could not read log file: $e';
    }
  }

  // 内部日志处理
  void _log(
    String message,
    LogLevel level, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final log = DiagnosticLog(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );

    _logs.add(log);
    if (_logs.length > 1000) {
      _logs.removeAt(0); // 保持日志数量在合理范围
    }

    _logController.add(log);

    // 写入日志文件
    _writeToLogFile(log);

    // 控制台输出（调试模式下）
    if (kDebugMode) {
      print(log.toString());
    }
  }

  // 写入日志文件
  Future<void> _writeToLogFile(DiagnosticLog log) async {
    if (_logFile == null) return;

    try {
      final logString = '${log.toString()}\n';
      await _logFile!.writeAsBytes(
        utf8.encode(logString),
        mode: FileMode.append,
      );
    } catch (e) {
      // 忽略日志写入错误
    }
  }

  // 处理Flutter错误
  void _handleFlutterError(FlutterErrorDetails details) {
    _log(
      'Flutter框架错误: ${details.exceptionAsString()}',
      LogLevel.error,
      details.exception,
      details.stack,
    );
  }

  // 处理异步错误
  void _handleAsyncError(Object error, StackTrace stackTrace) {
    _log('未处理的异步错误: ${error.toString()}', LogLevel.error, error, stackTrace);
  }

  // 关闭诊断服务
  void dispose() {
    _logController.close();
    _performanceTrackers.clear();
  }

  // 获取日志流
  Stream<DiagnosticLog> get logStream => _logController.stream;
}

// 日志级别
enum LogLevel { debug, info, warning, error, critical }

// 诊断日志类
class DiagnosticLog {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? error;
  final String? stackTrace;

  DiagnosticLog({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    String logStr =
        '[${timestamp.toIso8601String()}] [${level.name.toUpperCase()}] $message';
    if (error != null) {
      logStr += '\n  错误: $error';
    }
    if (stackTrace != null) {
      logStr += '\n  堆栈跟踪: $stackTrace';
    }
    return logStr;
  }
}

// 诊断信息类
class DiagnosticInfo {
  final String appVersion;
  final String flutterVersion;
  final String dartVersion;
  final String deviceInfo;
  final bool hasNetwork;
  final List<DiagnosticLog> logs;
  final bool isDebugMode;
  final Map<String, dynamic> memoryUsage;
  final int logCount;
  final Map<String, dynamic> performanceStats;

  DiagnosticInfo({
    required this.appVersion,
    required this.flutterVersion,
    required this.dartVersion,
    required this.deviceInfo,
    required this.hasNetwork,
    required this.logs,
    required this.isDebugMode,
    this.memoryUsage = const {},
    this.logCount = 0,
    this.performanceStats = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'appVersion': appVersion,
      'flutterVersion': flutterVersion,
      'dartVersion': dartVersion,
      'deviceInfo': deviceInfo,
      'hasNetwork': hasNetwork,
      'isDebugMode': isDebugMode,
      'memoryUsage': memoryUsage,
      'logCount': logCount,
      'performanceStats': performanceStats,
      'logs': logs.map((log) => log.toString()).toList(),
    };
  }
}
