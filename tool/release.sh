#!/usr/bin/env bash
# Poqi 一键发版：改版本 → 构建 → 算摘要 → 写 version.json → 提交 → 打 tag → 推送 → 发 Release
#
# 用法：
#   ./tool/release.sh 1.1.0 "本次更新说明"
#   ./tool/release.sh 1.1.0 "说明" --push        # 构建完成后直接推送到 GitHub 并创建 Release
#   ./tool/release.sh 1.1.0 "说明" --no-build    # 复用已有 APK，只做清单与发布
#
# 可选环境变量：
#   POQI_OWNER   仓库所有者，默认 losfer
#   POQI_REPO    仓库名，默认 poqi
#
# 依赖：flutter、git、python3、sha256sum（macOS 自带 shasum）；--push 需已登录的 gh
set -euo pipefail

VERSION="${1:-}"
NOTES="${2:-日常更新}"
PUSH=0
BUILD=1
for arg in "${@:3}"; do
  case "$arg" in
    --push) PUSH=1 ;;
    --no-build) BUILD=0 ;;
    *) echo "未知参数：$arg"; exit 1 ;;
  esac
done

REPO_OWNER="${POQI_OWNER:-losfer}"
REPO_NAME="${POQI_REPO:-poqi}"

if [[ -z "$VERSION" ]]; then
  echo "用法: ./tool/release.sh <version> \"<notes>\" [--push] [--no-build]"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ── 读取当前 version: x.y.z+n ────────────────────────────────────────────────
CUR_LINE=$(grep -E '^version:' pubspec.yaml | head -1)
CUR_BUILD=$(sed -E 's/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+).*/\1/' <<<"$CUR_LINE")
[[ "$CUR_BUILD" =~ ^[0-9]+$ ]] || CUR_BUILD=0
NEXT_BUILD=$(( CUR_BUILD + 1 ))

echo "▸ 目标版本 v$VERSION (build $NEXT_BUILD，上一版 build $CUR_BUILD)"

# ── 1. 同步 pubspec 版本号 ───────────────────────────────────────────────────
python3 - "$VERSION" "$NEXT_BUILD" <<'PY'
import re, sys
version, build = sys.argv[1], sys.argv[2]
s = open('pubspec.yaml').read()
s = re.sub(r'^version: .*$', f'version: {version}+{build}', s, flags=re.M)
open('pubspec.yaml', 'w').write(s)
PY

# ── 2. 构建 ──────────────────────────────────────────────────────────────────
APK="build/app/outputs/flutter-apk/app-release.apk"
if [[ $BUILD -eq 1 ]]; then
  echo "▸ 构建 APK（含 arm64 / armv7 / x86_64，单包便于应用内更新）"
  flutter build apk --release --build-name="$VERSION" --build-number="$NEXT_BUILD"
else
  echo "▸ 跳过构建，复用 $APK"
  [[ -f "$APK" ]] || { echo "找不到 $APK"; exit 1; }
fi

OUT="build/poqi-$VERSION.apk"
cp "$APK" "$OUT"

if command -v sha256sum >/dev/null 2>&1; then
  SHA=$(sha256sum "$OUT" | awk '{print $1}')
  SIZE=$(stat -c%s "$OUT")
else
  SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
  SIZE=$(stat -f%z "$OUT")
fi
echo "▸ sha256 $SHA"
echo "▸ 体积   $(awk -v s="$SIZE" 'BEGIN{printf "%.1f MB", s/1048576}')"

# ── 3. 写 version.json（应用内备用更新清单，走 gh-proxy 兜底） ────────────────
python3 - "$VERSION" "$NOTES" "$SHA" "$SIZE" "$REPO_OWNER" "$REPO_NAME" <<'PY'
import json, sys, datetime
version, notes, sha, size, owner, repo = sys.argv[1:7]
data = {
    "version": version,
    "tag": f"v{version}",
    "channel": "stable",
    "notes": notes,
    "publishedAt": datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "htmlUrl": f"https://github.com/{owner}/{repo}/releases/tag/v{version}",
    "assets": [{
        "name": f"poqi-{version}.apk",
        "url": f"https://github.com/{owner}/{repo}/releases/download/v{version}/poqi-{version}.apk",
        "size": int(size),
        "sha256": sha,
    }],
}
open('version.json', 'w').write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print("▸ version.json 已更新")
PY

# ── 4. 提交与打 tag ──────────────────────────────────────────────────────────
git add -A
if git diff --cached --quiet; then
  echo "▸ 无改动，跳过提交"
else
  git commit -m "release: v$VERSION — $NOTES"
fi
git tag -a "v$VERSION" -m "Poqi $VERSION" 2>/dev/null || echo "▸ tag v$VERSION 已存在"

# ── 5. 推送并创建 Release ────────────────────────────────────────────────────
if [[ $PUSH -eq 1 ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "✗ gh 未登录，先执行 gh auth login"; exit 1
  fi
  echo "▸ 推送代码与 tag"
  git push origin HEAD --tags
  echo "▸ 创建 Release"
  gh release create "v$VERSION" "$OUT" \
    --title "Poqi $VERSION" \
    --notes "$NOTES" \
    --latest
  echo "✓ 已发布：https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/v$VERSION"
  exit 0
fi

echo
echo "✓ 本地构建完成：$OUT"
echo "  推送并发布："
echo "    git push origin HEAD --tags"
echo "    gh release create v$VERSION \"$OUT\" -t \"Poqi $VERSION\" -n \"$NOTES\" --latest"
echo "  或直接重跑：./tool/release.sh $VERSION \"$NOTES\" --no-build --push"
