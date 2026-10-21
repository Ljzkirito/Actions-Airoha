#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#

if [ ! -d "package/libs/libffi" ]; then
    mkdir -p "package/libs/libffi"
    curl -fsSL --retry 3 -o "package/libs/libffi/Makefile" "https://github.com/immortalwrt/immortalwrt/raw/refs/heads/master/package/libs/libffi/Makefile"
fi