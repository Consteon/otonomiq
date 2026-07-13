// template_printer.dart
// import 'package:esc_pos_utils_plus/esc_pos_utils.dart' as pos_utils;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as pos_utils;
import 'package:expressions/expressions.dart';

/// A helper class to parse and print a template string using esc_pos_utils_plus.
///
/// This class interprets a custom template language to generate ESC/POS commands
/// for thermal printers, allowing for dynamic data, loops, grouping, and calculations.
/// It uses 1-based indexing for all data access in the template for user convenience.
class TemplatePrinter {
  final String template;
  final pos_utils.PaperSize paperSize;
  final Map<String, dynamic> tables;

  late final pos_utils.Generator _generator;
  final Map<String, dynamic> _variables = {};
  final List<String> _lines;

  TemplatePrinter({
    required this.template,
    required this.paperSize,
    this.tables = const {},
  }) : _lines = template.split(';');

  Future<List<int>> getBytes() async {
    final profile = await pos_utils.CapabilityProfile.load();
    _generator = pos_utils.Generator(paperSize, profile);
    _variables.clear();
    final bytes = await _processBlock(0, _lines.length - 1, _createContext());
    return bytes;
  }

  /// Replaces item placeholders like `item[1]` in an expression with their actual numeric values.
  String _replaceItemPlaceholders(
    String expression,
    Map<String, dynamic> context,
  ) {
    final List<dynamic>? itemData = context['item'] as List<dynamic>?;
    if (itemData == null) return expression;

    return expression.replaceAllMapped(RegExp(r'item\[(\d+)\]'), (match) {
      final userIndex = int.tryParse(match.group(1)!) ?? 0;
      // MODIFIED: Per your request, item indices are 0-based.
      if (userIndex < 0) return '0';

      if (userIndex < itemData.length) {
        return itemData[userIndex].toString();
      }
      return '0'; // Index out of bounds
    });
  }

  Future<List<int>> _processBlock(
    int start,
    int end,
    Map<String, dynamic> context,
  ) async {
    List<int> bytes = [];
    int i = start;

    while (i <= end) {
      final line = _lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }

      final commandMatch = RegExp(r'^<(\/?\w+)\s*([^>]*)>').firstMatch(line);
      if (commandMatch != null) {
        final command = commandMatch.group(1)!.toUpperCase();
        final attributes = _parseAttributes(commandMatch.group(2)!);
        final endBlockIndex = _findEndBlock(i, command);

        switch (command) {
          case 'HR':
            bytes += _generator.hr();
            break;
          case 'CUT':
            bytes += _generator.cut();
            break;
          case 'FEED':
            final linesToFeed = int.tryParse(attributes['lines'] ?? '1') ?? 1;
            bytes += _generator.feed(linesToFeed);
            break;
          case 'QRCODE':
            final data = _interpolate(attributes['data'] ?? '', context);
            final align = _getAlign(attributes['align']);
            final size = int.tryParse(attributes['size'] ?? '6') ?? 6;
            final qrSize = _getQrSize(size);
            bytes += _generator.qrcode(data, align: align, size: qrSize);
            break;
          case 'TEXT':
            final singleLineContentMatch = RegExp(
              r'^<TEXT[^>]*>([\s\S]*)<\/TEXT>$',
            ).firstMatch(line);
            if (singleLineContentMatch != null) {
              final content = singleLineContentMatch.group(1)!;
              bytes += _generator.text(
                _interpolate(content, context),
                styles: _getStyles(attributes),
              );
            } else {
              if (endBlockIndex == -1)
                throw Exception('Unclosed <TEXT> tag at line $i');
              final content = _lines.sublist(i + 1, endBlockIndex).join(';');
              bytes += _generator.text(
                _interpolate(content, context).replaceAll(';', '\n'),
                styles: _getStyles(attributes),
              );
              i = endBlockIndex;
            }
            break;
          case 'ROW':
            final singleLineRowMatch = RegExp(
              r'^<ROW[^>]*>([\s\S]*)<\/ROW>$',
            ).firstMatch(line);
            if (singleLineRowMatch != null) {
              final content = singleLineRowMatch.group(1)!;
              bytes += await _processSingleLineRow(content, context);
            } else {
              if (endBlockIndex == -1)
                throw Exception('Unclosed <ROW> tag at line $i');
              bytes += await _processMultiLineRow(
                i + 1,
                endBlockIndex - 1,
                context,
              );
              i = endBlockIndex;
            }
            break;
          case 'GROUP_BY':
            if (endBlockIndex == -1)
              throw Exception('Unclosed <GROUP_BY> tag at line $i');
            bytes += await _processGroupBy(
              i + 1,
              endBlockIndex - 1,
              attributes,
              context,
            );
            i = endBlockIndex;
            break;
          case 'LOOP':
            final singleLineLoopMatch = RegExp(
              r'^<LOOP[^>]*>([\s\S]*)<\/LOOP>$',
            ).firstMatch(line);
            if (singleLineLoopMatch != null) {
              final content = singleLineLoopMatch.group(1)!;
              bytes += await _processSingleLineLoop(
                content,
                attributes,
                context,
              );
            } else {
              if (endBlockIndex == -1)
                throw Exception('Unclosed <LOOP> tag at line $i');
              bytes += await _processMultiLineLoop(
                i + 1,
                endBlockIndex - 1,
                attributes,
                context,
              );
              i = endBlockIndex;
            }
            break;
          case 'ACCUMULATE':
            _processAccumulate(attributes, context);
            break;
          default:
            break;
        }
      } else {
        bytes += _generator.text(_interpolate(line, context));
      }
      i++;
    }
    return bytes;
  }

  Future<List<int>> _processMultiLineRow(
    int start,
    int end,
    Map<String, dynamic> context,
  ) async {
    final List<pos_utils.PosColumn> cols = [];
    int i = start;
    while (i <= end) {
      final line = _lines[i].trim();
      final colMatch = RegExp(
        r'^<COL\s*([^>]*)>([\s\S]*)<\/COL>',
      ).firstMatch(line);
      if (colMatch != null) {
        final attributes = _parseAttributes(colMatch.group(1)!);
        final content = _interpolate(colMatch.group(2)!, context);
        final width = int.tryParse(attributes['width'] ?? '1') ?? 1;
        final styles = _getStyles(
          Map<String, String>.from(attributes)..remove('width'),
        );
        cols.add(
          pos_utils.PosColumn(text: content, width: width, styles: styles),
        );
      }
      i++;
    }
    return _generator.row(cols);
  }

  Future<List<int>> _processSingleLineRow(
    String content,
    Map<String, dynamic> context,
  ) async {
    final List<pos_utils.PosColumn> cols = [];
    final colMatches = RegExp(
      r'<COL\s*([^>]*)>([\s\S]*?)<\/COL>',
    ).allMatches(content);

    for (final colMatch in colMatches) {
      final attributes = _parseAttributes(colMatch.group(1)!);
      final colContent = _interpolate(colMatch.group(2)!, context);
      final width = int.tryParse(attributes['width'] ?? '1') ?? 1;
      final styles = _getStyles(
        Map<String, String>.from(attributes)..remove('width'),
      );
      cols.add(
        pos_utils.PosColumn(text: colContent, width: width, styles: styles),
      );
    }
    return _generator.row(cols);
  }

  Future<List<int>> _processGroupBy(
    int start,
    int end,
    Map<String, String> attributes,
    Map<String, dynamic> context,
  ) async {
    List<int> bytes = [];
    final int colIndex = int.tryParse(attributes['column'] ?? '0') ?? 0;
    if (colIndex < 0) throw Exception('GROUP_BY column must be 0 or greater.');

    final sourceName = attributes['source'];
    if (sourceName == null || sourceName.isEmpty)
      throw Exception('<GROUP_BY> requires a "source" attribute.');

    final dynamic rawSourceData = tables[sourceName];
    if (rawSourceData == null || rawSourceData is! List)
      throw Exception(
        'Source "$sourceName" for GROUP_BY not found or is not a List.',
      );

    final List<List<String>> sourceData = (rawSourceData)
        .map((row) => (row as List).map((cell) => cell.toString()).toList())
        .toList();
    final Map<String, List<List<String>>> groupedData = {};

    for (final row in sourceData) {
      if (row.length > colIndex) {
        final key = row[colIndex];
        (groupedData[key] ??= []).add(row);
      }
    }

    for (final entry in groupedData.entries) {
      final groupContext = Map<String, dynamic>.from(context)
        ..['group'] = {'key': entry.key, 'count': entry.value.length};

      int loopStartIndex = -1, loopEndIndex = -1;
      for (int j = start; j <= end; j++) {
        if (_lines[j].trim().startsWith('<LOOP')) {
          loopStartIndex = j;
          loopEndIndex = _findEndBlock(j, 'LOOP');
          break;
        }
      }

      if (loopStartIndex != -1) {
        bytes += await _processBlock(start, loopStartIndex - 1, groupContext);
        if (loopEndIndex == -1)
          throw Exception(
            'Unclosed <LOOP> tag inside <GROUP_BY> at line $loopStartIndex',
          );
        bytes += await _processMultiLineLoop(
          loopStartIndex + 1,
          loopEndIndex - 1,
          {},
          groupContext,
          items: entry.value,
        );
        bytes += await _processBlock(loopEndIndex + 1, end, groupContext);
      } else {
        bytes += await _processBlock(start, end, groupContext);
      }
    }
    return bytes;
  }

  Future<List<int>> _processSingleLineLoop(
    String content,
    Map<String, String> attributes,
    Map<String, dynamic> context,
  ) async {
    List<int> bytes = [];
    late final List<dynamic> sourceData;
    final sourceName = attributes['source'];

    if (sourceName != null && sourceName.isNotEmpty) {
      final dynamic rawSourceData = tables[sourceName];
      if (rawSourceData == null || rawSourceData is! List) {
        throw Exception(
          'Source "$sourceName" for LOOP not found or is not a List.',
        );
      }
      // ponytail: Map-tolerance for keyed PRN variant. When source elements
      // are Maps (e.g. li[] = [{ii,in,qt,hg,sub},...]), pass them through
      // unchanged so {{item.in}}/{{item.qt}} resolve via _interpolate's
      // Map path-traversal. Positional List elements (GasPink DO) are
      // coerced to List<String> as before -- no regression.
      sourceData = (rawSourceData).map((row) {
        if (row is Map) return row;
        return (row as List).map((cell) => cell.toString()).toList();
      }).toList();
    } else {
      sourceData = [];
    }

    for (final item in sourceData) {
      final itemContext = Map<String, dynamic>.from(context)..['item'] = item;
      final commandMatches = RegExp(
        r'<(\w+)\s*([^>]*?)(?:\/>|>([\s\S]*?)<\/\1>)',
      ).allMatches(content);

      for (final match in commandMatches) {
        final command = match.group(1)!.toUpperCase();
        final attrs = _parseAttributes(match.group(2)!);
        final innerContent = match.group(3);

        switch (command) {
          case 'ACCUMULATE':
            _processAccumulate(attrs, itemContext);
            break;
          case 'ROW':
            if (innerContent != null)
              bytes += await _processSingleLineRow(innerContent, itemContext);
            break;
        }
      }
    }
    return bytes;
  }

  Future<List<int>> _processMultiLineLoop(
    int start,
    int end,
    Map<String, String> attributes,
    Map<String, dynamic> context, {
    List<List<String>>? items,
  }) async {
    List<int> bytes = [];
    late final List<dynamic> sourceData;
    final sourceName = attributes['source'];

    if (items != null) {
      sourceData = items;
    } else if (sourceName != null && sourceName.isNotEmpty) {
      final dynamic rawSourceData = tables[sourceName];
      if (rawSourceData == null || rawSourceData is! List)
        throw Exception(
          'Source "$sourceName" for LOOP not found or is not a List.',
        );
      // ponytail: Map-tolerance for keyed PRN variant (same as single-line).
      sourceData = (rawSourceData).map((row) {
        if (row is Map) return row;
        return (row as List).map((cell) => cell.toString()).toList();
      }).toList();
    } else {
      sourceData = [];
    }

    for (final item in sourceData) {
      final itemContext = Map<String, dynamic>.from(context)..['item'] = item;
      bytes += await _processBlock(start, end, itemContext);
    }
    return bytes;
  }

  void _processAccumulate(
    Map<String, String> attributes,
    Map<String, dynamic> context,
  ) {
    final expression = attributes['expression'];
    final variableName = attributes['into'];
    if (expression == null || variableName == null)
      throw Exception(
        'ACCUMULATE requires "expression" and "into" attributes.',
      );

    String processedExpression = _replaceItemPlaceholders(expression, context);

    double numResult = 0.0;
    try {
      final result = const ExpressionEvaluator().eval(
        Expression.parse(processedExpression),
        {},
      );
      if (result is num) numResult = result.toDouble();
    } catch (e) {
      // ignore
    }

    final currentValue = (_variables[variableName] ?? 0.0);
    _variables[variableName] = currentValue + numResult;
  }

  int _findEndBlock(int startIndex, String command) {
    int level = 1;
    final closeTag = '</$command>';
    for (int i = startIndex + 1; i < _lines.length; i++) {
      final line = _lines[i].trim();
      if (line.startsWith('<$command')) {
        level++;
      } else if (line == closeTag) {
        level--;
        if (level == 0) return i;
      }
    }
    return -1;
  }

  Map<String, dynamic> _createContext() {
    return tables;
  }

  String _formatIdr(String numberString, int decimalDigits) {
    try {
      // final number = double.tryParse(
      //         numberString.replaceAll('.', '').replaceAll(',', '.')) ??
      //     0.0;
      final number = double.tryParse(numberString.replaceAll(',', '')) ?? 0.0;
      final formattedString = number.toStringAsFixed(decimalDigits);
      final parts = formattedString.split('.');
      final integerPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
      return decimalDigits > 0 ? '$integerPart,${parts[1]}' : integerPart;
    } catch (e) {
      return numberString;
    }
  }

  String _formatUsd(String numberString, int decimalDigits) {
    try {
      final number = double.tryParse(numberString.replaceAll(',', '')) ?? 0.0;
      final formattedString = number.toStringAsFixed(decimalDigits);
      final parts = formattedString.split('.');
      final integerPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      return decimalDigits > 0 ? '$integerPart.${parts[1]}' : integerPart;
    } catch (e) {
      return numberString;
    }
  }

  String _interpolate(
    String text,
    Map<String, dynamic> context, {
    bool evaluate = true,
    bool format = true,
  }) {
    return text.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) {
      String valueAsString;
      final String fullKey = match.group(1)!.trim();
      final keyParts = fullKey.split('|').map((p) => p.trim()).toList();
      final String key = keyParts[0];
      final String? formatter = keyParts.length > 1 ? keyParts[1] : null;

      final tableAccessMatch = RegExp(
        r'^(\w+)\s*\[\s*(\d+)\s*\]\s*\[\s*(\d+)\s*\]$',
      ).firstMatch(key);
      if (tableAccessMatch != null) {
        try {
          final tableName = tableAccessMatch.group(1)!;
          final userRowIndex = int.parse(tableAccessMatch.group(2)!);
          final colIndex = int.parse(
            tableAccessMatch.group(3)!,
          ); // Column is 0-based

          final rowIndex = userRowIndex - 1; // Row is 1-based

          final table = context[tableName] as List?;
          if (table != null && rowIndex >= 0 && rowIndex < table.length) {
            final row = table[rowIndex] as List?;
            if (row != null && colIndex >= 0 && colIndex < row.length) {
              valueAsString = row[colIndex]?.toString() ?? '';
            } else {
              valueAsString = '';
            }
          } else {
            valueAsString = '';
          }
        } catch (e) {
          valueAsString = '!ERR!';
        }
      } else if (evaluate &&
          (key.contains('*') ||
              key.contains('/') ||
              key.contains('+') ||
              key.contains('-') // file use '-' todo fix this
              )) {
        String processedExpression = _replaceItemPlaceholders(key, context);
        try {
          final result = const ExpressionEvaluator().eval(
            Expression.parse(processedExpression),
            {},
          );
          valueAsString = (result is num && result % 1 == 0)
              ? result.toInt().toString()
              : result.toString();
        } catch (e) {
          valueAsString = "!ERR!";
        }
      } else if (_variables.containsKey(key)) {
        valueAsString = _variables[key].toString();
      } else {
        var parts = key.split(RegExp(r'[.\[\]]+'))
          ..removeWhere((p) => p.isEmpty);
        dynamic currentValue = context;
        try {
          for (final part in parts) {
            if (currentValue == null) break;
            if (currentValue is Map) {
              currentValue = currentValue[part];
              // currentValue.insert(0, []); // to make index begin with 1
            } else if (currentValue is List) {
              if (part == 'count') {
                currentValue = currentValue.length;
                break;
              }
              // MODIFIED: Per your request, list/item access is 0-based
              final userIndex = int.tryParse(part);
              if (userIndex == null || userIndex < 0) {
                currentValue = null;
                break;
              }
              currentValue = (userIndex < currentValue.length)
                  ? currentValue[userIndex]
                  : null;
            } else {
              currentValue = null;
              break;
            }
          }
          valueAsString = currentValue?.toString() ?? '';
        } catch (e) {
          return match.group(0)!;
        }
      }

      if (format && formatter != null) {
        // FIX-3: {{field|default:SomeText}} substitutes SomeText only when the
        // resolved value is empty (inert on non-empty). Keeps white-label
        // fallback text in the sheet template (e.g. {{by|default:Umum}}) rather
        // than baking it into Dart -- the nota doc `by` field stays "".
        final defaultMatch = RegExp(r'^default:(.*)$').firstMatch(formatter);
        if (defaultMatch != null) {
          return valueAsString.isEmpty ? defaultMatch.group(1)! : valueAsString;
        }
        final idrMatch = RegExp(r'^idr(\d*)$').firstMatch(formatter);
        if (idrMatch != null) {
          return _formatIdr(
            valueAsString,
            idrMatch.group(1)!.isEmpty ? 0 : int.parse(idrMatch.group(1)!),
          );
        }
        final usdMatch = RegExp(r'^usd(\d*)$').firstMatch(formatter);
        if (usdMatch != null) {
          return _formatUsd(
            valueAsString,
            usdMatch.group(1)!.isEmpty ? 2 : int.parse(usdMatch.group(1)!),
          );
        }
      }
      return valueAsString;
    });
  } // end _interpolate

  /// **UPDATED**: Parses an attribute string into a Map, supporting both single and double quotes.
  Map<String, String> _parseAttributes(String attributeString) {
    final Map<String, String> attributes = {};
    // This regex captures key-value pairs. It supports values enclosed in single quotes,
    // double quotes, or no quotes at all, making the template syntax more flexible.
    final matches = RegExp(
      '(\\w+)\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s/>]+))',
    ).allMatches(attributeString);
    for (final match in matches) {
      final key = match.group(1)!;
      // The value is in one of the capture groups, depending on the quoting used.
      final value = match.group(2) ?? match.group(3) ?? match.group(4)!;
      attributes[key] = value;
    }
    return attributes;
  }

  pos_utils.PosAlign _getAlign(String? alignStr) {
    switch (alignStr?.toLowerCase()) {
      case 'center':
        return pos_utils.PosAlign.center;
      case 'right':
        return pos_utils.PosAlign.right;
      default:
        return pos_utils.PosAlign.left;
    }
  }

  pos_utils.QRSize _getQrSize(int size) {
    switch (size) {
      case 1:
        return pos_utils.QRSize.size1;
      case 2:
        return pos_utils.QRSize.size2;
      case 3:
        return pos_utils.QRSize.size3;
      case 4:
        return pos_utils.QRSize.size4;
      case 5:
        return pos_utils.QRSize.size5;
      case 6:
        return pos_utils.QRSize.size6;
      case 7:
        return pos_utils.QRSize.size7;
      case 8:
        return pos_utils.QRSize.size8;
      default:
        return pos_utils.QRSize.size4;
    }
  }

  pos_utils.PosTextSize _getPosTextSize(int size) {
    switch (size) {
      case 1:
        return pos_utils.PosTextSize.size1;
      case 2:
        return pos_utils.PosTextSize.size2;
      case 3:
        return pos_utils.PosTextSize.size3;
      case 4:
        return pos_utils.PosTextSize.size4;
      case 5:
        return pos_utils.PosTextSize.size5;
      case 6:
        return pos_utils.PosTextSize.size6;
      case 7:
        return pos_utils.PosTextSize.size7;
      case 8:
        return pos_utils.PosTextSize.size8;
      default:
        return pos_utils.PosTextSize.size1;
    }
  }

  pos_utils.PosStyles _getStyles(Map<String, String> attributes) {
    return pos_utils.PosStyles(
      align: _getAlign(attributes['align']),
      bold: (attributes['bold'] ?? 'false') == 'true',
      underline: (attributes['underline'] ?? 'false') == 'true',
      height: _getPosTextSize(int.tryParse(attributes['height'] ?? '1') ?? 1),
      width: _getPosTextSize(int.tryParse(attributes['width'] ?? '1') ?? 1),
    );
  }
}
