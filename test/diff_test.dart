import 'package:flutter_test/flutter_test.dart';
import 'package:poqi/domain/plugin/diff.dart';

void main() {
  const before = '''{
  "name": "棱镜",
  "version": "1.0.0",
  "endpoints": {
    "home": { "path": "/home" }
  }
}''';

  const after = '''{
  "name": "棱镜 · 演示源",
  "version": "1.1.0",
  "endpoints": {
    "home": { "path": "/home" },
    "search": { "path": "/search" }
  }
}''';

  test('生成 unified diff 并能原样应用', () {
    final patch = UnifiedDiff.generate(before, after);
    expect(patch, contains('--- a/plugin.json'));
    expect(patch, contains('+++ b/plugin.json'));
    expect(patch, contains('@@'));
    expect(patch, contains('+    "search": { "path": "/search" }'));

    final result = UnifiedDiff.apply(before, patch);
    expect(result, after);
  });

  test('文本相同时不产生补丁', () {
    expect(UnifiedDiff.generate(before, before), isEmpty);
    expect(UnifiedDiff.stats(before, before).isEmpty, isTrue);
  });

  test('统计新增与删除行数', () {
    final stats = UnifiedDiff.stats(before, after);
    expect(stats.added, greaterThan(0));
    expect(stats.removed, greaterThan(0));
    expect(stats.hunks, 1);
  });

  test('反向补丁可回滚', () {
    final patch = UnifiedDiff.generate(before, after);
    final rolled = UnifiedDiff.apply(after, UnifiedDiff.reverse(patch));
    expect(rolled, before);
  });

  test('上下文不匹配时抛出带行号的异常', () {
    final patch = UnifiedDiff.generate(before, after);
    final tampered = before.replaceFirst('棱镜', '其他');
    expect(
      () => UnifiedDiff.apply(tampered, patch),
      throwsA(isA<PatchException>()),
    );
  });

  test('补丁格式错误会被拒绝', () {
    expect(
      () => UnifiedDiff.apply(before, 'not a patch'),
      throwsA(isA<PatchException>()),
    );
  });
}
