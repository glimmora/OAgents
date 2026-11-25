#!/usr/bin/env bash
# ci_rootfs_cache.sh — helper cache rootfs Alpine untuk CI (job e2e).
# Membaca ROOTFS_URL + ROOTFS_SHA256_URL dari env/env.lock, mengunduh ke
# ~/.cache/oagents dengan resume (curl -C -), lalu memverifikasi sha256
# terhadap berkas .sha256 (format Alpine: "HASH  filename").
# Exit 1 bila mismatch. Saat ini hanya helper cache — e2e v0.1.0 memakai
# bridge palsu (E2E_FAKE_BRIDGE=true) tanpa rootfs asli.
set -euo pipefail

LOCK_FILE="${LOCK_FILE:-$(dirname "$(readlink -f "$0")")/../env/env.lock}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/oagents}"
CURL_FLAGS="${CURL_FLAGS:---fL --retry 3 --connect-timeout 15}"

mkdir -p "${CACHE_DIR}"

# Ambil variabel dari env.lock (hanya baris VAR=... di awal kolom).
get_lock_var() {
    grep -E "^${1}=" "${LOCK_FILE}" | head -n1 | cut -d= -f2- | tr -d '\r'
}

ROOTFS_URL="$(get_lock_var ROOTFS_URL)"
ROOTFS_SHA256_URL="$(get_lock_var ROOTFS_SHA256_URL)"

if [ -z "${ROOTFS_URL}" ] || [ -z "${ROOTFS_SHA256_URL}" ]; then
    echo "ERROR: ROOTFS_URL / ROOTFS_SHA256_URL tidak ditemukan di ${LOCK_FILE}" >&2
    exit 1
fi

ROOTFS_FILE="$(basename "${ROOTFS_URL}")"
SHA_FILE="$(basename "${ROOTFS_SHA256_URL}")"

echo "== ci_rootfs_cache =="
echo "URL     : ${ROOTFS_URL}"
echo "SHA URL : ${ROOTFS_SHA256_URL}"
echo "Cache   : ${CACHE_DIR}/${ROOTFS_FILE}"

# Unduh berkas sha256 (kecil, selalu segar) dan rootfs dengan resume.
curl ${CURL_FLAGS} -o "${CACHE_DIR}/${SHA_FILE}" "${ROOTFS_SHA256_URL}"
curl ${CURL_FLAGS} -C - -o "${CACHE_DIR}/${ROOTFS_FILE}" "${ROOTFS_URL}"

# Format berkas .sha256 Alpine: "HASH  filename" (dua spasi).
EXPECTED_HASH="$(awk '{print $1}' "${CACHE_DIR}/${SHA_FILE}" | tr -d '\r\n')"
if ! echo "${EXPECTED_HASH}" | grep -qE '^[0-9a-fA-F]{64}$'; then
    echo "ERROR: hash dari ${SHA_FILE} tidak valid: '${EXPECTED_HASH}'" >&2
    exit 1
fi

ACTUAL_HASH="$(sha256sum "${CACHE_DIR}/${ROOTFS_FILE}" | awk '{print $1}')"

echo "Expected: ${EXPECTED_HASH}"
echo "Actual  : ${ACTUAL_HASH}"

if [ "${EXPECTED_HASH,,}" != "${ACTUAL_HASH,,}" ]; then
    echo "ERROR: sha256 MISMATCH — berkas rusak, hapus dan unduh ulang." >&2
    rm -f "${CACHE_DIR}/${ROOTFS_FILE}"
    exit 1
fi

echo "OK: rootfs ter-cache dan terverifikasi di ${CACHE_DIR}/${ROOTFS_FILE}"
