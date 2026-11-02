#!/bin/sh
# 把带自定义页的 SnowApp 装到 /data/bin/SnowApp，并保留原版备份。
# 前提：系统处于正常状态（官方看门狗和界面在运行），/data/custom 里已有 SnowApp.patched 和 CustomView.qml。
# 恢复：sh /data/custom/restore_orig.sh

ORIG_SHA=a39016531620a874668ee322f0e976f48e47943742c54c8a7291b9e830c91abb
PATCHED_SHA=7300addb7fda4714b93cc45d3eb1df00b6940bdd5265fff119c7cf12933746e6
BIN=${BIN:-/data/bin/SnowApp}
CUSTOM=${CUSTOM:-/data/custom}
BAK=$CUSTOM/SnowApp.orig
NEW=$CUSTOM/SnowApp.patched

sha() { sha256sum "$1" | awk '{print $1}'; }
die() { echo "中止: $1"; exit 1; }

[ -f "$NEW" ] || die "找不到 $NEW"
[ -f "$CUSTOM/CustomView.qml" ] || die "找不到 $CUSTOM/CustomView.qml"
[ "$(sha "$NEW")" = "$PATCHED_SHA" ] || die "$NEW 校验值不对，请重新下载"

CUR=$(sha "$BIN")
if [ "$CUR" = "$PATCHED_SHA" ]; then echo "已经是改过的版本，无需安装"; exit 0; fi
[ "$CUR" = "$ORIG_SHA" ] || die "当前 $BIN 不是已知的原版（可能被升级过），不覆盖"

FREE=$(df -k /data 2>/dev/null | awk 'END{if (NF >= 3) print $(NF-2)}')
if [ -n "$FREE" ] && [ "$FREE" -lt 15000 ] 2>/dev/null; then die "/data 剩余空间不足 (${FREE}K)"; fi

# 1) 备份原版并校验
[ -f "$BAK" ] || cp "$BIN" "$BAK" || die "备份失败"
[ "$(sha "$BAK")" = "$ORIG_SHA" ] || die "备份校验失败"
sync

# 2) 先复制到同目录临时文件并校验，再用 mv 原子替换（运行中的旧进程不受影响）
cp "$NEW" "$BIN.new" || die "复制失败"
chmod 755 "$BIN.new"
[ "$(sha "$BIN.new")" = "$PATCHED_SHA" ] || { rm -f "$BIN.new"; die "临时文件校验失败"; }
sync
mv -f "$BIN.new" "$BIN" || die "替换失败"
sync
echo "已安装。原版备份在 $BAK"

# 3) 让新版本生效：看门狗在运行时，杀掉旧进程，看门狗约 5 秒内用新文件拉起
if ps | grep -q '[w]atchdog.sh'; then
  PID=$(ps | grep '[S]nowApp' | awk '{print $1}')
  if [ -n "$PID" ]; then
    echo "重启 SnowApp，看门狗会在 5 秒内拉起新版本"
    kill -9 $PID
  fi
else
  echo "看门狗没在运行，请执行 reboot 让新版本生效"
fi
