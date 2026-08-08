# Shizuku loads this service from the APK in a separate app_process. R8 cannot
# discover that reflective entry point from bindUserService().
-keep class com.apkmesh.apk_mesh.ShizukuInstallerService { *; }
-keep interface com.apkmesh.apk_mesh.IShizukuInstaller { *; }
-keep class com.apkmesh.apk_mesh.IShizukuInstaller$* { *; }
