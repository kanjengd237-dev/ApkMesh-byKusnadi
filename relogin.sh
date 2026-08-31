#!/bin/bash
set -e

echo "🔐 Memperbarui Otentikasi GitHub CLI..."

# Masukkan Personal Access Token Anda jika diminta
if [ -z "$GITHUB_TOKEN" ]; then
  read -sp "🔑 Tempelkan GitHub Token (PAT) Anda: " USER_TOKEN
  echo ""
  export GH_TOKEN="$USER_TOKEN"
else
  export GH_TOKEN="$GITHUB_TOKEN"
fi

# Login ke GH CLI
echo "$GH_TOKEN" | gh auth login --with-token

echo "✅ Otentikasi Berhasil!"
echo "🚀 Melanjutkan pemantauan build..."
gh run watch
