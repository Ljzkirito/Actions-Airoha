#!/bin/bash
# =============================================================================
# Ubuntu 24.04 (noble) 专用：构建环境“补充安装”
#
# 本脚本对应 immortalwrt init_build_environment.sh 中 noble 分支的后半段：
#   - LLVM 23        (apt.llvm.org)        —— 原变量 LLVM_VERSION=23
#   - Node.js 24     (nodesource)          —— 原脚本 NODE_VERSION 默认 24
#   - Yarn classic   (dl.yarnpkg.com)
#   - Go 1.27        (ppa:longsleep/golang-backports)
#   - gh             (本脚本改用 noble universe，省掉 cli.github.com 源)
#   - upx 5.3.0 / padjffs2 / po2lmo 三个手工编译件
#
# noble 上的 BPO_FLAG 与 VERSION_PACKAGE 都是空，所以这里不出现
# `-t noble-backports` 和 python2。
#
# 用法（必须以 root 运行，且应先装好基础包）：
#   sudo bash scripts/init-extra-24.04.sh
#
# 与上游的差异（都是有意的）：
#   1. 不做 `apt full-upgrade`——在承载 runner 的 VM 上升级 systemd/libc 是
#      “The hosted runner lost communication” 的高危来源；
#   2. 不写 China 镜像（hosted runner 在境外，CHN_NET 分支永远是死代码）；
#   3. padjffs2 去掉 -Werror：新编译器多一条 warning 就让整个初始化失败不值当；
#   4. gh 走 Ubuntu 自带源，少一个第三方 repo。
# =============================================================================
set -euo pipefail

LLVM_VERSION=23
NODE_MAJOR=24
GO_VERSION=1.27
UPX_REV=5.3.0

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: 需要 root 权限: sudo bash $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log() { printf '\n\033[36m[INFO]\033[0m %s\n' "$*"; }

# -----------------------------------------------------------------------------
# 1. 第三方源
# -----------------------------------------------------------------------------
log "配置第三方 apt 源 (llvm-${LLVM_VERSION} / node ${NODE_MAJOR} / yarn / go ${GO_VERSION})"

apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg software-properties-common

install -d -m 0755 /etc/apt/keyrings

# LLVM 23 —— noble 官方源只有 18/19
curl -fsSL --retry 3 --retry-delay 5 \
  https://apt.llvm.org/llvm-snapshot.gpg.key \
  | gpg --dearmor --yes -o /etc/apt/keyrings/llvm.gpg
echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] https://apt.llvm.org/noble/ llvm-toolchain-noble-${LLVM_VERSION} main" \
  > /etc/apt/sources.list.d/llvm.list

# Node.js 24
curl -fsSL --retry 3 --retry-delay 5 \
  https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list

# Yarn classic
curl -fsSL --retry 3 --retry-delay 5 \
  https://dl.yarnpkg.com/debian/pubkey.gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/yarn.gpg
echo "deb [signed-by=/etc/apt/keyrings/yarn.gpg] https://dl.yarnpkg.com/debian/ stable main" \
  > /etc/apt/sources.list.d/yarn.list

# Go 1.27（noble 自带的是 1.22）
add-apt-repository -y ppa:longsleep/golang-backports

apt-get update -y

# -----------------------------------------------------------------------------
# 2. LLVM 23
# -----------------------------------------------------------------------------
log "安装 LLVM ${LLVM_VERSION}"
apt-get install -y --no-install-recommends \
  "clang-${LLVM_VERSION}" \
  "libclang-${LLVM_VERSION}-dev" \
  "lld-${LLVM_VERSION}" \
  "liblld-${LLVM_VERSION}-dev" \
  "llvm-${LLVM_VERSION}"

# 把 llvm-23 的全套工具暴露到 /usr/bin（原脚本写法，这里加了目录存在性检查，
# 否则通配符不展开会把字面量 "*" 链过去）
if [ -d "/usr/lib/llvm-${LLVM_VERSION}/bin" ]; then
  for i in "/usr/lib/llvm-${LLVM_VERSION}/bin"/*; do
    ln -sf "$i" "/usr/bin/${i##*/}"
  done
  # 原脚本是 ln -svf；若 /usr/lib/llvm 已存在（真目录）则不覆盖
  if [ ! -e /usr/lib/llvm ]; then
    ln -s "/usr/lib/llvm-${LLVM_VERSION}" /usr/lib/llvm
  fi
fi

# -----------------------------------------------------------------------------
# 3. Node.js 24 + Yarn
# -----------------------------------------------------------------------------
log "安装 Node.js ${NODE_MAJOR} + Yarn"
apt-get install -y --no-install-recommends nodejs yarn
node -v
yarn --version || echo "WARN: yarn 未就绪（不影响 C 构建）"

# -----------------------------------------------------------------------------
# 4. Go 1.27
# -----------------------------------------------------------------------------
log "安装 Go ${GO_VERSION}"
apt-get install -y --no-install-recommends "golang-${GO_VERSION}-go"
rm -f /usr/bin/go /usr/bin/gofmt
ln -s "/usr/lib/go-${GO_VERSION}/bin/go" /usr/bin/go
ln -s "/usr/lib/go-${GO_VERSION}/bin/gofmt" /usr/bin/gofmt
go version

# -----------------------------------------------------------------------------
# 5. gh（noble universe 自带，不需要 cli.github.com）
# -----------------------------------------------------------------------------
apt-get install -y --no-install-recommends gh
gh --version | head -n1

apt-get clean -y

# -----------------------------------------------------------------------------
# 6. 手工编译件：upx / padjffs2 / po2lmo
# -----------------------------------------------------------------------------
log "编译安装 upx ${UPX_REV} / padjffs2 / po2lmo"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
cd "${TMP_DIR}"

# upx 5.3.0
curl -fsSLO --retry 3 --retry-delay 5 \
  "https://github.com/upx/upx/releases/download/v${UPX_REV}/upx-${UPX_REV}-amd64_linux.tar.xz"
tar -Jxf "upx-${UPX_REV}-amd64_linux.tar.xz"
rm -f /usr/bin/upx /usr/bin/upx-ucl
install -m 0755 "upx-${UPX_REV}-amd64_linux/upx" /usr/bin/upx-ucl
ln -sf /usr/bin/upx-ucl /usr/bin/upx
upx --version | head -n1

# padjffs2（注意：去掉了上游的 -Werror）
curl -fsSLO --retry 3 --retry-delay 5 \
  "https://raw.githubusercontent.com/openwrt/openwrt/main/tools/padjffs2/src/padjffs2.c"
gcc -Wall -O2 -o padjffs2 padjffs2.c
strip padjffs2
install -m 0755 padjffs2 /usr/bin/padjffs2

# po2lmo
git clone --filter=blob:none --no-checkout https://github.com/openwrt/luci.git po2lmo
cd po2lmo
git config core.sparseCheckout true
echo "modules/luci-base/src" >> .git/info/sparse-checkout
git checkout --quiet
cd modules/luci-base/src
make po2lmo
strip po2lmo
install -m 0755 po2lmo /usr/bin/po2lmo
cd "${TMP_DIR}"

cd /
rm -rf "${TMP_DIR}"
trap - EXIT

log "完成：llvm-${LLVM_VERSION} / node $(node -v) / $(go version | awk '{print $3}') / upx ${UPX_REV} / padjffs2 / po2lmo"
