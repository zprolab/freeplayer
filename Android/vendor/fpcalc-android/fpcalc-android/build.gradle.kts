plugins {
    id("com.android.library")
}

android {
    namespace = "com.geecko.fpcalc"
    compileSdk {
        version = release(37)
    }
    defaultConfig {
        minSdk = 24
        externalNativeBuild {
            cmake {
                cppFlags += "-DANDROID_ARM_NEON=TRUE -std=c++11 -frtti -fexceptions"
            }
        }
        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }
    }
    buildTypes {
        release {}
        debug {}
    }
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
