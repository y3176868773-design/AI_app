import 'dart:async';
import 'package:flutter/material.dart';
import '../test/diagnostic_test_suite.dart';
import '../services/diagnostic_service.dart';

class DiagnosticRunner extends StatefulWidget {
  const DiagnosticRunner({super.key});

  @override
  State<DiagnosticRunner> createState() => _DiagnosticRunnerState();
}

class _DiagnosticRunnerState extends State<DiagnosticRunner> {
  bool _isRunning = false;
  String _testResults = '';

  final DiagnosticService _diagnosticService = DiagnosticService();
  late StreamSubscription<DiagnosticLog> _logSubscription;

  @override
  void initState() {
    super.initState();
    // 初始化诊断服务
    _diagnosticService.initialize();
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    super.dispose();
  }

  Future<void> _runDiagnostic() async {
    setState(() {
      _isRunning = true;
      _testResults = '正在运行诊断测试...\n';
    });

    // 订阅日志流
    _logSubscription = _diagnosticService.logStream.listen((log) {
      setState(() {
        _testResults +=
            '[${log.timestamp.toLocal().toString().substring(11, 19)}] [${log.level.name.toUpperCase()}] ${log.message}\n';
      });
    });

    try {
      await DiagnosticTestSuite.runFullDiagnostic();

      // 生成详细报告
      final report = await DiagnosticTestSuite.generateDiagnosticReport();
      setState(() {
        _testResults += '\n=== 详细诊断报告 ===\n';
        _testResults += report;
      });
    } catch (e) {
      setState(() {
        _testResults += '\n诊断测试失败: $e\n';
      });
    } finally {
      setState(() {
        _isRunning = false;
      });
      // 取消日志订阅
      _logSubscription.cancel();
    }
  }

  void _clearResults() {
    setState(() {
      _testResults = '';
    });
  }

  Future<void> _saveResults() async {
    if (_testResults.isEmpty) return;

    try {
      // 这里可以实现保存到文件或分享功能
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '诊断结果已保存',
            style: TextStyle(color: Colors.white),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 8, left: 16, right: 16),
          backgroundColor: Colors.grey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          duration: const Duration(seconds: 3),
          elevation: 4,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '保存失败: $e',
            style: TextStyle(color: Colors.white),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 8, left: 16, right: 16),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断测试运行器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearResults,
            tooltip: '清除结果',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveResults,
            tooltip: '保存结果',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _isRunning ? null : _runDiagnostic,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: _isRunning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text('运行诊断测试'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black12,
                  ),
                  child: Text(
                    _testResults.isEmpty ? '点击按钮开始运行诊断测试' : _testResults,
                    style: const TextStyle(fontFamily: 'Courier New'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
