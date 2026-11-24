#!/bin/bash
# 免费签名最长 7 天。这个脚本每 6 小时检查一次，手机在线且快到期时
# 自动重新签名并装回 iPhone，避免 App 突然打不开。
# 逻辑与 /Users/alex/project/readbook/scripts/refresh_install.sh 一致。
set -uo pipefail

ROOT="/Users/alex/project/rustdesk/flutter"
DEVICE_ID="00008150-000918560C04401C"
BUNDLE_ID="com.psrcaus75d.rustdesk"
LOG="$HOME/Library/Logs/rustdesk-refresh.log"
STATE_DIR="$HOME/Library/Application Support/rustdesk"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
BACKUP_DIR="$STATE_DIR/profiles"
DERIVED="$ROOT/build/ios_refresh"
APP="$DERIVED/Build/Products/Release-iphoneos/Runner.app"
FLUTTER="/Users/alex/development/flutter-3.44.9/bin/flutter"
XCODEBUILD="/usr/bin/xcodebuild"
RUST_LIB="/Users/alex/project/rustdesk/target/aarch64-apple-ios/release/liblibrustdesk.a"
export PATH="/Users/alex/development/flutter-3.44.9/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$(dirname "$LOG")" "$BACKUP_DIR"
say() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

say_once() {
  local key="$1" msg="$2" f="$STATE_DIR/.skip-$1"
  local now last=0
  now=$(date +%s)
  [ -f "$f" ] && last=$(stat -f %m "$f" 2>/dev/null || echo 0)
  if [ $((now - last)) -ge 21600 ]; then
    say "$msg"
    touch "$f"
  fi
}

# 1) 手机在线检查
LINE=$(/usr/bin/xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_ID" | head -1)
if [ -z "$LINE" ] || echo "$LINE" | grep -qi "unavailable\|unpaired\|disconnected"; then
  say_once offline "手机未在线，跳过本次续签"
  exit 0
fi

# 2) 手机是否已经装了本 App
INSTALLED=no
if /usr/bin/xcrun devicectl device info apps --device "$DEVICE_ID" 2>/dev/null | grep -q "$BUNDLE_ID"; then
  INSTALLED=yes
fi

# 3) 剩余 6 天及以下才续签（FORCE=1 跳过此判断，用于开发时重装）
if [ "${FORCE:-0}" != "1" ] && [ "$INSTALLED" = "yes" ] && [ -f "$APP/embedded.mobileprovision" ]; then
  EXP=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null)
  if [ -n "${EXP:-}" ]; then
    NOW=$(date -u +%s)
    THEN=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$EXP" +%s 2>/dev/null || echo 0)
    if [ "$THEN" -gt 0 ]; then
      LEFT=$(( (THEN - NOW) / 86400 ))
      if [ "$LEFT" -ge 7 ]; then
        say_once ok "剩余 ${LEFT} 天，暂不需要续签"
        exit 0
      fi
      RENEW_STAMP="$STATE_DIR/.last-renew"
      if [ -f "$RENEW_STAMP" ]; then
        LAST=$(stat -f %m "$RENEW_STAMP" 2>/dev/null || echo 0)
        if [ $(( $(date +%s) - LAST )) -lt 72000 ]; then
          say_once recent "刚刚续签过（20 小时内），跳过"
          exit 0
        fi
      fi
      if [ "$LEFT" -lt 0 ]; then
        say "描述文件已过期，立即续签"
      fi
    fi
  fi
fi

# 4) Apple 开发者站点连通性
PROXY=""
if [ "$(scutil --proxy 2>/dev/null | awk '/HTTPSEnable/{print $3}')" = "1" ]; then
  P=$(scutil --proxy 2>/dev/null | awk '/HTTPSPort/{print $3}')
  [ -n "${P:-}" ] && PROXY="http://127.0.0.1:$P"
fi
reachable() {
  local code=""
  if [ -n "$PROXY" ]; then
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 -x "$PROXY" https://developer.apple.com 2>/dev/null)
  fi
  [ "$code" = "200" ] && return 0
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 --noproxy '*' https://developer.apple.com 2>/dev/null)
  [ "$code" = "200" ]
}
if ! reachable; then
  say "连不上 Apple 开发者站点，跳过本次续签（现有安装不受影响）"
  exit 0
fi

[ -f "$RUST_LIB" ] || { say "缺少 Rust iOS 静态库：$RUST_LIB"; exit 1; }

say "开始重新签名"
cd "$ROOT" || { say "找不到 Flutter 目录"; exit 1; }

# 5) 清掉本 App 的旧描述文件，强制 Xcode 申请新的
for f in "$PROFILE_DIR"/*.mobileprovision; do
  [ -e "$f" ] || continue
  if security cms -D -i "$f" 2>/dev/null | grep -q "$BUNDLE_ID"; then
    cp -f "$f" "$BACKUP_DIR/$(basename "$f")" 2>/dev/null
    rm -f "$f" && say "已清除旧描述文件，将申请新的"
  fi
done

restore_profiles() {
  for b in "$BACKUP_DIR"/*.mobileprovision; do
    [ -e "$b" ] || continue
    cp -f "$b" "$PROFILE_DIR/$(basename "$b")" 2>/dev/null
  done
}

# 6) 生成 Flutter/Xcode 配置（会处理 Pods）
if ! "$FLUTTER" build ios --release --config-only --no-pub >> "$LOG" 2>&1; then
  restore_profiles
  say "Flutter 配置失败（检查 flutter doctor / Pods）"
  exit 1
fi

# 7) 用自动签名构建 Release
if ! "$XCODEBUILD" -workspace "$ROOT/ios/Runner.xcworkspace" -scheme Runner \
      -configuration Release -destination "id=$DEVICE_ID" \
      -allowProvisioningUpdates -derivedDataPath "$DERIVED" build \
      >> "$LOG" 2>&1; then
  restore_profiles
  say "构建失败（多半是 Apple ID 登录失效或描述文件问题），已还原描述文件"
  /usr/bin/osascript -e 'display notification "续签失败，请打开 Xcode 确认 Apple ID 登录状态" with title "RustDesk 无法自动续签"' >/dev/null 2>&1
  exit 1
fi

[ -d "$APP" ] || APP="$DERIVED/Build/Products/Release-iphoneos/RustDesk.app"
[ -d "$APP" ] || { say "构建产物缺失"; exit 1; }

# 8) 装回手机并启动
if /usr/bin/xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >> "$LOG" 2>&1; then
  NEWEXP=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null)
  touch "$STATE_DIR/.last-renew"
  say "安装/续签成功，新的到期时间 $NEWEXP"
  /usr/bin/xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >> "$LOG" 2>&1 || true
else
  say "安装失败，现有安装不受影响"
  exit 1
fi
