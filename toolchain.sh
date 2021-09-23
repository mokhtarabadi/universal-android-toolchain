#!/bin/bash

# get android sdk path
SDK=$HOME/Android/Sdk
[ -n "$ANDROID_SDK_HOME" ] && SDK="$ANDROID_SDK_HOME"

if [ ! -d "$SDK" ]; then
      echo -e "No Android SDK found\nTry set ANDROID_SDK_HOME environment variable"
      exit 1
fi

# get android ndk path
NDK=$SDK/ndk/21.4.7075529
[ -n "$ANDROID_NDK_HOME" ] && NDK="$ANDROID_NDK_HOME"

if [ ! -d "$NDK" ]; then
      echo -e "No Android NDK found\nTry to set ANDROID_NDK_HOME environment variable"
      exit 1
fi

# get pre-installed ndk cmake
CMAKE=$SDK/cmake/3.10.2.4988404
[ -n "$ANDROID_CMAKE_HOME" ] && CMAKE="$ANDROID_CMAKE_HOME"

if [ ! -d "$CMAKE" ]; then
      echo "Please install cmake from Android SDK manager or set ANDROID_CMAKE_HOME environment variable"
      exit 1
fi

# get host
HOST=$(tr "[:upper:]" "[:lower:]" <<<"$(uname -s)-$(uname -m)")

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST"

show_help() {
      echo -e "Usage: $0 [arm] [api]\narm is mandatory and must be one of arm, arm64, x86, x64\napi is optinal and default is 28"
}

if [ -z "${1+x}" ]; then
      show_help
      exit 1
fi

# get api level
API=28
if [ -n "$2" ]; then
      API=$2
fi

# need use shared lib++
SHARED=OFF
if [ -n "$ANDROID_USE_SHARED_LIBC" ]; then
      SHARED=$ANDROID_USE_SHARED_LIBC
fi

case $1 in
arm)
      TRIPLE=arm-linux-androideabi
      ABI=armeabi-v7a
      ;;

arm64)
      TRIPLE=aarch64-linux-android
      ABI=arm64-v8a
      ;;

x86)
      TRIPLE=i686-linux-android
      ABI=x86
      ;;

x64)
      TRIPLE=x86_64-linux-android
      ABI=x86_64
      ;;

*)
      echo -e "Unsupported architecture: $1\n"
      show_help
      exit 1
      ;;
esac

TARGET=$TRIPLE
if [ "$1" == "arm" ]; then
      TARGET=armv7a-linux-androideabi
fi

CURRENT_DIR=$(pwd)
THIRDPARTY=$CURRENT_DIR/3rd-party
SYSROOT=$CURRENT_DIR/sysroot/$ABI
OUTPUT_DIR=$CURRENT_DIR/output/$ABI

# create needed directories
[ ! -d "$THIRDPARTY" ] && mkdir "$THIRDPARTY"
[ ! -d "$SYSROOT" ] && mkdir -p "$SYSROOT/"{lib,include}
[ ! -d "$OUTPUT_DIR" ] && mkdir -p "$OUTPUT_DIR"

export_autoconf_variables() {
      export AR=$TOOLCHAIN/bin/llvm-ar
      export CC=$TOOLCHAIN/bin/$TARGET$API-clang
      export AS=$CC
      export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
      export LD=$TOOLCHAIN/bin/ld
      export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
      export STRIP=$TOOLCHAIN/bin/llvm-strip

      export CFLAGS="$CFLAGS -std=gnu11"
      export CXXFLAGS="$CXXFLAGS -std=c++11"

      if [ "$SHARED" == "ON" ]; then
            export LDFLAGS="-c++_shared"
      else
            export LDFLAGS="-static-libstdc++"
      fi
}

android_make_command() {
      make \
            CC=$CC \
            CXX=$CXX \
            LD=$LD \
            AS=$AS \
            STRIP=$STRIP \
            AR=$AR \
            RANLIB=$RANLIB \
            "$@"
}

# base autoconf command for cross-compile for android
android_autoconf_command() {
      ./configure \
            --host $TARGET \
            "$@"
}

# base cmake command for android
android_cmake_command() {
      PARAMS=(
            "-DCMAKE_BUILD_TYPE=Release"
            "-DCMAKE_CXX_FLAGS=$CXXFLAGS"
            "-DCMAKE_C_FLAGS=$CFLAGS"
            "-DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake"
            "-DANDROID_ABI=$ABI"
            "-DANDROID_NDK=$NDK"
            "-DANDROID_PLATFORM=android-$API"
            "-DCMAKE_ANDROID_ARCH_ABI=$ABI"
            "-DCMAKE_ANDROID_NDK=$NDK"
            "-DCMAKE_FIND_ROOT_PATH=$SYSROOT"
            "-DCMAKE_MAKE_PROGRAM=$CMAKE/bin/ninja"
            "-DCMAKE_SYSTEM_NAME=Android"
            "-DCMAKE_SYSTEM_VERSION=$API"
            "-GNinja"
      )

      if [ "$SHARED" == "ON" ]; then
            PARAMS+=(
                  "-DANDROID_STL=c++_shared"
            )
      else
            PARAMS+=(
                  "-DANDROID_STL=c++_static"
            )
      fi

      "$CMAKE"/bin/cmake "${PARAMS[@]}" "$@"
}

# use cmake version of openssl for easy integration with android_cmake_command
build_openssl() {
      # download
      cd "$THIRDPARTY" || return
      if [ ! -d openssl-cmake-1.1.1k-20210430 ]; then
            curl -L -O https://github.com/janbar/openssl-cmake/archive/refs/tags/1.1.1k-20210430.tar.gz
            tar -xvf 1.1.1k-20210430.tar.gz
      fi
      cd openssl-cmake-1.1.1k-20210430 || return

      # clean
      rm -rf build && mkdir build
      cd build || return

      # build
      android_cmake_command \
            -DDSO_NONE=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DWITH_APPS=OFF \
            ..

      "$CMAKE/bin/cmake" --build . --config Release

      # install
      cp crypto/libcrypto_1_1.a "$SYSROOT/lib/libcrypto.a"
      cp ssl/libssl_1_1.a "$SYSROOT/lib/libssl.a"
      cp -r include/openssl "$SYSROOT/include"

      cd $CURRENT_DIR
}

build_mbedtls() {
      # download
      cd "$THIRDPARTY" || return
      if [ ! -d mbedtls-2.26.0 ]; then
            curl -L -O https://github.com/ARMmbed/mbedtls/archive/refs/tags/v2.26.0.tar.gz
            tar -xvf v2.26.0.tar.gz
      fi
      cd mbedtls-2.26.0 || return

      # clean
      rm -rf build && mkdir build
      cd build || return

      # build
      android_cmake_command \
            -DENABLE_ZLIB_SUPPORT=ON \
            -DENABLE_TESTING=OFF \
            -DENABLE_PROGRAMS=OFF \
            -DLINK_WITH_PTHREAD=OFF \
            -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
            -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
            ..

      "$CMAKE/bin/cmake" --build . --config Release

      # install
      cp library/{libmbedcrypto,libmbedtls,libmbedx509}.a "$SYSROOT/lib"
      cd ..
      cp -r include/mbedtls "$SYSROOT/include"

      cd $CURRENT_DIR
}

# build libevent with openssl/mbedtls support[openssl=ON, mbedtls=ON]
build_libevent() {
      # build parameters
      PARAMS=(
            "-DEVENT__DISABLE_SAMPLES=ON"
            "-DEVENT__DISABLE_TESTS=ON"
            "-DEVENT__DOXYGEN=OFF"
            "-DEVENT__LIBRARY_TYPE=STATIC"
            "-DEVENT__DISABLE_BENCHMARK=ON"
            "-DEVENT__DISABLE_THREAD_SUPPORT=ON"
      )

      # check need build mbedtls or openssl support
      if [ "$1" == "ON" ]; then
            echo "Build openssl"
            build_openssl
            PARAMS+=(
                  "-DEVENT__DISABLE_OPENSSL=OFF"
            )
      else
            PARAMS+=(
                  "-DEVENT__DISABLE_OPENSSL=ON"
            )
      fi

      if [ "$2" == "ON" ]; then
            echo "Build mbedtls"
            build_mbedtls
            PARAMS+=(
                  "-DEVENT__DISABLE_MBEDTLS=OFF"
                  "-DMBEDTLS_USE_STATIC_LIBS=ON"
            )
      else
            PARAMS+=(
                  "-DEVENT__DISABLE_MBEDTLS=ON"
            )
      fi

      # download
      cd "$THIRDPARTY" || return
      if [ ! -d libevent-master ]; then
            curl -L https://github.com/libevent/libevent/archive/refs/heads/master.zip -o libevent.zip
            unzip libevent.zip
      fi
      cd libevent-master || return

      # clean
      rm -rf build && mkdir build
      cd build || return

      android_cmake_command "${PARAMS[@]}" ..

      "$CMAKE/bin/cmake" --build . --config Release

      # install
      cp lib/*.a "$SYSROOT/lib"
      cp -r include/* "$SYSROOT/include"
      cd ..
      cp -r include/* "$SYSROOT/include"

      cd $CURRENT_DIR
}

export_autoconf_variables
