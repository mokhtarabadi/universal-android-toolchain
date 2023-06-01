# What is this?

A bash script to build most C/C++ projects for Android using NDK (dynamically or statically)

# How to use it?

Install Android SDK and NDK(25.2.9519653) with cmake componenet (prefer install them into default location `$HOME/Android/Sdk`) if you havent

If you installed Android SDK to different path, need set below environment variables:\
`ANDROID_SDK_HOME` to installtion Android SDK path\
`ANDROID_NDK_HOME` to Android NDK path (if not setted, script trying to detect NDK from `ANDROID_SDK_HOME`)\
`ANDROID_CMAKE_HOME` to Android cmake path (install from Android SDK manager, if not setted, script trying to detect it from `ANDROID_SDK_HOME`)

Then source `./toolchain.sh arch api_level` script in begainning of your build script to building projects for Android\
`arch` is one of arm, arm64, x86, x64\
`api_level` default is 28 if not specified

Toolchain have some pre-defined methods for building some libraries:\
OpenSSL = call `build_openssl`\
mbedtls = call `build_mbedtls`\
libevent = call `build_libevent` with 2 optinal arguments `openssl_support` [ON/OFF] and `mbedtls_support` [ON/OFF]

After sourcing, you can call below methods to build projects\
`android_make_command` to build project with `make` command, useful for projects did'nt support autoconf or cmake\
`android_autoconf_command` to build autoconf projects\
`android_cmake_command` to build cmake project

All the above methods can be called with extra arguemtns like `android_cmake_command -DCMAKE_XXX=OFF -DCMAKE_TEST=ON`

For example go to stunnel folder and run `./build.sh arm64 21` to build most recent version of stunnel for Android after the process is completed you can see the `libstunnel.so` in `output/arm64-v8a` directory

See [stunnel](./stunnel)

# Notes

If you want to include more than one shared libraries in your Android project, you prefer to use shared libc++ instead static one by set `ANDROID_USE_SHARED_LIBC=ON` environment variable before sourcing `toolchain.sh` and alse add `-DANDROID_STL=c++_shared` to cmake arguments in `build.gradle` file of app module.

Enjoy!
