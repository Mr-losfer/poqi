#!/usr/bin/env bash
# Poqi 一键发版：改版本 → 构建 → 算摘要 → 写 version.json → 提交 → 打 tag → 推送 → 发 Release
#
# 目标平台只有两个：Android（APK）与 Windows（zip，整个 Release 目录打包）。
# Windows 包只能在 Windows 宿主机上构建，其他系统会自动跳过并给出提示（不视为失败）。
#
# 用法：
#   ./tool/release.sh 1.1.0 "本次更新说明"                  # 只构建 APK
#   ./tool/release.sh 1.1.0 "说明" --desktop                # APK + Windows zip（Windows 宿主才构建）
#   ./tool/release.sh 1.1.0 "说明" --desktop --push         # 构建后推送并创建 Release
#   ./tool/release.sh 1.1.0 "说明" --no-build               # 复用已有产物，只做清单与发布
#
# 可选环境变量：
#   POQI_OWNER   仓库所有者，默认 Mr-losfer
#   POQI_REPO    仓库名，默认 poqi
#
# 依赖：flutter、git、python3（打包 zip 与写清单）；
#       摘要用 sha256sum（Linux / Git Bash）或 shasum（macOS）；--push 需已登录的 gh
set -euo pipefail

VERSION="${1:-}"
NOTES="${2:-日常更新}"
PUSH=0
BUILD=1
DESKTOP=0
for arg in "${@:3}"; do
  case "$arg" in
    --push)     PUSH=1 ;;
    --desktop)  DESKTOP=1 ;;
    --no-build) BUILD=0 ;;
    *) echo "未知参数：$arg"; exit 1 ;;
  esac
done

REPO_OWNER="${POQI_OWNER:-Mr-losfer}"
REPO_NAME="${POQI_REPO:-poqi}"
TAG="v$VERSION"

if [[ -z "$VERSION" ]]; then
  echo "用法: ./tool/release.sh <version> \"<notes>\" [--desktop] [--push] [--no-build]"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ── 宿主平台检测：Windows 包无法在 Linux / macOS 上交叉编译 ──────────────────
IS_WINDOWS=0
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) IS_WINDOWS=1 ;;
esac
if [[ "${OS:-}" == "Windows_NT" ]]; then IS_WINDOWS=1; fi

# ── 摘要与体积工具函数（GNU / BSD 双兼容） ───────────────────────────────────
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
size_of() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1"
}
human_size() {
  awk -v s="$1" 'BEGIN{printf "%.1f MB", s/1048576}'
}

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

# ── 2. 构建 Android ─────────────────────────────────────────────────────────
APK_SRC="build/app/outputs/flutter-apk/app-release.apk"
OUT_APK="build/poqi-$VERSION.apk"

if [[ $BUILD -eq 1 ]]; then
  echo "▸ 构建 APK（通用包：arm64 / armv7 / x86_64，单包便于应用内更新）"
  flutter build apk --release --build-name="$VERSION" --build-number="$NEXT_BUILD"
else
  echo "▸ 跳过构建，复用 $APK_SRC"
  [[ -f "$APK_SRC" ]] || { echo "✗ 找不到 $APK_SRC"; exit 1; }
fi
cp "$APK_SRC" "$OUT_APK"

# ── 3. 构建 Windows（仅 --desktop 且宿主为 Windows） ─────────────────────────
WIN_DIR="build/windows/x64/runner/Release"
OUT_ZIP="build/poqi-$VERSION-windows-x64.zip"
ZIP_PRESENT=0

if [[ $DESKTOP -eq 1 ]]; then
  if [[ $IS_WINDOWS -eq 0 ]]; then
    echo "▸ 跳过 Windows 包：当前宿主 $(uname -s) 无法构建 Windows 产物"
    echo "  Windows 包需在 Windows runner 或 CI 的 windows job 上构建（推送 tag 即可自动产出）"
  elif [[ $BUILD -eq 1 ]]; then
    echo "▸ 构建 Windows 桌面版"
    flutter build windows --release --build-name="$VERSION" --build-number="$NEXT_BUILD"
  else
    echo "▸ 跳过构建，复用 $WIN_DIR"
  fi

  if [[ -d "$WIN_DIR" ]]; then
    # 整个 Release 目录打包，zip 内保留一层 poqi-<version>-windows-x64/，解压即用
    echo "▸ 打包 Windows 目录 → $OUT_ZIP"
    rm -f "$OUT_ZIP"
    python3 - "$WIN_DIR" "$OUT_ZIP" "poqi-$VERSION-windows-x64" <<'PY'
import os, sys, zipfile
src, out, top = sys.argv[1:4]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for root, _dirs, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            rel = os.path.relpath(p, src).replace(os.sep, '/')
            z.write(p, f'{top}/{rel}')
print(f'  ↳ 已写入 {out}')
PY
    ZIP_PRESENT=1
  elif [[ -f "$OUT_ZIP" ]]; then
    echo "▸ 复用已有 $OUT_ZIP"
    ZIP_PRESENT=1
  else
    echo "▸ 未找到 $WIN_DIR，本次不产出 Windows 包"
  fi
fi

# ── 4. 摘要、体积与校验清单 ──────────────────────────────────────────────────
SHA_APK=$(sha256_of "$OUT_APK")
SIZE_APK=$(size_of "$OUT_APK")
echo "▸ APK    sha256 $SHA_APK"
echo "▸ APK    体积   $(human_size "$SIZE_APK")"

# 只写文件名：与 Release 里资产名一致，用户可直接 sha256sum -c
: > build/SHA256SUMS.txt
printf '%s  %s\n' "$SHA_APK" "$(basename "$OUT_APK")" >> build/SHA256SUMS.txt

if [[ $ZIP_PRESENT -eq 1 ]]; then
  SHA_ZIP=$(sha256_of "$OUT_ZIP")
  SIZE_ZIP=$(size_of "$OUT_ZIP")
  echo "▸ WIN    sha256 $SHA_ZIP"
  echo "▸ WIN    体积   $(human_size "$SIZE_ZIP")"
  printf '%s  %s\n' "$SHA_ZIP" "$(basename "$OUT_ZIP")" >> build/SHA256SUMS.txt
fi
echo "▸ 校验清单 build/SHA256SUMS.txt"

# ── 5. 写 version.json（应用内备用更新清单，走 gh-proxy 兜底） ────────────────
# assets 按实际产物生成：apk 恒有；Windows zip 视是否构建而定，各自带 size / sha256。
ASSET_FILES="$OUT_APK"
if [[ $ZIP_PRESENT -eq 1 ]]; then
  ASSET_FILES="$ASSET_FILES
$OUT_ZIP"
fi

python3 - "$VERSION" "$NOTES" "$REPO_OWNER" "$REPO_NAME" "$ASSET_FILES" <<'PY'
import datetime, hashlib, json, os, sys
version, notes, owner, repo, files = sys.argv[1:6]
assets = []
for path in [p.strip() for p in files.splitlines() if p.strip()]:
    name = os.path.basename(path)
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    assets.append({
        "name": name,
        "url": f"https://github.com/{owner}/{repo}/releases/download/v{version}/{name}",
        "size": os.path.getsize(path),
        "sha256": h.hexdigest(),
    })
data = {
    "version": version,
    "tag": f"v{version}",
    "channel": "stable",
    "notes": notes,
    "publishedAt": datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "htmlUrl": f"https://github.com/{owner}/{repo}/releases/tag/v{version}",
    "assets": assets,
}
open('version.json', 'w').write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(f"▸ version.json 已更新（{len(assets)} 个资产）")
PY

# ── 6. 提交与打 tag ──────────────────────────────────────────────────────────
git add -A
if git diff --cached --quiet; then
  echo "▸ 无改动，跳过提交"
else
  git commit -m "release: v$VERSION — $NOTES"
fi
git tag -a "$TAG" -m "Poqi $VERSION" 2>/dev/null || echo "▸ tag $TAG 已存在"

# ── 7. 推送并创建 Release ────────────────────────────────────────────────────
RELEASE_FILES=("$OUT_APK" "build/SHA256SUMS.txt" "version.json")
if [[ $ZIP_PRESENT -eq 1 ]]; then
  RELEASE_FILES+=("$OUT_ZIP")
fi

if [[ $PUSH -eq 1 ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "✗ gh 未登录，先执行 gh auth login"; exit 1
  fi
  echo "▸ 推送代码与 tag"
  git push origin HEAD --tags
  echo "▸ 创建 Release（${#RELEASE_FILES[@]} 个文件）"
  gh release create "$TAG" "${RELEASE_FILES[@]}" \
    --title "Poqi $VERSION" \
    --notes "$NOTES" \
    --latest
  echo "✓ 已发布：https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$TAG"
  exit 0
fi

echo
echo "✓ 本地构建完成："
for f in "${RELEASE_FILES[@]}"; do echo "    $f"; done
echo "  推送并发布："
echo "    git push origin HEAD --tags"
echo "    gh release create $TAG ${RELEASE_FILES[*]} -t \"Poqi $VERSION\" -n \"$NOTES\" --latest"
echo "  或直接重跑：./tool/release.sh $VERSION \"$NOTES\" --no-build --push"
if [[ $DESKTOP -eq 1 && $ZIP_PRESENT -eq 0 ]]; then
  echo "  注意：Windows 包未生成，需在 Windows 上重跑 --desktop，或推送 tag 交给 CI 构建"
fi
