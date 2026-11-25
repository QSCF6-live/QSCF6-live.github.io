#!/usr/bin/env bash
# 一键发布：新版本资产上传 GitHub Release + 页面版本号更新 + 推送 Pages + 线上验证
# 用法:
#   ./release.sh 1.0.1 --dmg ../../release/BOSS智能筛选-1.0.1-arm64.dmg \
#                      --zip ../../release/BOSS智能筛选-1.0.1-arm64-mac.zip \
#                      [--exe ../../release/BOSS智能筛选-1.0.1-win64.exe]
# 全部参数可选：只改版本号不发资产也可以。PAT 从 ~/.dsh/github.json 读取。
set -euo pipefail

VER=""
DMG=""; ZIP=""; EXE=""; SUFFIX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg) DMG="$2"; shift 2;;
    --zip) ZIP="$2"; shift 2;;
    --exe) EXE="$2"; shift 2;;
    --suffix) SUFFIX="$2"; shift 2;;
    *) if [[ -z "$VER" ]]; then VER="$1"; shift; else echo "未知参数: $1" >&2; exit 1; fi;;
  esac
done

if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法: $0 <版本号 X.Y.Z> [--dmg 文件] [--zip 文件] [--exe 文件] [--suffix '版本后缀文字']"; exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
PAGE="$DIR/index.html"
TOKEN="$(python3 -c "import json;print(json.load(open('$HOME/.dsh/github.json'))['token'])")"
API="https://api.github.com/repos/QSCF6-live/QSCF6-live.github.io"
UP="https://uploads.github.com/repos/QSCF6-live/QSCF6-live.github.io/releases"
TAG="v$VER"
TODAY="$(date +%Y-%m-%d)"

mb() { python3 -c "import sys;print(f'{int(sys.argv[1])/1048576:.0f} MB')" "$1"; }

# ---------- 1. 安全新检：公开资产不得含 .env ----------
check_env() {
  local f="$1"
  case "$f" in
    *.zip) if unzip -l "$f" 2>/dev/null | grep -qE '(^|[[:space:]/])(\.env)$'; then echo "❌ $f 内含 .env，禁止发布！" >&2; exit 1; fi;;
    *.dmg) echo "  (dmg 跳过自动扫描，请确保构建时用了 .env.hidden-build 流程)";;
    *.exe) echo "  (exe 跳过自动扫描，请确认 win-unpacked 无 .env)";;
  esac
}

# ---------- 2. 建 Release（已存在则复用）----------
mk_release() {
  local code
  code=$(curl -s -o /tmp/rel.json -w "%{http_code}" -X POST "$API/releases" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"$TAG\",\"body\":\"BOSS智能筛选 $TAG\",\"draft\":false,\"prerelease\":false}")
  if [[ "$code" == "201" ]]; then
    python3 -c "import json;print(json.load(open('/tmp/rel.json'))['id'])"
  elif [[ "$code" == "422" ]]; then
    curl -s "$API/releases/tags/$TAG" -H "Authorization: Bearer $TOKEN" | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])"
  else
    echo "❌ 建 Release 失败 HTTP $code" >&2; cat /tmp/rel.json >&2; exit 1
  fi
}

# ---------- 3. 上传资产（GitHub 会剥离中文，统一用 BOSS. 前缀命名）----------
upload() {
  local rel_id="$1" f="$2" name="$3"
  echo "  上传 $name ($(mb "$(stat -f%z "$f")"))..."
  local code
  code=$(curl -s -o /tmp/up.json -w "%{http_code}" -X POST \
    "$UP/$rel_id/assets?name=$name" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/octet-stream" \
    --data-binary @"$f")
  [[ "$code" == "201" ]] || { echo "❌ 上传 $name 失败 HTTP $code" >&2; cat /tmp/up.json >&2; exit 1; }
}

REL_ID=""
if [[ -n "$DMG" || -n "$ZIP" || -n "$EXE" ]]; then
  echo "== 建立/获取 Release $TAG =="
  REL_ID=$(mk_release)
  echo "  release id: $REL_ID"
  for spec in "${DMG:+$DMG:BOSS.$VER-arm64.dmg}" "${ZIP:+$ZIP:BOSS.$VER-arm64-mac.zip}" "${EXE:+$EXE:BOSS.$VER-win64.exe}"; do
    [[ -n "$spec" ]] || continue
    f="${spec%%:*}"; name="${spec##*:}"
    [[ -f "$f" ]] || { echo "❌ 文件不存在: $f" >&2; exit 1; }
    check_env "$f"
    upload "$REL_ID" "$f" "$name"
  done
  # 线上可达性抽验（Range 206）
  sleep 5
  for name in "${DMG:+BOSS.$VER-arm64.dmg}" "${ZIP:+BOSS.$VER-arm64-mac.zip}" "${EXE:+BOSS.$VER-win64.exe}"; do
    [[ -n "$name" ]] || continue
    code=$(curl -s -o /dev/null -w "%{http_code}" -L -r 0-1023 \
      "https://github.com/QSCF6-live/QSCF6-live.github.io/releases/download/$TAG/$name")
    [[ "$code" == "206" || "$code" == "302" ]] && echo "  ✓ $name 可下载 ($code)" \
      || { echo "❌ $name 不可下载 HTTP $code" >&2; exit 1; }
  done
fi

# ---------- 4. 页面版本号替换 ----------
echo "== 更新页面版本号 → $VER =="
python3 - "$PAGE" "$VER" "$TODAY" "$SUFFIX" <<'PYEOF'
import re, sys
page, ver, today = sys.argv[1], sys.argv[2], sys.argv[3]
TAG_SUFFIX = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else "通用版"
src = open(page, encoding="utf-8").read()
src, n1 = re.subn(r'v\d+\.\d+\.\d+ · [^<"]+', f'v{ver} · {TAG_SUFFIX}', src)
src, n2 = re.subn(r'© \d{4} BOSS智能筛选 · v[\d.]+', f'© 2026 BOSS智能筛选 · v{ver}', src)
src, n3 = re.subn(r'releases/download/v[\d.]+', f'releases/download/v{ver}', src)
src, n4 = re.subn(r'BOSS\.\d+\.\d+\.\d+', f'BOSS.{ver}', src)
src, n5 = re.subn(r'更新于 [\d -]+', f'更新于 {today}', src)
open(page, "w", encoding="utf-8").write(src)
print(f"  badge:{n1} copyright:{n2} REL:{n3} assets:{n4} date:{n5}")
PYEOF

# ---------- 5. 提交 + 推送 ----------
cd "$DIR"
git add index.html
git commit -m "v$VER: 版本更新 $( [[ -n "$REL_ID" ]] && echo "+ 资产上线" || echo "(仅版本号)" )" || echo "  (无改动，跳过提交)"
TOKEN="$TOKEN" git -c credential.helper= \
  -c credential.helper='!f(){ echo username=QSCF6-live; echo password='"$TOKEN"'; };f' \
  push origin main 2>&1 | sed "s/$TOKEN/[MASKED]/g"

# ---------- 6. 线上验证 ----------
echo "== 等待 Pages 部署并验证 =="
sleep 45
live=$(curl -s "https://qscf6-live.github.io/?nocache=$(date +%s)")
if echo "$live" | grep -q "v$VER"; then
  echo "✓ 页面已显示 v$VER"
else
  echo "⚠ 页面尚未出现 v$VER（部署可能未完成，稍后手动刷新确认）"
fi
stale=$(echo "$live" | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | sort -u | grep -v "v$VER" || true)
[[ -z "$stale" ]] && echo "✓ 无残留旧版本号" || echo "⚠ 残留旧版本号: $stale"
echo "== 发布完成: $TAG =="
