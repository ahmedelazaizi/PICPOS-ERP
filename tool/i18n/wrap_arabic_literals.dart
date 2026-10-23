import 'dart:convert' show utf8;
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

const _arabicPattern = r'[\u0600-\u06FF]';
const _loggerMethods = {
  'print',
  'debugPrint',
  'log',
  'info',
  'warning',
  'warn',
  'error',
  'trace',
  'diagnostic',
};

class CodemodResult {
  const CodemodResult({
    required this.source,
    required this.wrapped,
    required this.skipped,
  });

  final String source;
  final int wrapped;
  final Map<String, int> skipped;
}

class _Edit {
  const _Edit(this.offset, this.end, this.text);

  final int offset;
  final int end;
  final String text;
}

const _nonUiMethods = {
  'codeUnitAt',
  'contains',
  'endsWith',
  'indexOf',
  'replaceAll',
  'replaceAllMapped',
  'replaceFirst',
  'split',
  'startsWith',
};

class _NonUiUnwrapper extends RecursiveAstVisitor<void> {
  _NonUiUnwrapper(this.source, this.path);

  final String source;
  final String path;
  final edits = <_Edit>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'tr' && _shouldUnwrap(node)) {
      final arguments = node.argumentList.arguments;
      final argument = arguments.isEmpty ? null : arguments.first;
      if (argument is SimpleStringLiteral) {
        edits.add(_Edit(node.offset, node.end, source.substring(argument.offset, argument.end)));
      }
    }
    super.visitMethodInvocation(node);
  }

  bool _shouldUnwrap(MethodInvocation node) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('lib/core/utils/') ||
        normalized.startsWith('lib/presentation/widgets/touch_keyboard/')) {
      return true;
    }
    AstNode? current = node.parent;
    while (current != null) {
      if (current is MethodInvocation &&
          _nonUiMethods.contains(current.methodName.name)) {
        return true;
      }
      if (current is InstanceCreationExpression &&
          current.constructorName.type.toSource() == 'RegExp') {
        return true;
      }
      if (current is BinaryExpression &&
          (current.operator.lexeme == '==' || current.operator.lexeme == '!=')) {
        return true;
      }
      if (current is SwitchCase ||
          current is SwitchDefault ||
          current is ConstantPattern ||
          current is EnumConstantDeclaration) {
        return true;
      }
      if (current is MapLiteralEntry && identical(current.key, node)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }
}

class _TextTemplate {
  const _TextTemplate(this.value, this.arguments);

  final String value;
  final Map<String, String> arguments;
}

class _ArabicVisitor extends RecursiveAstVisitor<void> {
  _ArabicVisitor(this.source, this.path);

  final String source;
  final String path;
  final edits = <_Edit>[];
  final constChanges = <int, String>{};
  final skipped = <String, int>{};

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    final parts = _literalParts(node);
    if (parts == null) {
      super.visitAdjacentStrings(node);
      return;
    }
    _visitLiteralGroup(node, parts);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme != '+') {
      super.visitBinaryExpression(node);
      return;
    }
    final parts = _literalParts(node);
    if (parts == null) {
      super.visitBinaryExpression(node);
      return;
    }
    _visitLiteralGroup(node, parts);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _visitString(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    _visitString(node);
  }

  void _visitString(StringLiteral node) {
    if (!_containsArabic(node.stringValue ?? _rawLiteral(node))) {
      return;
    }
    final skipReason = _skipReason(node);
    if (skipReason != null) {
      skipped[skipReason] = (skipped[skipReason] ?? 0) + 1;
      return;
    }

    final replacement = _replacement(node);
    if (replacement == null) {
      skipped['unsupported_literal'] =
          (skipped['unsupported_literal'] ?? 0) + 1;
      return;
    }
    edits.add(_Edit(node.offset, node.end, replacement));
    for (final change in _constKeywordChanges(node)) {
      constChanges[change.offset] = change.replacement;
    }
  }

  List<StringLiteral>? _literalParts(Expression node) {
    if (node is AdjacentStrings) return node.strings;
    if (node is StringLiteral) return [node];
    if (node is! BinaryExpression || node.operator.lexeme != '+') return null;
    final left = _literalParts(node.leftOperand);
    final right = _literalParts(node.rightOperand);
    if (left == null || right == null) return null;
    return [...left, ...right];
  }

  void _visitLiteralGroup(Expression node, List<StringLiteral> parts) {
    final template = _templateFor(parts);
    if (template == null || !_containsArabic(template.value)) return;
    final skipReason = _skipReason(parts.first, allowLiteralGroup: true);
    if (skipReason != null) {
      skipped[skipReason] = (skipped[skipReason] ?? 0) + 1;
      return;
    }
    edits.add(_Edit(node.offset, node.end,
        _trCall(template.value, template.arguments)));
    for (final change in _constKeywordChanges(parts.first)) {
      constChanges[change.offset] = change.replacement;
    }
  }

  _TextTemplate? _templateFor(List<StringLiteral> parts) {
    final template = StringBuffer();
    final arguments = <String, String>{};
    var complexIndex = 0;
    for (final part in parts) {
      if (part is SimpleStringLiteral) {
        final value = part.stringValue;
        if (value == null) return null;
        template.write(value);
        continue;
      }
      if (part is! StringInterpolation) return null;
      for (final element in part.elements) {
        if (element is InterpolationString) {
          template.write(element.value);
          continue;
        }
        final expression = (element as InterpolationExpression).expression;
        var name = expression is SimpleIdentifier
            ? expression.name
            : 'p${complexIndex++}';
        while (arguments.containsKey(name)) {
          name = 'p${complexIndex++}';
        }
        template.write('{$name}');
        arguments[name] = expression is SimpleIdentifier
            ? name
            : expression.toSource();
      }
    }
    return _TextTemplate(template.toString(), arguments);
  }

  String? _replacement(StringLiteral node) {
    final template = _templateFor([node]);
    if (template == null) return null;
    return _trCall(template.value, template.arguments);
  }

  String? _skipReason(
    StringLiteral node, {
    bool allowLiteralGroup = false,
  }) {
    if (_hasI18nIgnoreComment(node)) return 'i18n_ignore';
    if (_hasRegExpAncestor(node)) return 'non_ui_operation';
    if (_isPersistedWriteArgument(node)) return 'persisted_write';

    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('lib/core/utils/') ||
        normalized.startsWith('lib/presentation/widgets/touch_keyboard/')) {
      return 'non_ui_path';
    }
    if (_hasAncestor<Directive>(node)) return 'directive';
    if (_hasAncestor<Annotation>(node)) return 'annotation';
    if (_hasAncestor<DefaultFormalParameter>(node)) {
      return 'default_parameter';
    }
    if (_hasAncestor<SwitchCase>(node) || _hasAncestor<SwitchDefault>(node)) {
      return 'switch_case';
    }
    if (_hasAncestor<ConstantPattern>(node)) return 'pattern';
    if (_hasAncestor<EnumConstantDeclaration>(node)) return 'enum_constant';
    if (!allowLiteralGroup && _hasAncestor<AdjacentStrings>(node)) {
      return 'adjacent_string';
    }
    final value = node.stringValue;
    if (value != null && _isNonUiToken(value)) return 'non_ui_token';
    if (_hasAncestor<StringInterpolation>(node)) {
      return 'nested_interpolation_literal';
    }

    AstNode? current = node.parent;
    while (current != null) {
      if (current is MapLiteralEntry && identical(current.key, node)) {
        return 'map_key';
      }
      if (current is MethodInvocation) {
        final name = current.methodName.name;
        if (name == 'tr') {
          if (_isTrArgumentMapValue(node)) {
            current = current.parent;
            continue;
          }
          return 'already_translated';
        }
        if (_loggerMethods.contains(name)) return 'logger_message';
        if (_nonUiMethods.contains(name)) return 'non_ui_operation';
      }
      if (current is InstanceCreationExpression &&
          current.constructorName.type.toSource() == 'RegExp') {
        return 'non_ui_operation';
      }
      if (current is BinaryExpression &&
          (current.operator.lexeme == '==' || current.operator.lexeme == '!=')) {
        return 'non_ui_operation';
      }
      if (current is ThrowExpression ||
          current is AssertStatement ||
          current is AssertInitializer) {
        return 'exception_message';
      }
      if (current is InstanceCreationExpression) {
        final typeName = current.constructorName.type.toSource();
        if (typeName.endsWith('Exception') || typeName.endsWith('Error')) {
          return 'exception_message';
        }
      }
      current = current.parent;
    }

    if (_looksLikeData(_rawLiteral(node))) return 'data_or_setting_key';
    return null;
  }

  bool _isTrArgumentMapValue(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is MapLiteralEntry) {
        final map = current.parent;
        final arguments = map?.parent;
        final invocation = arguments?.parent;
        return arguments is ArgumentList &&
            invocation is MethodInvocation &&
            invocation.methodName.name == 'tr' &&
            invocation.argumentList.arguments.contains(map);
      }
      if (current is MethodInvocation) return false;
      current = current.parent;
    }
    return false;
  }

  bool _hasAncestor<T extends AstNode>(AstNode node) =>
      _ancestorOf<T>(node) != null;

  bool _hasRegExpAncestor(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is InstanceCreationExpression &&
          current.constructorName.type.toSource() == 'RegExp') {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  bool _hasI18nIgnoreComment(StringLiteral node) {
    final lineStart = source.lastIndexOf('\n', node.offset) + 1;
    final lineEnd = source.indexOf('\n', node.end);
    final currentLine = source.substring(
      lineStart,
      lineEnd < 0 ? source.length : lineEnd,
    );
    if (currentLine.contains('i18n-ignore')) return true;
    if (lineStart == 0) return false;

    final previousLineEnd = lineStart - 1;
    final previousLineStart = source.lastIndexOf('\n', previousLineEnd - 1) + 1;
    return source
        .substring(previousLineStart, previousLineEnd)
        .contains('i18n-ignore');
  }

  bool _isPersistedWriteArgument(StringLiteral node) {
    final named = _ancestorOf<NamedExpression>(node);
    if (named == null) return false;
    final name = named.name.label.name;
    if (name != 'description' && name != 'notes') return false;

    AstNode? current = named.parent;
    while (current != null) {
      if (current is MethodInvocation) {
        final method = current.methodName.name;
        if (method == 'createSafeTransaction' ||
            method == 'createJournalEntry' ||
            method.startsWith('insert')) {
          return true;
        }
      }
      current = current.parent;
    }
    return false;
  }

  T? _ancestorOf<T extends AstNode>(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is T) return current;
      current = current.parent;
    }
    return null;
  }

  List<({int offset, String replacement})> _constKeywordChanges(
    StringLiteral node,
  ) {
    final changes = <({int offset, String replacement})>[];
    AstNode? current = node.parent;
    while (current != null) {
      final isConstContext = current is InstanceCreationExpression ||
          current is ListLiteral ||
          current is SetOrMapLiteral ||
          current is VariableDeclarationList;
      if (isConstContext) {
        final start = (current.offset - 16).clamp(0, source.length);
        final prefix = source.substring(start, current.offset);
        final before = RegExp(r'\bconst\s*$').firstMatch(prefix);
        final direct = RegExp(r'^const\b').firstMatch(source.substring(
            current.offset, (current.offset + 8).clamp(0, source.length)));
        final constOffset = before == null
            ? (direct == null ? null : current.offset + direct.start)
            : start + before.start;
        if (constOffset != null) {
          changes.add((
            offset: constOffset,
            replacement: current is VariableDeclarationList ? 'final' : '',
          ));
        }
      }
      current = current.parent;
    }
    return changes;
  }

  String _rawLiteral(StringLiteral node) =>
      source.substring(node.offset, node.end);
}

bool _containsArabic(String value) => RegExp(_arabicPattern).hasMatch(value);

bool _isNonUiToken(String value) {
  if (value.runes.length <= 1) return true;
  return RegExp(r'^[0-9٠-٩،٫٪؉؊؋؍؎؏ؘؙؚؐؑؒؓؔؕؖؗ؜؛؟\s.,:;!?+\-*/()\[\]{}]+$')
      .hasMatch(value);
}

bool _looksLikeData(String raw) {
  final unquoted = raw.replaceFirst(RegExp(r'''^(['"]{1,3})'''), '');
  if (RegExp(r'^(https?://|[A-Za-z]:[\\/]|[A-Za-z0-9_./-]+)$')
      .hasMatch(unquoted)) {
    return true;
  }
  return RegExp(r'\b(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|FROM|WHERE)\b',
          caseSensitive: false)
      .hasMatch(unquoted);
}

String _trCall(String template, Map<String, String> arguments) {
  final encodedTemplate = _quote(template);
  if (arguments.isEmpty) return "tr('$encodedTemplate')";
  final encodedArgs = arguments.entries
      .map((entry) => "'${entry.key}': ${entry.value}")
      .join(', ');
  return "tr('$encodedTemplate', {$encodedArgs})";
}

String _quote(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll("'", "\\'")
    .replaceAll(r'$', r'\$')
    .replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n');

CodemodResult transformSource(
  String source, {
  String path = 'codemod.dart',
}) {
  final parse = parseString(content: source, path: path);
  final visitor = _ArabicVisitor(source, path);
  parse.unit.accept(visitor);
  final edits = <_Edit>[...visitor.edits];
  for (final change in visitor.constChanges.entries) {
    edits.add(_Edit(change.key, change.key + 5, change.value));
  }
  edits.sort((a, b) => b.offset.compareTo(a.offset));
  var transformed = source;
  for (final edit in edits) {
    transformed = transformed.replaceRange(edit.offset, edit.end, edit.text);
  }
  return CodemodResult(
    source: transformed,
    wrapped: visitor.edits.length,
    skipped: visitor.skipped,
  );
}

String unwrapNonUiSource(String source, {String path = 'codemod.dart'}) {
  final parse = parseString(content: source, path: path);
  final visitor = _NonUiUnwrapper(source, path);
  parse.unit.accept(visitor);
  final edits = [...visitor.edits]
    ..sort((a, b) => b.offset.compareTo(a.offset));
  var transformed = source;
  for (final edit in edits) {
    transformed = transformed.replaceRange(edit.offset, edit.end, edit.text);
  }
  return transformed;
}

class _LocaleGetterVisitor extends RecursiveAstVisitor<void> {
  _LocaleGetterVisitor(this.source);

  final String source;
  final edits = <_Edit>[];

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final list = node.parent;
    if (list is! VariableDeclarationList || !list.isFinal) {
      super.visitVariableDeclaration(node);
      return;
    }
    final declaration = list.parent;
    final isStatic = declaration is FieldDeclaration && declaration.isStatic;
    final isTopLevel = declaration is TopLevelVariableDeclaration;
    final initializer = node.initializer;
    if ((!isStatic && !isTopLevel) || initializer == null ||
        !initializer.toSource().contains('tr(')) {
      super.visitVariableDeclaration(node);
      return;
    }
    final semicolon = source.indexOf(';', initializer.end);
    if (semicolon < 0 || list.variables.length != 1) {
      super.visitVariableDeclaration(node);
      return;
    }
    var prefix = source.substring(list.offset, node.offset);
    prefix = prefix.replaceFirst(RegExp(r'\bstatic\s+'), 'static ');
    prefix = prefix.replaceFirst(RegExp(r'\bfinal\s+'), '');
    prefix = prefix.trimRight();
    final name = node.name.lexeme;
    final value = source.substring(initializer.offset, initializer.end);
    edits.add(_Edit(
      list.offset,
      semicolon + 1,
      '$prefix get $name => $value;',
    ));
    super.visitVariableDeclaration(node);
  }
}

String makeLocaleGetters(String source, {String path = 'codemod.dart'}) {
  final parse = parseString(content: source, path: path);
  final visitor = _LocaleGetterVisitor(source);
  parse.unit.accept(visitor);
  final edits = [...visitor.edits]
    ..sort((a, b) => b.offset.compareTo(a.offset));
  var transformed = source;
  for (final edit in edits) {
    transformed = transformed.replaceRange(edit.offset, edit.end, edit.text);
  }
  return transformed;
}

bool _isPartFile(String source) =>
    RegExp(r'^\s*part of ', multiLine: true).hasMatch(source);

String _addImport(String source) {
  const importLine = "import 'package:picpos_erp/core/i18n/tr.dart';";
  if (source.contains(importLine)) return source;
  final lines = source.split('\n');
  if (_isPartFile(source)) return source;
  var insertion = 0;
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].trimLeft().startsWith('library')) {
      insertion = index + 1;
      break;
    }
  }
  lines.insert(insertion, importLine);
  return lines.join('\n');
}

bool _isEligible(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized == 'lib/app_main_screen.dart') return true;
  if (normalized.startsWith('lib/presentation/') ||
      normalized.startsWith('lib/core/')) {
    if (normalized.startsWith('lib/core/i18n/')) return false;
    if (normalized.contains('/print') ||
        normalized.contains('/pdf') ||
        normalized.contains('/escpos') ||
        normalized.contains('invoice_template')) {
      return false;
    }
    return true;
  }
  return false;
}

String? _partLibraryPath(String path, String source) {
  final match = RegExp(r'''part of ['"]([^'"]+)['"]''').firstMatch(source);
  if (match == null) return null;
  final candidate = p.join(File(path).parent.path, match.group(1)!);
  return p.normalize(candidate);
}

Future<void> _rebuildTrackedFilesFromHead(Directory root) async {
  final result = Process.runSync('git', [
    'diff',
    '--name-only',
    '--diff-filter=M',
    '--',
    'lib/presentation',
    'lib/core',
    'lib/app_main_screen.dart',
  ]);
  if (result.exitCode != 0) {
    throw StateError('git diff failed: ${result.stderr}');
  }
  for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
    final relative = line.trim().replaceAll('\\', '/');
    if (relative.isEmpty || !_isEligible(relative)) continue;
    final head = Process.runSync(
      'git',
      ['show', 'HEAD:$relative'],
      stdoutEncoding: utf8,
    );
    if (head.exitCode != 0) continue;
    final original = head.stdout.toString();
    final isPart = _isPartFile(original);
    final transformed = transformSource(original, path: relative);
    if (transformed.wrapped == 0) continue;
    final output = isPart ? transformed.source : _addImport(transformed.source);
    if (isPart) {
      final libraryPath = _partLibraryPath(
        p.join(root.path, relative),
        original,
      );
      if (libraryPath != null && File(libraryPath).existsSync()) {
        final library = File(libraryPath);
        final librarySource = await library.readAsString();
        if (!librarySource.contains("package:picpos_erp/core/i18n/tr.dart")) {
          await library.writeAsString(_addImport(librarySource));
        }
      }
    }
    await File(p.join(root.path, relative)).writeAsString(output);
  }
}

Future<void> main([List<String> arguments = const []]) async {
  final root = Directory.current;
  if (arguments.contains('--unwrap-non-ui')) {
    var filesChanged = 0;
    await for (final entity in root
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)) {
      final path = entity.path;
      final relative = path.substring(root.path.length + 1).replaceAll('\\', '/');
      if (!_isEligible(relative)) continue;
      final file = File(path);
      final source = await file.readAsString();
      final transformed = unwrapNonUiSource(source, path: relative);
      if (transformed == source) continue;
      await file.writeAsString(transformed);
      filesChanged++;
    }
    stdout.writeln('files_rewritten=$filesChanged');
    return;
  }
  if (arguments.contains('--make-locale-getters')) {
    var filesChanged = 0;
    await for (final entity in root
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)) {
      final path = entity.path;
      final relative = path.substring(root.path.length + 1).replaceAll('\\', '/');
      if (!_isEligible(relative)) continue;
      final file = File(path);
      final source = await file.readAsString();
      final transformed = makeLocaleGetters(source, path: relative);
      if (transformed == source) continue;
      await file.writeAsString(transformed);
      filesChanged++;
    }
    stdout.writeln('files_rewritten=$filesChanged');
    return;
  }
  if (arguments.contains('--rebuild-from-head')) {
    await _rebuildTrackedFilesFromHead(root);
    return;
  }
  var filesChanged = 0;
  var wrapped = 0;
  final skipped = <String, int>{};
  await for (final entity in root
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File)) {
    final path = entity.path;
    final relative = path.substring(root.path.length + 1).replaceAll('\\', '/');
    if (!_isEligible(relative)) continue;
    final file = File(path);
    final source = await file.readAsString();
    final isPart = _isPartFile(source);
    late final CodemodResult result;
    try {
      result = transformSource(source, path: relative);
    } catch (error) {
      throw StateError('Failed to parse $relative: $error');
    }
    for (final entry in result.skipped.entries) {
      skipped[entry.key] = (skipped[entry.key] ?? 0) + entry.value;
    }
    if (result.source == source) continue;
    if (isPart) {
      final libraryPath = _partLibraryPath(path, source);
      if (libraryPath != null && File(libraryPath).existsSync()) {
        final library = File(libraryPath);
        final librarySource = await library.readAsString();
        if (!librarySource.contains("package:picpos_erp/core/i18n/tr.dart")) {
          await library.writeAsString(_addImport(librarySource));
        }
      }
    }
    final output = isPart ? result.source : _addImport(result.source);
    await file.writeAsString(output);
    filesChanged++;
    wrapped += result.wrapped;
  }
  stdout.writeln('files_rewritten=$filesChanged');
  stdout.writeln('literals_wrapped=$wrapped');
  stdout.writeln('skipped=${skipped.entries.map((e) => '${e.key}:${e.value}').join(',')}');
}
