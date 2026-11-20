#!/bin/bash -e
# 补入源码 (padavanonly/immortalwrt-mt798x-6.6 @ openwrt-24.10-6.6) 中缺失的两个 512ROM 机型：
#   netcore_n60-pro-512rom             Netcore N60 Pro 512MB NAND
#   xiaomi_redmi-router-ax6000-512rom  Xiaomi Redmi AX6000（OpenWrt U-Boot 布局）512MB NAND
#
# 说明：
#   * 上游该分支只定义了 netcore_n60-pro 与 xiaomi_redmi-router-ax6000-stock/-ubootmod，
#     没有 512MB NAND 变体，选 512ROM 的 .config 会被 kconfig 静默丢弃、编不出固件。
#   * 这里不引入外部树，dts 直接由上游现有机型 dts 派生（只改 model / compatible / ubi 分区大小），
#     从而跟随上游的分区布局与 dtsi 结构，避免与 6.6 内核不匹配。
#   * 幂等：filogic.mk 里已有 define 则整段跳过。

MK="${MK:-target/linux/mediatek/image/filogic.mk}"
DTSDIR="${DTSDIR:-target/linux/mediatek/dts}"

[ -f "$MK" ] || { echo "::error::找不到 $MK（当前目录不是 openwrt 源码根？）"; exit 1; }

fail() { echo "::error::$*"; exit 1; }

need_device() {
    ! grep -q "^define Device/$1\$" "$MK"
}

echo "---- 补入 512ROM 机型 ----"

# ------------------------------------------------------------------ N60 Pro 512ROM
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

# ------------------------------------------------------- Redmi AX6000 ubootmod 512ROM
if need_device xiaomi_redmi-router-ax6000-512rom; then
    src="$DTSDIR/mt7986a-xiaomi-redmi-router-ax6000-ubootmod.dts"
    dst="$DTSDIR/mt7986a-xiaomi-redmi-router-ax6000-512rom.dts"
    [ -f "$src" ] || fail "缺少 $src，无法派生 Redmi AX6000 512ROM 的 dts"

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

echo "---- 补入结果 ----"
grep -c '512rom' "$MK" || true
grep -n '^define Device/.*512rom' "$MK" || true
ls -l "$DTSDIR"/*512rom*.dts || true
