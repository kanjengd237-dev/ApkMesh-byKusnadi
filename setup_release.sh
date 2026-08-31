#!/bin/bash
set -e

echo "🔑 [1/3] Memasang GitHub Secrets secara otomatis..."
gh secret set KEYSTORE_PASSWORD -b"ApkMeshSecret123!"
gh secret set KEY_ALIAS -b"upload"
gh secret set KEY_PASSWORD -b"ApkMeshSecret123!"

# Membuat Keystore baru & memasukkannya langsung ke Secrets
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload -dname "CN=Kusnadi, OU=Dev, O=ApkMesh, L=Jakarta, ST=Jakarta, C=ID" -storepass "ApkMeshSecret123!" -keypass "ApkMeshSecret123!"
gh secret set KEYSTORE_BASE64 -b"$(base64 -w 0 upload-keystore.jks)"
rm -f upload-keystore.jks

echo "✅ GitHub Secrets berhasil dikonfigurasi!"

echo "📝 [2/3] Memperbarui .github/workflows/flutter_ci.yml..."
mkdir -p .github/workflows

cat << 'EOF' > .github/workflows/flutter_ci.yml
name: Flutter Release Build

on:
  push:
    branches: [ main, master ]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v5
        with:
          distribution: 'zulu'
          java-version: '17'

      - name: Setup Flutter SDK
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - name: Decode Android Keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/upload-keystore.jks

      - name: Create key.properties
        run: |
          cat <<EOP > android/key.properties
          storePassword=${{ secrets.KEYSTORE_PASSWORD }}
          keyPassword=${{ secrets.KEY_PASSWORD }}
          keyAlias=${{ secrets.KEY_ALIAS }}
          storeFile=upload-keystore.jks
          EOP

      - name: Install Dependencies
        run: flutter pub get

      - name: Build Release APK
        run: flutter build apk --release

      - name: Clean Sensitive Secrets
        if: always()
        run: |
          rm -f android/app/upload-keystore.jks
          rm -f android/key.properties

      - name: Upload Release APK Artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: build/app/outputs/flutter-apk/app-release.apk
EOF

echo "📝 [3/3] Memperbarui builder.sh untuk Release Mode..."
cat << 'EOF' > builder.sh
#!/bin/bash
set -e

echo "----------------------------------------"
echo "🚀 FLUTTER AUTO-BUILD RELEASE SCRIPT"
echo "----------------------------------------"

if [ -z "$(git status --porcelain)" ]; then
  echo "⚠️ Tidak ada perubahan kode yang terdeteksi!"
  exit 0
fi

if [ -z "$1" ]; then
  read -p "📝 Masukkan pesan commit: " COMMIT_MSG
  if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG="feat: update release build"
  fi
else
  COMMIT_MSG="$1"
fi

git add .
git commit -m "$COMMIT_MSG"
git push

echo "⏳ Memantau proses Release Build di GitHub Actions..."
sleep 3
RUN_ID=$(gh run list --workflow=flutter_ci.yml --limit 1 --json databaseId -q '.[0].databaseId')

if [ -n "$RUN_ID" ]; then
  gh run watch "$RUN_ID"
else
  gh run watch
fi

echo "📥 Mengunduh Release APK..."
mkdir -p builds
if gh run download -n app-release -D builds 2>/dev/null; then
  echo "----------------------------------------"
  echo "🎉 SELESAI 100%! Release APK berhasil disimpan di:"
  ls -lh builds/app-release.apk 2>/dev/null || ls -lh builds/
  echo "----------------------------------------"
else
  echo "⚠️ Gagal mengunduh artifact otomatis."
fi
EOF

chmod +x builder.sh
echo "✨ SETUP SELESAI!"
