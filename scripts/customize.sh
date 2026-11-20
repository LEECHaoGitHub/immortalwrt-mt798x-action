#!/bin/bash
# 主题换 vantage（默认主题，唯一预装主题）+ iStore 市场 + 中文包 + 保障 SSH（在源码根目录执行）
set -e
cd "${1:-.}"

VANTAGE_REPO=https://github.com/anothaDev/luci-theme-vantage
# 固定 tag：本脚本会按行号无关的字符串替换改主题的侧栏默认值，换版本时需同步复核这两处
VANTAGE_TAG=v1.0.21

echo "== 1/7 引入 iStore feed =="
for f in feeds.conf feeds.conf.default; do
  [ -f "$f" ] || continue
  sed -i '/^src-git istore /d' "$f"
  echo 'src-git istore https://github.com/istoreos/istore.git' >> "$f"
done
./scripts/feeds update -a

echo "== 2/7 移除预装主题（只保留外挂的 vantage）=="
rm -rf feeds/luci/themes/luci-theme-* \
       package/feeds/luci/luci-theme-* \
       feeds/luci/applications/luci-app-argon-config \
       package/feeds/luci/luci-app-argon-config
# luci-light 是 luci 集合的底座，主题依赖改成 vantage，否则删掉 bootstrap 后会缺包
sed -i 's/+luci-theme-bootstrap/+luci-theme-vantage/' feeds/luci/collections/luci-light/Makefile
grep -q '+luci-theme-vantage' feeds/luci/collections/luci-light/Makefile

echo "== 3/7 安装 feeds =="
./scripts/feeds install -a

echo "== 4/7 引入 luci-theme-vantage =="
rm -rf package/luci-theme-vantage
git clone --quiet --depth 1 --branch "$VANTAGE_TAG" "$VANTAGE_REPO" package/luci-theme-vantage
test -f package/luci-theme-vantage/luci-theme-vantage/Makefile

echo "== 5/7 侧栏默认展开（图标 + 名称）=="
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

echo "== 6/7 写入配置 =="
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-theme-vantage=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_dropbear=y
EOF

echo "== 7/7 默认主题 uci-defaults =="
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
