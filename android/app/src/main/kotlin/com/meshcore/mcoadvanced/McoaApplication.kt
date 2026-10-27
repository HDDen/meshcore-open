package com.meshcore.mcoadvanced

import android.app.Application

class McoaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CpuPolicyRuntime.install(this)
    }
}
