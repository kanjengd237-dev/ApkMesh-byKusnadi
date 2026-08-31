#!/bin/bash

# Hentikan skrip jika terjadi error pada salah satu perintah
set -e

echo "----------------------------------------"
echo "🚀 FLUTTER AUTO-BUILD & DEPLOY SCRIPT"
echo "----------------------------------------"

# 1. Cek apakah ada perubahan file di Git
if [ -z "$(git status --porcelain)" ]; then
  echo "⚠️ Tidak ada perubahan kode yang terdeteksi di proyek ini!"
  exit 0
fi

# 2. Minta input pesan commit dari pengguna
if [ -z "$1" ]; then
  read -p "📝 Masukkan pesan commit (contoh: feat: tambah halaman login): " COMMIT_MSG
  if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG="feat: update source code dan UI aplikasi"
  fi
else
  COMMIT_MSG="$1"
fi

echo ""
echo "📦 [1/4] Menandai & Mengunci Perubahan Kode (Git Commit)..."
git add .
git commit -m "$COMMIT_MSG"

echo ""
echo "🌐 [2/4] Mengunggah Kode ke GitHub (Git Push)..."
git push

echo ""
echo "⏳ [3/4] Memantau Proses Build di GitHub Actions (Live Log)..."
# Mengambil ID run terbaru yang baru saja dipicu oleh git push
sleep 3
RUN_ID=$(gh run list --workflow=flutter_ci.yml --limit 1 --json databaseId -q '.[0].databaseId')

if [ -n "$RUN_ID" ]; then
  gh run watch "$RUN_ID"
else
  echo "⚠️ Tidak dapat mendeteksi ID run, menjalankan 'gh run watch' standar..."
  gh run watch
fi

echo ""
echo "📥 [4/4] Mengunduh File APK Hasil Build Terbaru..."
# Memastikan folder output tersedia
mkdir -p builds

# Mengunduh artifact app-debug ke folder 'builds'
if gh run download -n app-debug -D builds 2>/dev/null; then
  echo "----------------------------------------"
  echo "🎉 SELESAI 100%! APK berhasil disimpan di:"
  ls -lh builds/app-debug.apk 2>/dev/null || ls -lh builds/
  echo "----------------------------------------"
else
  echo "⚠️ Gagal mengunduh artifact otomatis. Anda dapat mendownloadnya manual via 'gh run download'."
fi
