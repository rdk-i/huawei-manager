#!/bin/bash
# Automatisasi Build Huawei Manager di WSL
# Simpan file ini di E:\xProject\Huawei Manager\huawei-manager\build.sh

# Konfigurasi Path
SDK_PATH="$HOME/openwrt-build/sdk"
PROJECT_PATH="/mnt/e/xProject/Huawei Manager/huawei-manager"
PACKAGE_NAME="huawei-manager"

echo "========================================"
echo "   Mulai Build Otomatis Huawei Manager"
echo "========================================"

# Masuk ke SDK
cd $SDK_PATH || { echo "Gagal masuk ke SDK Path: $SDK_PATH"; exit 1; }

# 1. Bersihkan package lama
echo "[1/4] Membersihkan package lama..."
rm -rf package/$PACKAGE_NAME
make package/$PACKAGE_NAME/clean >/dev/null 2>&1

# 2. Copy source code baru
echo "[2/4] Meng-copy source code terbaru..."
# Struktur flat: Makefile, files/, luasrc/ ada di root PROJECT_PATH
mkdir -p package/$PACKAGE_NAME
cp "$PROJECT_PATH/Makefile" package/$PACKAGE_NAME/
cp -r "$PROJECT_PATH/files" package/$PACKAGE_NAME/
cp -r "$PROJECT_PATH/luasrc" package/$PACKAGE_NAME/

# Fix line endings for ALL files (CRITICAL for WSL/Windows)
echo "      Memperbaiki line endings..."
find package/$PACKAGE_NAME -type f -exec sed -i 's/\r$//' {} +

# Refresh package list
echo "      Me-refresh definisi package..."
make defconfig >/dev/null 2>&1

# 3. Build Package
echo "[3/4] Sedang mem-build package (tunggu sebentar)..."
make package/$PACKAGE_NAME/compile V=s > build.log 2>&1

if [ $? -eq 0 ]; then
    echo "      Build BERHASIL!"
else
    echo "      Build GAGAL! Cek build.log untuk detail."
    tail -n 20 build.log
    exit 1
fi

# 4. Copy hasil ke Windows
echo "[4/4] Mengambil file .ipk..."
IPK_FILE=$(find bin/packages -name "${PACKAGE_NAME}*.ipk" | head -n 1)

if [ -n "$IPK_FILE" ]; then
    # Buat folder release jika belum ada
    mkdir -p "$PROJECT_PATH/release"
    cp "$IPK_FILE" "$PROJECT_PATH/release/"
    echo ""
    echo "SUKSES! File .ipk telah disalin ke:"
    echo "$PROJECT_PATH/release/$(basename "$IPK_FILE")"
else
    echo "Gagal menemukan file .ipk hasil build."
    exit 1
fi

echo "========================================"
echo ""
echo "Untuk install di OpenWrt:"
echo "  scp ${PACKAGE_NAME}_*.ipk root@router:/tmp/"
echo "  ssh root@router"
echo "  opkg update"
echo "  opkg install python3 python3-pip"
echo "  opkg install /tmp/${PACKAGE_NAME}_*.ipk"
