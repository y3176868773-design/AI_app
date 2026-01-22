import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
// import 'diagnostic_service.dart'; // 暂时注释，因为DiagnosticService还未完全修复

class FileService {
  // 通用的文件解析函数，返回原始内容和AI内容
  static Future<Map<String, String>> parseFileWithSeparateContent(
    File file,
  ) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileExt = fileName.split('.').last.toLowerCase();

      String rawContent = '';
      String aiContent = '';

      switch (fileExt) {
        case 'pdf':
          final pdfContent = await parsePdf(file);
          rawContent = pdfContent;
          aiContent = pdfContent;
          break;
        case 'docx':
        case 'doc':
          final wordContent = await parseWord(file);
          // 对于Word文件，rawContent应该是格式化的内容，用于用户预览
          rawContent = _formatWordForPreview(wordContent);
          // aiContent应该是纯文本，用于AI解析
          aiContent = wordContent
              .replaceAll(RegExp(r'#+.+?\n'), '')
              .replaceAll(RegExp(r'\|.*?\|\n'), '')
              .replaceAll(RegExp(r'---+\n'), '')
              .trim();
          break;
        case 'xlsx':
        case 'xls':
          final excelContent = await parseExcel(file);
          rawContent = excelContent; // 原始Markdown格式，用于用户预览
          // 对于Excel文件，保留Markdown表格格式，但移除标题和分隔线，使AI能更好地解析表格内容
          aiContent = _processExcelForAI(excelContent);
          break;
        case 'png':
        case 'jpg':
        case 'jpeg':
        case 'gif':
        case 'webp':
          final imageContent = await parseImage(file);
          rawContent = imageContent;
          aiContent = imageContent;
          break;
        default:
          rawContent = '不支持的文件格式: $fileExt';
          aiContent = '不支持的文件格式: $fileExt';
          break;
      }

      return {'rawContent': rawContent, 'aiContent': aiContent};
    } catch (e) {
      final errorMsg =
          '文件解析错误: $e\n\n文件信息:\n文件名: ${file.path.split(Platform.pathSeparator).last}\n路径: ${file.path}';
      return {'rawContent': errorMsg, 'aiContent': errorMsg};
    }
  }

  // 通用的文件解析函数（兼容旧版本）
  static Future<String> parseFile(File file) async {
    final result = await parseFileWithSeparateContent(file);
    return result['rawContent']!;
  }

  // 解析PDF文件
  static Future<String> parsePdf(File file) async {
    try {
      // 提取PDF基本信息
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = (file.lengthSync() / 1024).toStringAsFixed(2);

      String text = '';
      text += '文件类型: PDF文档\n';
      text += '文件名: $fileName\n';
      text += '大小: $fileSize KB\n\n';
      text += '--- 文件内容 ---\n';

      // 多级PDF处理策略
      String pdfContent = '';
      int pageCount = 0;

      try {
        // 第一级：尝试使用Syncfusion PDF库提取文本
        pdfContent = await _extractTextWithSyncfusion(file);
        pageCount = await _getPageCountWithSyncfusion(file);

        // 如果提取的文本太少，可能是扫描型PDF
        if (pdfContent.length < 100) {
          // 第二级：尝试使用PDF库提取文本
          try {
            pdfContent = await _extractTextWithPdfLibrary(file);
          } catch (e) {
            // 第三级：尝试OCR识别
            try {
              pdfContent = await _extractTextWithOcr(file);
              text += '注意：此PDF可能是扫描型文档，内容通过OCR识别。\n\n';
            } catch (ocrError) {
              // 所有方法都失败
              return _handlePdfParsingFailure(fileName, fileSize, file.path);
            }
          }
        }

        // 结构化处理PDF内容
        final structuredContent = _structurePdfContent(pdfContent, pageCount);
        text += structuredContent;

        // 添加PDF统计信息
        text += '\n\n--- 文档统计 ---\n';
        text += '总页数: $pageCount\n';
        text += '提取字符数: ${pdfContent.length}\n';
      } catch (e) {
        return _handlePdfParsingError(e, fileName, fileSize, file.path);
      }

      return text;
    } catch (e) {
      return 'PDF解析错误: $e\n\n文件信息:\n文件名: ${file.path.split(Platform.pathSeparator).last}\n路径: ${file.path}';
    }
  }

  // 使用Syncfusion PDF库提取文本
  static Future<String> _extractTextWithSyncfusion(File file) async {
    final document = PdfDocument(inputBytes: await file.readAsBytes());
    final buffer = StringBuffer();

    try {
      final maxPagesToExtract = min(document.pages.count, 10); // 增加到10页

      for (int i = 0; i < maxPagesToExtract; i++) {
        final textExtractor = PdfTextExtractor(document);
        final pageText = textExtractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );

        if (pageText.isNotEmpty) {
          buffer.writeln('--- 第 ${i + 1} 页 ---');
          buffer.writeln(pageText);
          buffer.writeln();
        }
      }

      if (document.pages.count > maxPagesToExtract) {
        buffer.writeln(
          '... (省略 ${document.pages.count - maxPagesToExtract} 页)',
        );
      }
    } finally {
      document.dispose();
    }

    return buffer.toString();
  }

  // 使用PDF库提取文本
  static Future<String> _extractTextWithPdfLibrary(File file) async {
    // 这里可以添加使用pdf库的实现
    // 由于pdf库主要用于创建PDF，这里提供一个占位实现
    throw UnimplementedError('PDF库文本提取暂未实现');
  }

  // 使用OCR提取文本
  static Future<String> _extractTextWithOcr(File file) async {
    // 注意：这需要先将PDF转换为图像
    // 这里提供一个简化的OCR实现框架
    throw UnimplementedError('OCR文本提取暂未实现，需要先将PDF转换为图像');
  }

  // 获取PDF页数
  static Future<int> _getPageCountWithSyncfusion(File file) async {
    try {
      final document = PdfDocument(inputBytes: await file.readAsBytes());
      final count = document.pages.count;
      document.dispose();
      return count;
    } catch (e) {
      return 0;
    }
  }

  // 结构化处理PDF内容
  static String _structurePdfContent(String content, int pageCount) {
    if (content.isEmpty) {
      return 'PDF文档内容为空或无法提取文本。\n';
    }

    // 移除多余的空白字符
    String structuredContent = content.replaceAll(RegExp(r'\n\s*\n'), '\n\n');

    // 尝试识别段落和标题
    final lines = structuredContent.split('\n');
    final buffer = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 跳过空行
      if (line.isEmpty) {
        buffer.writeln();
        continue;
      }

      // 简单的标题识别
      if (line.length < 80 &&
          (line == line.toUpperCase() ||
              RegExp(r'^\d+\.\s').hasMatch(line) ||
              RegExp(r'^[一二三四五六七八九十]+[、\.]\s').hasMatch(line))) {
        buffer.writeln('## $line');
      } else {
        buffer.writeln(line);
      }
    }

    return buffer.toString();
  }

  // 处理PDF解析失败的情况
  static String _handlePdfParsingFailure(
    String fileName,
    String fileSize,
    String filePath,
  ) {
    return '文件类型: PDF文档\n'
        '文件名: $fileName\n'
        '大小: $fileSize KB\n\n'
        '--- 解析结果 ---\n'
        'PDF文档无法解析，可能是以下原因：\n\n'
        '1. 扫描型PDF（图像型文档）\n'
        '2. 加密或受密码保护的PDF\n'
        '3. 损坏的PDF文件\n'
        '4. 不支持的PDF版本或格式\n\n'
        '--- 解决建议 ---\n\n'
        '对于扫描型PDF：\n'
        '- 使用具有OCR功能的PDF阅读器\n'
        '- 使用专业OCR软件转换为文本\n'
        '- 尝试使用在线OCR服务\n\n'
        '对于加密PDF：\n'
        '- 使用PDF阅读器打开并解除密码保护\n'
        '- 保存为未加密的PDF文件\n\n'
        '文件路径: $filePath\n';
  }

  // 处理PDF解析错误
  static String _handlePdfParsingError(
    dynamic error,
    String fileName,
    String fileSize,
    String filePath,
  ) {
    return '文件类型: PDF文档\n'
        '文件名: $fileName\n'
        '大小: $fileSize KB\n'
        '解析状态: PDF解析失败\n'
        '失败原因: $error\n\n'
        '--- 解决建议 ---\n\n'
        '1. 检查PDF文件是否完整\n'
        '2. 尝试使用其他PDF阅读器打开\n'
        '3. 尝试将PDF转换为其他格式\n'
        '4. 检查文件是否损坏\n\n'
        '文件路径: $filePath\n';
  }

  // 解析Word文件
  static Future<String> parseWord(File file) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = (file.lengthSync() / 1024).toStringAsFixed(2);

      String text = '';
      text += '文件类型: Word文档\n';
      text += '文件名: $fileName\n';
      text += '大小: $fileSize KB\n\n';
      text += '--- 文件内容 ---\n';

      if (file.path.toLowerCase().endsWith('.docx')) {
        try {
          // 使用archive库手动解析.docx文件（.docx实际上是zip文件）
          final bytes = await file.readAsBytes();
          final archive = ZipDecoder().decodeBytes(bytes);

          // 查找主要的文档内容文件
          final contentFile = archive.files.firstWhere(
            (file) => file.name == 'word/document.xml',
            orElse: () => throw Exception('文档内容文件未找到'),
          );

          final contentXml = utf8.decode(contentFile.content as List<int>);
          // 简单提取文本内容，去除XML标签
          final plainText = contentXml.replaceAll(RegExp(r'<[^>]*>'), '');

          if (plainText.isNotEmpty) {
            // 添加提取的文本内容
            text += plainText;

            // 添加文档统计信息
            final wordCount = plainText
                .split(RegExp(r'\s+'))
                .where((word) => word.isNotEmpty)
                .length;
            final charCount = plainText.length;
            text += '\n\n--- 文档统计 ---\n';
            text += '字数: $wordCount\n';
            text += '字符数: $charCount\n';
          } else {
            text += 'Word文档内容为空。\n';
          }
        } catch (e) {
          text += 'Word文档解析失败: $e\n\n';
          text += '建议：\n';
          text += '1. 将Word文档转换为PDF格式后上传\n';
          text += '2. 或直接复制文档内容粘贴到聊天框\n';
        }
      } else {
        // 对于.doc文件，提供转换建议
        text += '文件格式: Word文档 (.doc)\n\n';
        text += '不支持旧版Word(.doc)格式，请转换为.docx或PDF格式后重试。\n\n';
        text += '转换方法：\n';
        text += '1. 使用Microsoft Word打开文件\n';
        text += '2. 点击"文件" > "另存为"\n';
        text += '3. 选择"Word文档(*.docx)"或"PDF"格式\n';
        text += '4. 保存后重新上传\n';
      }

      return text;
    } catch (e) {
      return 'Word解析错误: $e\n\n文件信息:\n文件名: ${file.path.split(Platform.pathSeparator).last}\n路径: ${file.path}';
    }
  }

  // 解析Excel文件，转为Markdown格式
  static Future<String> parseExcel(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = (file.lengthSync() / 1024).toStringAsFixed(2);

      // 检查是否成功解析Excel文件
      if (excel.tables.isEmpty) {
        return '文件类型: Excel表格\n'
            '文件名: $fileName\n'
            '大小: $fileSize KB\n'
            '工作表数量: 0\n\n'
            '--- 文件内容 ---\n'
            '无法解析Excel文件内容，可能的原因：\n'
            '1. 文件格式不正确或已损坏\n'
            '2. 文件是受密码保护的\n'
            '3. 文件使用了不支持的Excel版本\n'
            '4. 文件中没有工作表\n\n'
            '建议：\n'
            '- 尝试使用Microsoft Excel打开文件并另存为.xlsx格式\n'
            '- 确保文件没有密码保护\n'
            '- 检查文件是否完整';
      }

      String text = '';
      text += '文件类型: Excel表格\n';
      text += '文件名: $fileName\n';
      text += '大小: $fileSize KB\n';
      text += '工作表数量: ${excel.tables.length}\n\n';
      text += '--- 文件内容 ---\n';

      // 智能选择工作表
      final sortedSheets = _sortSheetsByRelevance(excel);

      // 提取Excel内容，转为Markdown格式
      int sheetCount = 0;
      bool hasValidData = false;

      for (var sheetInfo in sortedSheets) {
        if (sheetCount >= 3) break;

        final tableName = sheetInfo['name'] as String;
        final table = excel.tables[tableName]!;

        // 检查工作表是否有数据
        if (table.maxRows <= 1 || table.maxCols <= 0) {
          text += '# 工作表: $tableName\n\n';
          text += '此工作表为空或没有数据。\n\n';
          sheetCount++;
          continue;
        }

        text += '# 工作表: $tableName\n\n';
        hasValidData = true;

        // 添加工作表统计信息
        text += '数据行数: ${table.maxRows - 1}\n';
        text += '数据列数: ${table.maxCols}\n\n';

        // 转为Markdown表格
        // 智能检测表头位置
        final headerRowIndex = _detectHeaderRow(table);

        // 提取表头
        final headers = <String>[];
        final headerRow = table.row(headerRowIndex);
        for (var cell in headerRow) {
          headers.add(cell?.value?.toString() ?? '');
        }

        // 生成Markdown表头
        text += '| ${headers.join(' | ')} |\n';
        text += '| ${headers.map((_) => '---').join(' | ')} |\n';

        // 生成表格内容（增加行数限制）
        final startRow = headerRowIndex + 1;
        final endRow = min(startRow + 20, table.maxRows);

        for (int i = startRow; i < endRow; i++) {
          final row = table.row(i);
          final rowCells = <String>[];
          bool hasData = false;

          for (var cell in row) {
            final cellValue = cell?.value?.toString() ?? '';
            rowCells.add(cellValue);
            if (cellValue.isNotEmpty) hasData = true;
          }

          // 只添加有数据的行
          if (hasData) {
            text += '| ${rowCells.join(' | ')} |\n';
          }
        }

        if (table.maxRows > endRow) {
          text += '\n... (省略 ${table.maxRows - endRow} 行)\n\n';
        } else {
          text += '\n';
        }

        sheetCount++;
      }

      if (excel.tables.length > 3) {
        text += '... (省略 ${excel.tables.length - 3} 个工作表)\n';
      }

      // 添加Excel文件统计信息
      text += '\n--- 文件统计 ---\n';
      text += '总工作表数: ${excel.tables.length}\n';
      text += '已解析工作表数: ${min(excel.tables.length, 3)}\n';

      // 如果没有找到任何有效数据，添加提示
      if (!hasValidData) {
        text += '\n--- 注意 ---\n';
        text += '所有工作表均为空或没有数据。请检查Excel文件是否包含有效数据。\n';
      }

      return text;
    } catch (e) {
      return 'Excel解析错误: $e\n\n文件信息:\n文件名: ${file.path.split(Platform.pathSeparator).last}\n路径: ${file.path}';
    }
  }

  // 智能排序工作表，按相关性排序
  static List<Map<String, dynamic>> _sortSheetsByRelevance(Excel excel) {
    final sheetsInfo = <Map<String, dynamic>>[];

    for (var tableName in excel.tables.keys) {
      final table = excel.tables[tableName]!;

      // 计算工作表的相关性分数
      int score = 0;

      // 有数据的行数越多，分数越高
      score += (table.maxRows - 1) * 10;

      // 有数据的列数越多，分数越高
      score += table.maxCols * 5;

      // 检查第一行是否像表头（包含文本而非数字）
      bool hasTextHeader = false;
      final firstRow = table.row(0);
      for (var cell in firstRow) {
        if (cell?.value != null &&
            cell!.value.toString().isNotEmpty &&
            !RegExp(r'^\d+$').hasMatch(cell.value.toString())) {
          hasTextHeader = true;
          break;
        }
      }

      if (hasTextHeader) score += 50;

      // 工作表名称包含常见关键词，分数更高
      if (RegExp(
        r'(数据|data|明细|详情|列表|list|sheet1)',
        caseSensitive: false,
      ).hasMatch(tableName)) {
        score += 30;
      }

      sheetsInfo.add({
        'name': tableName,
        'score': score,
        'rows': table.maxRows,
        'cols': table.maxCols,
      });
    }

    // 按分数降序排序
    sheetsInfo.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    return sheetsInfo;
  }

  // 智能检测表头行位置
  static int _detectHeaderRow(Sheet table) {
    // 默认假设第一行是表头
    if (table.maxRows <= 1) return 0;

    // 检查前几行，找出最可能是表头的行
    int bestHeaderRow = 0;
    int maxTextColumns = 0;

    for (int i = 0; i < min(3, table.maxRows); i++) {
      final row = table.row(i);
      int textColumns = 0;

      for (var cell in row) {
        if (cell?.value != null &&
            cell!.value.toString().isNotEmpty &&
            !RegExp(r'^\d+(\.\d+)?$').hasMatch(cell.value.toString())) {
          textColumns++;
        }
      }

      if (textColumns > maxTextColumns) {
        maxTextColumns = textColumns;
        bestHeaderRow = i;
      }
    }

    return bestHeaderRow;
  }

  // 解析图片文件
  static Future<String> parseImage(File file) async {
    try {
      // 提取图片基本信息
      return '文件类型: 图片\n'
          '文件名: ${file.path.split(Platform.pathSeparator).last}\n'
          '格式: ${file.path.split('.').last.toLowerCase()}\n'
          '大小: ${(file.lengthSync() / 1024).toStringAsFixed(2)} KB\n\n'
          '--- 文件内容 ---.\n'
          '这是一张图片文件，建议使用AI的图像识别能力进行分析。';
    } catch (e) {
      return '图片信息获取失败: $e';
    }
  }

  // 格式化Word内容，使其适合用户预览
  static String _formatWordForPreview(String wordContent) {
    // 将Word内容转换为更易读的Markdown格式
    final lines = wordContent.split('\n');
    final buffer = StringBuffer();

    // 添加文档标题
    buffer.writeln('# Word文档内容\n');

    bool inDocumentInfo = true;

    for (final line in lines) {
      // 跳过文件信息部分
      if (inDocumentInfo && line.contains('--- 文件内容 ---')) {
        inDocumentInfo = false;
        continue;
      }

      if (inDocumentInfo) {
        continue;
      }

      // 跳过空行
      if (line.trim().isEmpty) {
        buffer.writeln();
        continue;
      }

      // 处理文档统计信息
      if (line.contains('--- 文档统计 ---')) {
        buffer.writeln('\n## 文档统计\n');
        continue;
      }

      // 添加普通内容
      buffer.writeln(line);
    }

    return buffer.toString();
  }

  // 处理Excel内容，使其适合AI解析（公共方法）
  static String processExcelForAI(String excelContent) {
    return _processExcelForAI(excelContent);
  }

  // 格式化Word内容，使其适合用户预览（公共方法）
  static String formatWordForPreview(String wordContent) {
    return _formatWordForPreview(wordContent);
  }

  // 处理Excel内容，使其适合AI解析（私有实现）
  static String _processExcelForAI(String excelContent) {
    // 检查内容是否为空
    if (excelContent.trim().isEmpty) {
      return 'Excel文件内容为空或无法解析。';
    }

    // 将Excel内容转换为更自然的文本描述
    final lines = excelContent.split('\n');
    final buffer = StringBuffer();
    String currentSheet = '';
    List<String> headers = [];
    bool hasData = false;
    int dataRowCount = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 检测工作表标题
      if (line.startsWith('# 工作表:')) {
        // 如果之前有工作表，添加数据统计
        if (currentSheet.isNotEmpty && dataRowCount > 0) {
          buffer.writeln('该工作表共有$dataRowCount行数据。\n');
        }

        currentSheet = line.substring('# 工作表:'.length).trim();
        buffer.writeln('工作表"$currentSheet"包含以下数据：');
        headers.clear();
        dataRowCount = 0;
        continue;
      }

      // 跳过统计信息行
      if (line.contains('数据行数:') ||
          line.contains('数据列数:') ||
          line.contains('总工作表数:') ||
          line.contains('已解析工作表数:') ||
          line.contains('文件类型:') ||
          line.contains('文件名:') ||
          line.contains('大小:') ||
          line.contains('工作表数量:')) {
        continue;
      }

      // 跳过文件内容分隔线
      if (line == '--- 文件内容 ---') {
        continue;
      }

      // 处理表格行
      if (line.startsWith('|') && line.endsWith('|')) {
        // 移除Markdown表格格式，提取单元格内容
        final cells = line
            .split('|')
            .map((cell) => cell.trim())
            .where((cell) => cell.isNotEmpty)
            .toList();

        // 如果是表头行（下一行是分隔线）
        if (i + 1 < lines.length && lines[i + 1].contains('---')) {
          headers = cells;
          if (headers.isNotEmpty) {
            buffer.writeln('表格列标题包括：${headers.join('、')}。');
          }
          i++; // 跳过分隔线行
          hasData = true;
        } else if (headers.isNotEmpty) {
          // 数据行 - 创建自然语言描述
          final rowDescriptions = <String>[];
          for (int j = 0; j < headers.length && j < cells.length; j++) {
            if (cells[j].isNotEmpty) {
              rowDescriptions.add('${headers[j]}是"${cells[j]}"');
            }
          }
          if (rowDescriptions.isNotEmpty) {
            dataRowCount++;
            buffer.writeln('第$dataRowCount行：${rowDescriptions.join('，')}。');
          }
        }
      }
      // 处理省略行
      else if (line.startsWith('... (省略')) {
        buffer.writeln(line);
      }
    }

    // 添加最后一个工作表的统计
    if (currentSheet.isNotEmpty && dataRowCount > 0) {
      buffer.writeln('该工作表共有$dataRowCount行数据。\n');
    }

    // 如果没有找到任何数据，返回提示信息
    if (!hasData) {
      return 'Excel文件中没有找到有效数据。可能是空表格或格式不支持。';
    }

    // 添加总结
    buffer.writeln('\n以上是Excel文件中的所有数据内容。');

    return buffer.toString().trim();
  }

  // 智能处理文档内容，替代简单截断
  static String processDocumentContent(String content, String type) {
    if (content.isEmpty) return '';

    // 根据文档类型选择不同的处理策略
    switch (type.toLowerCase()) {
      case 'pdf':
        return _processPdfContent(content);
      case 'word':
        return _processWordContent(content);
      case 'excel':
        return _processExcelForAI(content);
      case 'image':
        return _processImageContent(content);
      default:
        return _processGenericContent(content);
    }
  }

  // 处理PDF内容
  static String _processPdfContent(String content) {
    // 清洗文本
    String cleanText = content
        .replaceAll(RegExp(r'\s+'), ' ') // 去掉多余空格
        .replaceAll(RegExp(r'[^\x20-\x7E\u4e00-\u9fa5\n]'), '') // 去掉乱码
        .trim();

    // 如果内容较短，直接返回
    if (cleanText.length <= 2000) return cleanText;

    // 尝试按段落分割
    final paragraphs = cleanText.split(RegExp(r'\n\s*\n'));

    // 如果段落数量合理，选择前几个重要段落
    if (paragraphs.length > 1) {
      // 计算每个段落的重要性分数
      final scoredParagraphs = paragraphs.map((p) {
        int score = 0;

        // 段落越长，分数越高
        score += p.length ~/ 10;

        // 包含关键词的段落分数更高
        final keywords = ['总结', '结论', '摘要', '概述', '重要', '关键', '结论', '建议'];
        for (var keyword in keywords) {
          if (p.contains(keyword)) score += 50;
        }

        // 包含数字和数据的段落分数更高
        if (RegExp(r'\d+').hasMatch(p)) score += 20;

        return {'text': p, 'score': score};
      }).toList();

      // 按分数排序
      scoredParagraphs.sort(
        (a, b) => (b['score'] as int).compareTo(a['score'] as int),
      );

      // 选择高分段落，直到总长度接近2000字符
      final buffer = StringBuffer();
      int currentLength = 0;

      for (var item in scoredParagraphs) {
        final paragraph = item['text'] as String;
        if (currentLength + paragraph.length > 2000) break;

        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(paragraph);
        currentLength += paragraph.length;
      }

      return buffer.toString();
    }

    // 如果无法按段落处理，则智能截取
    return _smartTruncate(cleanText, 2000);
  }

  // 处理Word内容
  static String _processWordContent(String content) {
    // 清洗文本
    String cleanText = content
        .replaceAll(RegExp(r'\s+'), ' ') // 去掉多余空格
        .replaceAll(RegExp(r'[^\x20-\x7E\u4e00-\u9fa5\n]'), '') // 去掉乱码
        .trim();

    // 如果内容较短，直接返回
    if (cleanText.length <= 2000) return cleanText;

    // 尝试保留文档结构
    final lines = cleanText.split('\n');
    final buffer = StringBuffer();
    int currentLength = 0;
    bool inImportantSection = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 检查是否是重要部分的开始
      if (RegExp(
        r'^(摘要|概述|引言|结论|总结|建议|重要|关键)',
        caseSensitive: false,
      ).hasMatch(line)) {
        inImportantSection = true;
      }

      // 如果是重要部分或者当前长度还不够，则保留
      if (inImportantSection || currentLength < 1500) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(line);
        currentLength += line.length + 1;

        // 如果超过长度限制，检查是否可以结束
        if (currentLength > 2000) {
          // 尝试在句子结尾截断
          final matches = RegExp(r'[。！？.!?]').allMatches(buffer.toString());
          if (matches.isNotEmpty) {
            final lastSentenceEnd = matches.last;
            return buffer.toString().substring(0, lastSentenceEnd.end);
          }
          break;
        }
      }
    }

    return buffer.toString();
  }

  // 处理图片内容
  static String _processImageContent(String content) {
    // 图片内容主要是元数据，直接返回
    return content;
  }

  // 处理通用内容
  static String _processGenericContent(String content) {
    // 清洗文本
    String cleanText = content
        .replaceAll(RegExp(r'\s+'), ' ') // 去掉多余空格
        .replaceAll(RegExp(r'[^\x20-\x7E\u4e00-\u9fa5\n]'), '') // 去掉乱码
        .trim();

    // 如果内容较短，直接返回
    if (cleanText.length <= 2000) return cleanText;

    // 智能截取
    return _smartTruncate(cleanText, 2000);
  }

  // 智能截取文本，尽量在句子结尾截断
  static String _smartTruncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;

    // 首先尝试在句子结尾截断
    final truncated = text.substring(0, maxLength);
    final matches = RegExp(r'[。！？.!?]').allMatches(truncated);
    final lastSentenceEnd = matches.isNotEmpty ? matches.last : null;

    if (lastSentenceEnd != null && lastSentenceEnd.end > maxLength * 0.7) {
      return truncated.substring(0, lastSentenceEnd.end);
    }

    // 如果没有合适的句子结尾，尝试在段落结尾截断
    final paragraphMatches = RegExp(r'\n\n').allMatches(truncated);
    if (paragraphMatches.isNotEmpty) {
      final lastParagraphEnd = paragraphMatches.last;
      if (lastParagraphEnd.end > maxLength * 0.7) {
        return truncated.substring(0, lastParagraphEnd.end);
      }
    }

    // 最后，在空格处截断
    final lastSpace = truncated.lastIndexOf(' ');

    if (lastSpace > maxLength * 0.7) {
      return truncated.substring(0, lastSpace);
    }

    // 如果都不合适，直接截断
    return truncated;
  }

  // 从图片中提取Base64编码和格式，带图片压缩
  static Future<Map<String, String>> getImageBase64WithFormat(File file) async {
    try {
      final originalImage = img.decodeImage(await file.readAsBytes());
      if (originalImage == null) {
        throw Exception('无法解码图片');
      }

      // 调整图片大小，限制最大尺寸为1024x1024
      final resizedImage = img.copyResize(
        originalImage,
        width: 1024,
        height: 1024,
        maintainAspect: true,
      );

      // 编码为JPEG，质量80%
      final compressedBytes = img.encodeJpg(resizedImage, quality: 80);
      final base64 = base64Encode(compressedBytes);

      return {'base64': base64, 'format': 'jpeg'};
    } catch (e) {
      // 详细记录错误信息
      throw Exception('图片解析错误: $e');
    }
  }

  // 从图片中提取文本信息（用于RAG）
  static Future<String> extractTextFromImage(File file) async {
    return await parseImage(file);
  }

  // 从Word中提取文本内容（用于RAG）
  static Future<String> extractTextFromWord(File file) async {
    return await parseWord(file);
  }

  // 从Excel中提取文本内容（用于RAG）
  static Future<String> extractTextFromExcel(File file) async {
    return await parseExcel(file);
  }

  // 从PDF中提取文本内容（用于RAG）
  static Future<String> extractTextFromPdf(File file) async {
    return await parsePdf(file);
  }

  // 选择文件（支持PDF、Word、Excel）
  static Future<File?> pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: ['pdf', 'docx', 'doc', 'xlsx', 'xls'],
      );
      if (result != null &&
          result.files.isNotEmpty &&
          result.files.first.path != null) {
        return File(result.files.first.path!);
      }
    } catch (e) {
      // 静默处理错误，不影响应用流程
    }
    return null;
  }

  // 选择PDF文件（保留原有方法，兼容旧代码）
  static Future<File?> pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.isNotEmpty) {
        return File(result.files.first.path!);
      }
    } catch (e) {
      // 静默处理错误，不影响应用流程
    }
    return null;
  }

  // 选择图片
  static Future<File?> pickImage() async {
    try {
      final result = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (result != null) {
        return File(result.path);
      }
    } catch (e) {
      // 静默处理错误，不影响应用流程
    }
    return null;
  }

  // 从PDF中提取图片
  static Future<List<File>> extractImagesFromPdf(File file) async {
    final List<File> extractedImages = [];

    try {
      // 使用Syncfusion PDF库打开文件
      final PdfDocument document = PdfDocument(
        inputBytes: await file.readAsBytes(),
      );

      // 遍历每一页
      for (int pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
        // 注意：由于Syncfusion Flutter PDF的限制，我们无法直接提取页面中的独立图片
        // 这里我们使用一个简化的方案，将整个页面作为图片保存
        // 后续可以考虑使用更高级的PDF处理库来提取独立图片

        // 我们将跳过直接提取图片，而是将PDF页面的文本内容提取出来
        // 并将PDF文件本身作为参考

        // 对于完整的图片提取功能，建议使用更专业的PDF处理库
      }

      document.dispose();
      return extractedImages;
    } catch (e) {
      // 详细记录错误信息
      throw Exception('PDF图片提取错误: $e');
    }
  }
}
