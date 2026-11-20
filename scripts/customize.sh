#!/bin/bash
# 主题换 vantage（默认主题，唯一预装主题）+ iStore 市场 + 中文包 + 首页仪表盘（quickstart）
# + 保障 SSH（在源码根目录执行）
set -e
cd "${1:-.}"

VANTAGE_REPO=https://github.com/anothaDev/luci-theme-vantage
# 固定 tag：本脚本会按行号无关的字符串替换改主题的侧栏默认值，换版本时需同步复核这两处
VANTAGE_TAG=v1.0.21

echo "== 1/8 引入 iStore feed =="
for f in feeds.conf feeds.conf.default; do
  [ -f "$f" ] || continue
  sed -i '/^src-git istore /d' "$f"
  echo 'src-git istore https://github.com/istoreos/istore.git' >> "$f"
done
./scripts/feeds update -a

echo "== 2/8 移除预装主题（只保留外挂的 vantage）=="
rm -rf feeds/luci/themes/luci-theme-* \
       package/feeds/luci/luci-theme-* \
       feeds/luci/applications/luci-app-argon-config \
       package/feeds/luci/luci-app-argon-config
# luci-light 是 luci 集合的底座，主题依赖改成 vantage，否则删掉 bootstrap 后会缺包
sed -i 's/+luci-theme-bootstrap/+luci-theme-vantage/' feeds/luci/collections/luci-light/Makefile
grep -q '+luci-theme-vantage' feeds/luci/collections/luci-light/Makefile

echo "== 3/8 安装 feeds =="
./scripts/feeds install -a

echo "== 4/8 引入 luci-theme-vantage =="
rm -rf package/luci-theme-vantage
git clone --quiet --depth 1 --branch "$VANTAGE_TAG" "$VANTAGE_REPO" package/luci-theme-vantage
test -f package/luci-theme-vantage/luci-theme-vantage/Makefile

echo "== 5/8 侧栏默认展开（图标 + 名称）=="
# vantage 的左侧导航默认是「图标 + 悬停飞出」，展开态只记在浏览器 localStorage(vantage.rail)。
# 改成默认 pinned（图标 + 名称常显），并把「折叠」写成 'rail' 以便用户折叠后能持久保持。
python3 - <<'PY'
import sys

def patch(path, pairs):
    s = open(path, encoding="utf-8").read()
    for old, new in pairs:
        if s.count(old) != 1:
            sys.exit("[ERROR] %s 中待替换片段出现 %d 次（期望 1）: %s" % (path, s.count(old), old[:70]))
        s = s.replace(old, new, 1)
    open(path, "w", encoding="utf-8", newline="\n").write(s)

root = "package/luci-theme-vantage/luci-theme-vantage"
patch(root + "/ucode/template/themes/vantage/header.ut", [(
    "rail = localStorage.getItem('vantage.rail') || '';",
    "rail = localStorage.getItem('vantage.rail');\n\tif (rail === null) rail = 'pinned';",
)])
patch(root + "/htdocs/luci-static/resources/menu-vantage.js", [(
    "storageSet(RAIL_KEY, pinned ? null : 'pinned');",
    "storageSet(RAIL_KEY, pinned ? 'rail' : 'pinned');",
)])
print("[ok] 侧栏默认展开（pinned）")
PY

echo "== 6/8 引入首页仪表盘（iStoreOS 风格 quickstart）=="
# luci-app-quickstart 不在 istore feed（istoreos 把它放在自家 luci fork 里），
# 所以从 kiddin9/op-packages 树内 vendor 两件套：
#   luci-app-quickstart —— LuCI 首页仪表盘（网络向导/设备管理/测速/商店入口）
#   quickstart          —— 守护进程（预编译二进制，aarch64 直接可用）
# 注意 <64M NOR 小闪存机型慎用：quickstart 带 mdadm/parted/smartmontools，体积不小
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 --filter=blob:none --sparse \
  https://github.com/kiddin9/op-packages.git "$tmp/repo"
git -C "$tmp/repo" sparse-checkout set luci-app-quickstart quickstart
for p in luci-app-quickstart quickstart; do
  # feed 里若有同名副本必须先删：两处同时存在时 kconfig 取 feed 那份（带架构约束），会静默丢包
  rm -rf "package/feeds/istore/$p" "package/feeds/luci/$p" "package/feeds/kiddin9/$p" "package/$p"
  cp -a "$tmp/repo/$p" "package/$p"
  [ -f "package/$p/Makefile" ] || { echo "::error::quickstart 包缺失: $p"; exit 1; }
done
echo "✔ 首页仪表盘（luci-app-quickstart + quickstart）已 vendor 到 package/"
echo "== 7/8 写入配置 =="
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-theme-vantage=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_luci-lib-taskd=y
CONFIG_PACKAGE_luci-lib-xterm=y
CONFIG_PACKAGE_taskd=y
CONFIG_PACKAGE_libuci-lua=y
CONFIG_PACKAGE_luci-app-quickstart=y
CONFIG_PACKAGE_quickstart=y
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_tar=y
CONFIG_PACKAGE_mount-utils=y
CONFIG_PACKAGE_xz-utils=y
CONFIG_PACKAGE_dropbear=y
EOF

echo "== 8/8 默认主题 uci-defaults =="
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-default-theme <<'EOT'
#!/bin/sh
# 仅在主题未选或仍指向已删除的 bootstrap 时切到 vantage，升级保留用户自己的选择
[ -n "$(uci -q get luci.themes.Vantage)" ] || exit 0
case "$(uci -q get luci.main.mediaurlbase)" in
	''|/luci-static/bootstrap)
		uci -q set luci.main.mediaurlbase='/luci-static/vantage'
		uci -q commit luci
		;;
esac
exit 0
EOT
chmod +x files/etc/uci-defaults/99-default-theme
echo "[done] customize"
