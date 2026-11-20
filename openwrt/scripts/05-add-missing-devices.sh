#!/bin/bash -e
# 补入源码 (padavanonly/immortalwrt-mt798x-6.6 @ openwrt-24.10-6.6) 中缺失的机型定义：
#   netcore_n60-pro-512rom             Netcore N60 Pro 512MB NAND（dts 由现有机型派生）
#   xiaomi_redmi-router-ax6000-512rom  Redmi AX6000 U-Boot 布局 + 512MB NAND（dts 由 ubootmod 派生）
#   sl_3000                            SL-3000 NAND（上游只剩 sl_3000-emmc）
#   clx_s20p                           CLX S20P（上游只有 supergateway_s20p 等同 SOC 机型）
#   newland_nl-wr8103                  Newland NL-WR8103
#
# 说明：
#   * 512ROM 两款的 dts 直接由上游现成 dts 派生，只改 model / compatible / ubi 分区大小，
#     分区布局与 dtsi 结构跟随上游，不会和 6.6 内核打架。
#   * sl_3000 / clx_s20p / nl-wr8103 的 dts 取自同代 immortalwrt-24.10 树（本仓库 openwrt/devices/），
#     构建时按 $mirror 拉取；Device 定义与该树保持一致。
#   * 全部幂等：filogic.mk 里已有同名 define 就跳过。

MK="${MK:-target/linux/mediatek/image/filogic.mk}"
DTSDIR="${DTSDIR:-target/linux/mediatek/dts}"

[ -f "$MK" ] || { echo "::error::找不到 $MK（当前目录不是 openwrt 源码根？）"; exit 1; }

fail() { echo "::error::$*"; exit 1; }
need_device() { ! grep -q "^define Device/$1\$" "$MK"; }

fetch_dts() {
    local f="$1" dst="$DTSDIR/$1" src
    if [ -s "$dst" ]; then echo "  · dts $f 已存在"; return 0; fi
    if [ -n "${DTS_LOCAL:-}" ] && [ -f "$DTS_LOCAL/$f" ]; then
        cp "$DTS_LOCAL/$f" "$dst"
    else
        src="$mirror/openwrt/devices/$f"
        curl -fsSL "$src" -o "$dst" || true
    fi
    [ -s "$dst" ] || fail "获取设备树 $f 失败（来源 ${src:-$DTS_LOCAL}）"
    echo "  ✔ dts $f"
}

echo "---- 补入源码缺失机型 ----"

# ------------------------------------------------------------ Netcore N60 Pro 512ROM
if need_device netcore_n60-pro-512rom; then
    src="$DTSDIR/mt7986a-netcore-n60-pro.dts"
    dst="$DTSDIR/mt7986a-netcore-n60-pro-512rom.dts"
    [ -f "$src" ] || fail "缺少 $src，无法派生 N60 Pro 512ROM 的 dts"
    sed -e 's/^\([[:space:]]*\)model = "Netcore N60 Pro";/\1model = "Netcore N60 Pro (512MB NAND)";/' \
        -e 's/compatible = "netcore,n60-pro", "mediatek,mt7986a";/compatible = "netcore,n60-pro-512rom", "mediatek,mt7986a";/' \
        -e 's/reg = <0x0580000 0x7280000>;/reg = <0x0580000 0x1ea00000>;/' \
        "$src" > "$dst"
    grep -q 'netcore,n60-pro-512rom' "$dst" || fail "N60 Pro 512ROM：compatible 未替换成功"
    grep -q '0x1ea00000' "$dst" || fail "N60 Pro 512ROM：ubi 分区未改为 490MB"
    cat >> "$MK" <<'EOF'

define Device/netcore_n60-pro-512rom
  DEVICE_VENDOR := Netcore
  DEVICE_MODEL := N60 Pro
  DEVICE_VARIANT := (512MB NAND)
  DEVICE_DTS := mt7986a-netcore-n60-pro-512rom
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-usb3 automount kmod-usb-ledtrig-usbport
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += netcore_n60-pro-512rom
EOF
    echo "  ✔ netcore_n60-pro-512rom"
else
    echo "  · netcore_n60-pro-512rom 已存在，跳过"
fi

# --------------------------------------------------- Redmi AX6000 ubootmod 512ROM
if need_device xiaomi_redmi-router-ax6000-512rom; then
    src="$DTSDIR/mt7986a-xiaomi-redmi-router-ax6000-ubootmod.dts"
    dst="$DTSDIR/mt7986a-xiaomi-redmi-router-ax6000-512rom.dts"
    [ -f "$src" ] || fail "缺少 $src，无法派生 AX6000 512ROM 的 dts"
    sed -e 's/^\([[:space:]]*\)model = "Xiaomi Redmi Router AX6000 (OpenWrt U-Boot layout)";/\1model = "Xiaomi Redmi Router AX6000 (OpenWrt U-Boot layout, 512MB NAND)";/' \
        -e 's/compatible = "xiaomi,redmi-router-ax6000-ubootmod", "mediatek,mt7986a";/compatible = "xiaomi,redmi-router-ax6000-512rom", "mediatek,mt7986a";/' \
        -e 's/reg = <0x600000 0x6e00000>;/reg = <0x600000 0x1ea00000>;/' \
        "$src" > "$dst"
    grep -q 'xiaomi,redmi-router-ax6000-512rom' "$dst" || fail "AX6000 512ROM：compatible 未替换成功"
    grep -q '0x1ea00000' "$dst" || fail "AX6000 512ROM：ubi 分区未改为 490MB"
    cat >> "$MK" <<'EOF'

define Device/xiaomi_redmi-router-ax6000-512rom
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Redmi Router AX6000
  DEVICE_VARIANT := (OpenWrt U-Boot layout, 512MB NAND)
  DEVICE_DTS := mt7986a-xiaomi-redmi-router-ax6000-512rom
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-leds-ws2812b kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  ARTIFACTS := initramfs-factory.ubi
  ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-recovery.itb | ubinize-kernel
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_redmi-router-ax6000-512rom
EOF
    echo "  ✔ xiaomi_redmi-router-ax6000-512rom"
else
    echo "  · xiaomi_redmi-router-ax6000-512rom 已存在，跳过"
fi

# ---------------------------------------------------------------------- SL-3000 NAND
if need_device sl_3000; then
    fetch_dts mt7981b-sl-3000.dts
    cat >> "$MK" <<'EOF'

define Device/sl_3000
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000
  DEVICE_DTS := mt7981b-sl-3000
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount coremark blkid blockdev fdisk f2fsck mkf2fs kmod-mmc kmod-mtd-rw
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000
EOF
    echo "  ✔ sl_3000"
else
    echo "  · sl_3000 已存在，跳过"
fi

# ------------------------------------------------------------------------- CLX S20P
if need_device clx_s20p; then
    fetch_dts mt7986a-clx-s20p.dts
    cat >> "$MK" <<'EOF'

define Device/clx_s20p
  DEVICE_VENDOR := CLX
  DEVICE_MODEL := S20P
  DEVICE_DTS := mt7986a-clx-s20p
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-usb3 automount e2fsprogs f2fsck mkf2fs kmod-nvme kmod-mmc mmc-utils luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += clx_s20p
EOF
    echo "  ✔ clx_s20p"
else
    echo "  · clx_s20p 已存在，跳过"
fi

# ---------------------------------------------------------------- Newland NL-WR8103
if need_device newland_nl-wr8103; then
    fetch_dts mt7981b-newland-nl-wr8103.dts
    cat >> "$MK" <<'EOF'

define Device/newland_nl-wr8103
  DEVICE_VENDOR := Newland
  DEVICE_MODEL := NL-WR8103
  DEVICE_DTS := mt7981b-newland-nl-wr8103
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES := newland,nl-wr8103
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += newland_nl-wr8103
EOF
    echo "  ✔ newland_nl-wr8103"
else
    echo "  · newland_nl-wr8103 已存在，跳过"
fi

echo "---- 校验 ----"
for d in netcore_n60-pro-512rom xiaomi_redmi-router-ax6000-512rom sl_3000 clx_s20p newland_nl-wr8103; do
    grep -q "^define Device/$d\$" "$MK" || fail "$d 注入失败"
    grep -q "^TARGET_DEVICES += $d\$" "$MK" || fail "$d 未加入 TARGET_DEVICES"
done
echo "5 个机型定义均已就位；filogic.mk 现有 define Device/ 数量：$(grep -c '^define Device/' "$MK")"
