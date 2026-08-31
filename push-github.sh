#!/bin/bash

# Konfigurasi User & Repo
GITHUB_USER="kanjengd237-dev"
REPO_NAME="ApkMesh-byKusnadi"
IS_PRIVATE=false

# Cek apakah GITHUB_TOKEN ada di environment terminal
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN belum di-set di terminal!"
    echo "👉 Jalankan perintah ini dulu di terminal Anda:"
    echo "   export GITHUB_TOKEN='ghp_TOKEN_BARU_ANDA'"
    exit 1
fi

echo "🚀 [1/4] Membuat File Workflow GitHub Actions..."
mkdir -p .github/workflows

cat << 'EOF' > .github/workflows/flutter_ci.yml
name: Flutter CI

on:
  push:
    branches: [ main, master ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
      - run: flutter pub get
      - run: flutter build apk --debug
      - uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: build/app/outputs/flutter-apk/app-debug.apk
EOF

# Otomatis menambahkan file skrip dan file sensitif ke .gitignore
echo "🔒 Memastikan file sensitif tidak ter-commit ke Git..."
echo "push-github.sh" >> .gitignore
echo "*.jks" >> .gitignore
echo "key.properties" >> .gitignore
sort -u .gitignore -o .gitignore

echo "🌐 [2/4] Membuat Repository via GitHub API..."
curl -s -H "Authorization: token $GITHUB_TOKEN" \
     -d "{\"name\":\"$REPO_NAME\", \"private\":$IS_PRIVATE}" \
     https://api.github.com/user/repos > /dev/null

echo "📦 [3/4] Melakukan Commit dan Push..."
git init
git branch -M main
git add .
git commit -m "feat: initial commit with github action workflow"

# Menggunakan token secara aman tanpa menyimpan di file repository
REMOTE_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"

git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
git push -u origin main

echo "✨ Sukses! Aplikasi dan Workflow CI/CD berhasil dipush."
