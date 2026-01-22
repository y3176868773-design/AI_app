import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import '../models/document.dart';

class DocumentViewScreen extends StatelessWidget {
  final Document document;

  const DocumentViewScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: _buildContentPreview(context),
    );
  }

  Widget _buildContentPreview(BuildContext context) {
    switch (document.type) {
      case 'image':
        return _buildImagePreview(context);
      case 'pdf':
        return _buildPdfPreview(context);
      case 'word':
      case 'excel':
        return _buildDocumentInfo(context);
      default:
        return _buildUnsupportedPreview(context);
    }
  }

  Widget _buildImagePreview(BuildContext context) {
    if (document.filePath == null) {
      return _buildUnsupportedPreview(context);
    }
    return Center(
      child: InteractiveViewer(
        panEnabled: true,
        boundaryMargin: const EdgeInsets.all(20),
        minScale: 0.1,
        maxScale: 5.0,
        child: Image.file(
          File(document.filePath!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildUnsupportedPreview(context);
          },
        ),
      ),
    );
  }

  Widget _buildPdfPreview(BuildContext context) {
    if (document.filePath == null) {
      return _buildUnsupportedPreview(context);
    }
    return pdfx.PdfView(
      controller: pdfx.PdfController(
        document: pdfx.PdfDocument.openFile(document.filePath!),
      ),
    );
  }

  Widget _buildDocumentInfo(BuildContext context) {
    // 对于Word和Excel文件，只显示文件信息，不提供预览
    if (document.filePath != null) {
      final file = File(document.filePath!);
      if (file.existsSync()) {
        return _buildFileInfo(context, file);
      }
    }

    // 如果无法显示文件信息，则显示错误信息
    return _buildErrorWidget(context, '无法找到原始文件或文件不存在');
  }

  Widget _buildFileInfo(BuildContext context, File file) {
    final isWord = document.type == 'word';
    final iconColor = isWord ? Colors.blue : Colors.green;
    final fileType = isWord ? 'Word文档' : 'Excel表格';
    final icon = isWord ? Icons.description : Icons.table_chart;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64.0, color: iconColor),
            const SizedBox(height: 16.0),
            Text(
              document.title,
              style: const TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(fileType, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8.0),
            Text(
              '文件大小: ${_getFileSize(file)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16.0),
            const Text(
              '此文件类型不支持预览，但可以用于AI解析',
              style: TextStyle(fontSize: 14.0, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24.0),
            ElevatedButton.icon(
              onPressed: () => _openFileWithOtherApp(context, file),
              icon: const Icon(Icons.open_in_new),
              label: const Text('使用其他应用打开'),
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedPreview(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64.0, color: Colors.red),
          const SizedBox(height: 16.0),
          Text(
            '不支持的文件类型: ${document.type}',
            style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8.0),
          Text('无法直接预览此文件类型', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16.0),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close),
            label: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 获取文件大小的友好显示
  String _getFileSize(File file) {
    final bytes = file.lengthSync();
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  // 使用其他应用打开文件
  Future<void> _openFileWithOtherApp(BuildContext context, File file) async {
    try {
      // 在实际应用中，您可以使用url_launcher或其他插件来打开文件
      // 这里我们只显示一个提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在尝试打开文件: ${file.path}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildErrorWidget(BuildContext context, String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64.0, color: Colors.red),
            const SizedBox(height: 16.0),
            const Text(
              '预览失败',
              style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8.0),
            Text(
              errorMessage,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
