#!/usr/bin/env bash
# hokan-deploy — 拉取 midnighthokan.com 仓库 → 脱敏检查 → 构建 → 备案号检查 → 原子替换上线
# 用法：hokan-deploy            # 只有 GitHub 上有新提交才部署（timer 调用）
#       hokan-deploy --force    # 强制重新构建并部署
set -euo pipefail

REPO=/data/midnighthokan.com
WWW=/var/www/midnighthokan
STATE=/var/lib/hokan-deploy
ICP='京ICP备2026041424号'
SITE=https://midnighthokan.com/
NPM_REG=https://registry.npmmirror.com
FORCE=${1:-}

mkdir -p "$STATE"
exec 9>"$STATE/lock"
flock -n 9 || { echo "another deploy is running"; exit 0; }

cd "$REPO"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git fetch -q origin "$BRANCH"
git merge -q --ff-only "origin/$BRANCH" || { echo "FAIL: local $BRANCH cannot fast-forward to origin"; exit 1; }
HEAD=$(git rev-parse HEAD)

if [[ "$FORCE" != "--force" && -f "$STATE/deployed" && "$(cat "$STATE/deployed")" == "$HEAD" ]]; then
  exit 0
fi
echo "deploying $HEAD"

# 1) 脱敏关卡：内容里出现舰队内部标识就拒绝发布
/usr/local/bin/hokan-sanitize "$REPO/src/content"

# 2) 构建
if [[ -f package-lock.json ]]; then
  npm ci --registry="$NPM_REG" --no-audit --no-fund --loglevel=error
else
  npm install --registry="$NPM_REG" --no-audit --no-fund --loglevel=error
fi
rm -rf dist
npm run build --silent

# 3) 产物关卡：首页存在且带备案号
[[ -f dist/index.html ]] || { echo "FAIL: dist/index.html missing"; exit 1; }
grep -q "$ICP" dist/index.html || { echo "FAIL: ICP number missing from homepage footer"; exit 1; }

# 4) 原子替换，旧版本留 5 份
TS=$(date +%Y%m%d-%H%M%S)
rm -rf "$WWW.new"
cp -a dist "$WWW.new"
if [[ -d "$WWW" ]]; then mv "$WWW" "$STATE/www-$TS"; fi
mv "$WWW.new" "$WWW"
ls -dt "$STATE"/www-* 2>/dev/null | tail -n +6 | xargs -r rm -rf

# 5) 线上验证，失败自动回滚
sleep 1
if curl -fsS -m 10 "$SITE" | grep -q "$ICP"; then
  echo "$HEAD" > "$STATE/deployed"
  echo "OK: $SITE now serves $HEAD"
else
  echo "FAIL: live check failed, rolling back"
  rm -rf "$WWW"
  mv "$STATE/www-$TS" "$WWW"
  exit 1
fi
