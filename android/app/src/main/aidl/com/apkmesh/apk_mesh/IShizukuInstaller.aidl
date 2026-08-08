package com.apkmesh.apk_mesh;

import android.os.ParcelFileDescriptor;

interface IShizukuInstaller {
    String install(in ParcelFileDescriptor apk, long size) = 1;

    void destroy() = 16777114;
}
