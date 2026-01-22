import 'package:flutter/material.dart';
import '../services/diagnostic_service.dart';

class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  final DiagnosticService _diagnosticService = DiagnosticService();
  DiagnosticInfo? _diagnosticInfo;
  bool _isLoading = false;
  List<DiagnosticLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadDiagnosticInfo();
    _subscribeToLogs();
  }

  void _loadDiagnosticInfo() async {
    setState(() => _isLoading = true);
    try {
      final info = await _diagnosticService.getDiagnosticInfo();
      setState(() {
        _diagnosticInfo = info;
        _logs = info.logs;
      });
    } catch (e) {
      _diagnosticService.log('加载诊断信息失败: $e', level: LogLevel.error);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToLogs() {
    _diagnosticService.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 100) {
          _logs.removeAt(0);
        }
      });
    });
  }

  void _exportLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _diagnosticService.exportLogs();
      if (mounted) {
        if (logs != null) {
          _showExportDialog(logs);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '没有找到日志文件',
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
    } catch (e) {
      _diagnosticService.log('导出日志失败: $e', level: LogLevel.error);
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '导出失败: $e',
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
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showExportDialog(String logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('诊断日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(child: SelectableText(logs)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Color _getLogLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.blue;
      case LogLevel.info:
        return Colors.green;
      case LogLevel.warning:
        return Colors.yellow[700]!;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.critical:
        return Colors.red[900]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断信息'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDiagnosticInfo,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportLogs,
            tooltip: '导出日志',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 系统信息卡片
                  if (_diagnosticInfo != null)
                    Column(
                      children: [
                        _buildInfoCard(
                          '应用版本',
                          _diagnosticInfo!.appVersion,
                          Icons.apps,
                        ),
                        _buildInfoCard(
                          'Flutter版本',
                          _diagnosticInfo!.flutterVersion,
                          Icons.code,
                        ),
                        _buildInfoCard(
                          'Dart版本',
                          _diagnosticInfo!.dartVersion,
                          Icons.language,
                        ),
                        _buildInfoCard(
                          '设备信息',
                          _diagnosticInfo!.deviceInfo,
                          Icons.device_hub,
                        ),
                        _buildInfoCard(
                          '网络连接',
                          _diagnosticInfo!.hasNetwork ? '已连接' : '未连接',
                          Icons.network_check,
                        ),
                        _buildInfoCard(
                          '调试模式',
                          _diagnosticInfo!.isDebugMode ? '开启' : '关闭',
                          Icons.developer_mode,
                        ),
                      ],
                    ),

                  // 日志信息
                  const SizedBox(height: 24),
                  const Text(
                    '日志记录',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 400,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return ListTile(
                          title: SelectableText(
                            log.message,
                            style: TextStyle(
                              color: _getLogLevelColor(log.level),
                            ),
                          ),
                          subtitle: SelectableText(
                            '${log.timestamp.toString().substring(0, 19)} [${log.level.name.toUpperCase()}]',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          onTap: () {
                            // 显示详细日志
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('详细日志'),
                                content: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('时间: ${log.timestamp}'),
                                      Text('级别: ${log.level.name}'),
                                      Text('消息: ${log.message}'),
                                      if (log.error != null)
                                        Text('错误: ${log.error}'),
                                      if (log.stackTrace != null)
                                        SelectableText(
                                          '堆栈跟踪: ${log.stackTrace}',
                                        ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('关闭'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
