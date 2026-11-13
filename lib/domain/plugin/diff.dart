/// 统一 diff（unified patch）的生成与应用。
///
/// 插件编辑器的"差量修改"能力由它支撑：
/// 生成 `@@ -a,b +c,d @@` 格式的补丁，可复制给 AI/同事，也可反向回滚。
class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldNo, this.newNo});

  /// ' ' 上下文、'-' 删除、'+' 新增
  final String kind;
  final String text;
  final int? oldNo;
  final int? newNo;
}

class DiffHunk {
  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<DiffLine> lines;
}

class PatchStats {
  const PatchStats({required this.added, required this.removed, required this.hunks});

  final int added;
  final int removed;
  final int hunks;

  bool get isEmpty => added == 0 && removed == 0;
}

class UnifiedDiff {
  const UnifiedDiff._();

  /// 生成 unified diff 文本。文本相同时返回空串。
  static String generate(
    String oldText,
    String newText, {
    String oldPath = 'a/plugin.json',
    String newPath = 'b/plugin.json',
    int context = 3,
  }) {
    if (oldText == newText) return '';
    final a = _lines(oldText);
    final b = _lines(newText);
    final ops = _myers(a, b);
    final hunks = _buildHunks(ops, a, b, context);

    final buf = StringBuffer()
      ..writeln('--- $oldPath')
      ..writeln('+++ $newPath');
    for (final h in hunks) {
      buf.writeln('@@ -${h.oldStart},${h.oldCount} +${h.newStart},${h.newCount} @@');
      for (final l in h.lines) {
        buf.writeln('${l.kind}${l.text}');
      }
    }
    return buf.toString();
  }

  static PatchStats stats(String oldText, String newText) {
    final a = _lines(oldText);
    final b = _lines(newText);
    final ops = _myers(a, b);
    var added = 0;
    var removed = 0;
    for (final op in ops) {
      if (op.kind == '+') added++;
      if (op.kind == '-') removed++;
    }
    return PatchStats(added: added, removed: removed, hunks: _buildHunks(ops, a, b, 3).length);
  }

  /// 应用 patch。失败时抛出 [PatchException]（带行号定位）。
  static String apply(String oldText, String patch) {
    final patchLines = _lines(patch);
    final out = <String>[];
    final oldLines = _lines(oldText);

    var p = 0;
    // 跳过文件头
    while (p < patchLines.length && (patchLines[p].startsWith('---') || patchLines[p].startsWith('+++'))) {
      p++;
    }
    var cursor = 0; // 已消费的旧文件行数

    while (p < patchLines.length) {
      final line = patchLines[p];
      if (line.trim().isEmpty) {
        p++;
        continue;
      }
      if (!line.startsWith('@@')) {
        throw PatchException('补丁格式错误：期望 @@ 头，实际 "$line"', p + 1);
      }
      final header = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@').firstMatch(line);
      if (header == null) throw PatchException('无法解析 hunk 头：$line', p + 1);
      final oldStart = int.parse(header.group(1)!);
      final oldCount = int.tryParse(header.group(2) ?? '1') ?? 1;
      p++;

      // hunk 之前的内容原样保留
      final target = (oldStart - 1).clamp(0, oldLines.length);
      if (target < cursor) {
        throw PatchException('hunk 顺序错乱：第 ${oldStart} 行已在之前处理', p);
      }
      while (cursor < target && cursor < oldLines.length) {
        out.add(oldLines[cursor]);
        cursor++;
      }

      var consumed = 0;
      var produced = 0;
      while (p < patchLines.length && !patchLines[p].startsWith('@@')) {
        final raw = patchLines[p];
        final kind = raw.isEmpty ? ' ' : raw[0];
        final text = raw.isEmpty ? '' : raw.substring(1);
        if (kind == ' ') {
          if (cursor >= oldLines.length || oldLines[cursor] != text) {
            throw PatchException(
              '上下文不匹配（旧文件第 ${cursor + 1} 行）：期望 "$text"，实际 '
              '"${cursor < oldLines.length ? oldLines[cursor] : '<EOF>'}"',
              p + 1,
            );
          }
          out.add(text);
          cursor++;
          consumed++;
          produced++;
        } else if (kind == '-') {
          if (cursor >= oldLines.length || oldLines[cursor] != text) {
            throw PatchException(
              '删除行不匹配（旧文件第 ${cursor + 1} 行）：期望 "$text"，实际 '
              '"${cursor < oldLines.length ? oldLines[cursor] : '<EOF>'}"',
              p + 1,
            );
          }
          cursor++;
          consumed++;
        } else if (kind == '+') {
          out.add(text);
          produced++;
        } else if (kind == r'\') {
          // "\ No newline at end of file"
        } else {
          throw PatchException('未知的行前缀 "$kind"', p + 1);
        }
        p++;
      }

      if (consumed != oldCount) {
        throw PatchException('hunk 声明删除/上下文 $oldCount 行，实际 $consumed 行', p);
      }
      if (produced != (int.tryParse(header.group(4) ?? '1') ?? 1)) {
        throw PatchException('hunk 声明新增 $produced 行与头部不一致', p);
      }
    }

    while (cursor < oldLines.length) {
      out.add(oldLines[cursor]);
      cursor++;
    }
    return out.join('\n');
  }

  /// 反向应用（回滚）。同一个变更块内需先删后增，否则无法套用。
  static String reverse(String patch) {
    final src = _lines(patch);
    final out = <String>[];
    var i = 0;
    while (i < src.length) {
      final line = src[i];
      if (line.startsWith('---')) {
        out.add('+++${line.substring(3)}');
        i++;
      } else if (line.startsWith('+++')) {
        out.add('---${line.substring(3)}');
        i++;
      } else if (line.startsWith('@@')) {
        final m = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@').firstMatch(line);
        if (m == null) {
          out.add(line);
          i++;
          continue;
        }
        out.add('@@ -${m.group(3)},${m.group(4) ?? '1'} +${m.group(1)},${m.group(2) ?? '1'} @@');
        i++;
        // 收集 hunk 行
        final block = <String>[];
        while (i < src.length && !src[i].startsWith('@@')) {
          block.add(src[i]);
          i++;
        }
        // 以上下文为界分段，段内先 '-' 后 '+'
        var k = 0;
        while (k < block.length) {
          final b = block[k];
          if (b.startsWith(' ')) {
            out.add(b);
            k++;
            continue;
          }
          final dels = <String>[];
          final adds = <String>[];
          while (k < block.length && !block[k].startsWith(' ')) {
            final cur = block[k];
            if (cur.startsWith('+')) {
              dels.add('-${cur.substring(1)}');
            } else if (cur.startsWith('-')) {
              adds.add('+${cur.substring(1)}');
            } else if (cur.startsWith(r'\')) {
              out.add(cur);
            }
            k++;
          }
          out..addAll(dels)..addAll(adds);
        }
      } else {
        out.add(line);
        i++;
      }
    }
    return out.join('\n');
  }

  static List<String> _lines(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  /// LCS 动态规划：插件体积在数千行内，O(n·m) 足够且实现稳定。
  static List<DiffLine> _myers(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }
    final out = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        out.add(DiffLine(' ', a[i], oldNo: i + 1, newNo: j + 1));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        out.add(DiffLine('-', a[i], oldNo: i + 1));
        i++;
      } else {
        out.add(DiffLine('+', b[j], newNo: j + 1));
        j++;
      }
    }
    while (i < n) {
      out.add(DiffLine('-', a[i], oldNo: i + 1));
      i++;
    }
    while (j < m) {
      out.add(DiffLine('+', b[j], newNo: j + 1));
      j++;
    }
    return out;
  }

  static List<DiffHunk> _buildHunks(
    List<DiffLine> ops,
    List<String> a,
    List<String> b,
    int context,
  ) {
    final changed = <int>[];
    for (var i = 0; i < ops.length; i++) {
      if (ops[i].kind != ' ') changed.add(i);
    }
    if (changed.isEmpty) return const [];

    final ranges = <List<int>>[];
    var start = (changed.first - context).clamp(0, ops.length);
    var end = (changed.first + context).clamp(0, ops.length - 1);
    for (var k = 1; k < changed.length; k++) {
      final s = (changed[k] - context).clamp(0, ops.length);
      if (s <= end + 1) {
        end = (changed[k] + context).clamp(0, ops.length - 1);
      } else {
        ranges.add([start, end]);
        start = s;
        end = (changed[k] + context).clamp(0, ops.length - 1);
      }
    }
    ranges.add([start, end]);

    final hunks = <DiffHunk>[];
    for (final r in ranges) {
      final slice = ops.sublist(r[0], r[1] + 1);
      final oldBefore = ops.take(r[0]).where((l) => l.kind != '+').length;
      final newBefore = ops.take(r[0]).where((l) => l.kind != '-').length;
      var oldStart = 0;
      var newStart = 0;
      var oldCount = 0;
      var newCount = 0;
      for (final l in slice) {
        if (l.kind != '+') {
          if (oldStart == 0 && l.oldNo != null) oldStart = l.oldNo!;
          oldCount++;
        }
        if (l.kind != '-') {
          if (newStart == 0 && l.newNo != null) newStart = l.newNo!;
          newCount++;
        }
      }
      if (oldStart == 0) oldStart = oldBefore;
      if (newStart == 0) newStart = newBefore;
      hunks.add(DiffHunk(
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
        lines: slice,
      ));
    }
    return hunks;
  }
}

class PatchException implements Exception {
  PatchException(this.message, this.line);

  final String message;
  final int line;

  @override
  String toString() => '补丁第 $line 行：$message';
}
