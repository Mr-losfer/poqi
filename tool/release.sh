#!/usr/bin/env bash
# Poqi 发布脚本：构建 → 计算摘要 → 写 version.json → 提交 → 打 tag
#
# 用法： ./tool/release.sh 1.1.0 "更新说明"
#
# 依赖：flutter、git、sha256sum（macOS 用 shasum）
set -euo pipefail

VERSION="${1:-}"
NOTES="${2:-日常更新}"
REPO_OWNER="${POQI_OWNER:-losfer}"
REPO_NAME="${POQI_REPO:-poqi}"

if [[ -z "$VERSION" ]]; then
  echo "用法: ./tool/release.sh <version> \"<notes>\""
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER=$(grep -E '^version: ' pubspec.yaml | sed -E 's/version: [0-9.]+ \+([0-9]+)/\1/')
NEXT_BUILD=$(( ${BUILD_NUMBER:-1} + 1 ))

echo "▸ 版本 v$VERSION (build $NEXT_BUILD)"

# 1. 同步版本号
python3 - "$VERSION" "$NEXT_BUILD" <<'PY'
import re, sys
version, build = sys.argv[1], sys.argv[2]
p = 'pubspec.yaml'
s = open(p).read()
s = re.sub(r'^version: .*$', f'version: {version}+{build}', s, flags=re.M)
open(p, 'w').write(s)
PY

# 2. 构建
echo "▸ 构建 APK"
flutter build apk --release --build-name="$VERSION" --build-number="$NEXT_BUILD"

APK="build/app/outputs/flutter-apk/app-release.apk"
OUT="build/poqi-$VERSION.apk"
cp "$APK" "$OUT"

if command -v sha256sum >/dev/null; then
  SHA=$(sha256sum "$OUT" | awk '{print $1}')
  SIZE=$(stat -c%s "$OUT")
else
  SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
  SIZE=$(stat -f%z "$OUT")
fi
echo "▸ sha256 $SHA"

# 3. 写 version.json（供应用内备用更新清单使用）
python3 - "$VERSION" "$NOTES" "$SHA" "$SIZE" "$REPO_OWNER" "$REPO_NAME" <<'PY'
import json, sys, datetime
version, notes, sha, size, owner, repo = sys.argv[1:7]
data = {
    "version": version,
    "tag": f"v{version}",
    "channel": "stable",
    "notes": notes,
    "publishedAt": datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    "htmlUrl": f"https://github.com/{owner}/{repo}/releases/tag/v{version}",
    "assets": [{
        "name": f"poqi-{version}.apk",
        "url": f"https://github.com/{owner}/{repo}/releases/download/v{version}/poqi-{version}.apk",
        "size": int(size),
        "sha256": sha,
    }],
}
open('version.json', 'w').write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
PY

# 4. 提交与打 tag
git add -A
git commit -m "release: v$VERSION — $NOTES" || echo "（没有需要提交的改动）"
git tag -a "v$VERSION" -m "Poqi $VERSION"

echo
echo "✓ 构建完成：$OUT"
echo "  下一步："
echo "    git push origin HEAD --tags"
echo "    gh release create v$VERSION \"$OUT\" -t \"Poqi $VERSION\" -n \"$NOTES\""
