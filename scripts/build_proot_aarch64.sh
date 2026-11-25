#!/usr/bin/env bash
# build_proot_aarch64.sh — bangun proot untuk Android aarch64 (dijalankan CI).
# Sumber: proot-me/proot (master) sesuai env/env.lock PROOT_BUILD_REF.
# Hasil: android/app/libs/arm64-v8a/libproot.so (dibaca RuntimePlugin dari
#        applicationInfo.nativeLibraryDir).
set -euo pipefail

PROOT_REPO_URL="https://github.com/proot-me/proot.git"
PROOT_REF="master"
OUT_DIR="android/app/libs/arm64-v8a"
WORK_DIR="${WORK_DIR:-$(pwd)/.ci-build/proot}"

# Deps build (Debian/Ubuntu runner): libarchive untuk opsi -R tar, libtalloc
# dipakai proot, clang sebagai compiler (bawaan runner linux-arm64).
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git build-essential clang \
    libarchive-dev libtalloc-dev pkg-config make

# Klon sumber proot ( shallow, ref terkunci ).
if [ ! -d "${WORK_DIR}/.git" ]; then
    git clone --depth 1 --branch "${PROOT_REF}" "${PROOT_REPO_URL}" "${WORK_DIR}"
else
    git -C "${WORK_DIR}" fetch origin "${PROOT_REF}"
    git -C "${WORK_DIR}" checkout --force "${PROOT_REF}"
fi

# Bangun hanya biner proot (bukan proot - care) dengan clang.
make -C "${WORK_DIR}/src" clean >/dev/null 2>&1 || true
CC=clang make -C "${WORK_DIR}/src" proot

# Verifikasi hasil: biner proot ada dan ELF aarch64.
BIN="${WORK_DIR}/src/proot"
test -f "${BIN}"
file "${BIN}" | grep -E 'ELF.*(aarch64|ARM aarch64)'

# Salin sebagai libproot.so — Android membundel semua .so di jniLibs dir.
mkdir -p "${OUT_DIR}"
cp "${BIN}" "${OUT_DIR}/libproot.so"
chmod +x "${OUT_DIR}/libproot.so"

echo "OK: $(ls -la "${OUT_DIR}/libproot.so")"
