#!/bin/bash

# get android sdk path
SDK=$HOME/Android/Sdk
[ -n "$ANDROID_SDK_HOME" ] && SDK="$ANDROID_SDK_HOME"

if [ ! -d "$SDK" ]; then
      echo -e "No Android SDK found\nTry set ANDROID_SDK_HOME environment variable"
      exit 1
fi

# get android ndk path
NDK=$SDK/ndk/25.2.9519653
[ -n "$ANDROID_NDK_HOME" ] && NDK="$ANDROID_NDK_HOME"

if [ ! -d "$NDK" ]; then
      echo -e "No Android NDK found\nTry to set ANDROID_NDK_HOME environment variable"
      exit 1
fi

# get pre-installed ndk cmake
CMAKE=$SDK/cmake/3.22.1
[ -n "$ANDROID_CMAKE_HOME" ] && CMAKE="$ANDROID_CMAKE_HOME"

if [ ! -d "$CMAKE" ]; then
      echo "Please install cmake from Android SDK manager or set ANDROID_CMAKE_HOME environment variable"
      exit 1
fi

# need to openssl
export ANDROID_NDK_ROOT=$NDK

# get build triple
BUILD_TRIPLE="$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')-gnu"

# get host
HOST=$(tr "[:upper:]" "[:lower:]" <<<"$(uname -s)-$(uname -m)")

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST"

show_help() {
      cat <<EOF
Usage: $0 arch [api]
  arch      The architecture to build for (arm, arm64, x86, x64)
  api       The Android API level to target (default: 28)
EOF
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

ARCH=$1

TARGET=$TRIPLE
if [ "$1" == "arm" ]; then
      TARGET=armv7a-linux-androideabi
fi

# change current directory
CURRENT_DIR=$(pwd)
if [ -n "$WORKING_DIRECTORY" ]; then
      CURRENT_DIR=$WORKING_DIRECTORY
fi

THIRDPARTY=$CURRENT_DIR/3rd-party
SYSROOT=$CURRENT_DIR/sysroot/$ABI
OUTPUT_DIR=$CURRENT_DIR/output/$ABI

# create needed directories
[ ! -d "$THIRDPARTY" ] && mkdir -p "$THIRDPARTY"
[ ! -d "$SYSROOT" ] && mkdir -p "$SYSROOT/usr/"{lib,include}
[ ! -d "$OUTPUT_DIR" ] && mkdir -p "$OUTPUT_DIR"

# export toolchain to path
export PATH="$TOOLCHAIN/bin:$PATH"

function export_autoconf_variables() {
      export DESTDIR="$SYSROOT"

      export AR=$TOOLCHAIN/bin/llvm-ar
      export CC=$TOOLCHAIN/bin/$TARGET$API-clang
      export AS=$CC
      export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
      export LD=$TOOLCHAIN/bin/$TRIPLE-ld
      export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
      export STRIP=$TOOLCHAIN/bin/llvm-strip

      export CFLAGS="$CFLAGS -std=gnu11"
      export CXXFLAGS="$CXXFLAGS -std=c++11"

      if [ "$SHARED" == "OFF" ]; then
            export LDFLAGS="$LDFLAGS -static-libstdc++"
      fi

      export CFLAGS="$CFLAGS --sysroot=$TOOLCHAIN/sysroot -I$TOOLCHAIN/sysroot/usr/include"
      export CXXFLAGS="$CXXFLAGS --sysroot=$TOOLCHAIN/sysroot"
      export LDFLAGS="$LDFLAGS --sysroot=$TOOLCHAIN/sysroot -L$TOOLCHAIN/sysroot/usr/lib"
}

function android_make_command() {
      make \
            CC="$CC" \
            CXX="$CXX" \
            LD="$LD" \
            AS="$AS" \
            STRIP="$STRIP" \
            AR="$AR" \
            RANLIB="$RANLIB" \
            DESTDIR="$DESTDIR" \
            "$@"
}

# base autoconf command for cross-compile for android
function android_autoconf_command() {
      local configure_path="$1"
      shift

      "$configure_path"/configure \
            --host "$TARGET" \
            --build "$BUILD_TRIPLE" \
            --prefix "/usr" \
            "$@"
}

# base cmake command for android
function android_cmake_command() {
      local PARAMS=(
            "-DCMAKE_BUILD_TYPE=Release"
            "-DCMAKE_C_COMPILER=$CC"
            "-DCMAKE_CXX_COMPILER=$CXX"
            "-DCMAKE_CXX_FLAGS=$CXXFLAGS"
            "-DCMAKE_C_FLAGS=$CFLAGS"
            "-DCMAKE_EXE_LINKER_FLAGS=$LDFLAGS"
            "-DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake"
            "-DANDROID_ABI=$ABI"
            "-DANDROID_NDK=$NDK"
            "-DANDROID_PLATFORM=android-$API"
            "-DCMAKE_ANDROID_ARCH_ABI=$ABI"
            "-DCMAKE_ANDROID_NDK=$NDK"
            "-DCMAKE_FIND_ROOT_PATH=$TOOLCHAIN/sysroot"
            "-DCMAKE_MAKE_PROGRAM=$CMAKE/bin/ninja"
            "-DCMAKE_SYSTEM_NAME=Android"
            "-DCMAKE_SYSTEM_VERSION=$API"
            "-DCMAKE_INSTALL_PREFIX=/usr"
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
function build_openssl() {
      # download
      cd "$THIRDPARTY" || return

      if [ ! -d "openssl-3.1.1" ]; then
            curl -L -O https://github.com/openssl/openssl/releases/download/openssl-3.1.1/openssl-3.1.1.tar.gz
            tar -xvf openssl-3.1.1.tar.gz
      fi
      cd openssl-3.1.1 || return

      # clean
      rm -rf build && mkdir build
      cd build || return

      OPENSSL_CONFIG_TYPE="android-"

      # switch $ARCH with arm arm64 x86 x64
      case $ARCH in
      arm)
            OPENSSL_CONFIG_TYPE+="armeabi"
            ;;
      arm64)
            OPENSSL_CONFIG_TYPE+="arm64"
            ;;
      x86)
            OPENSSL_CONFIG_TYPE+="x86"
            ;;
      x64)
            OPENSSL_CONFIG_TYPE+="x86_64"
            ;;
      esac

      # configure
      ../Configure --prefix=/usr $OPENSSL_CONFIG_TYPE no-asm no-shared no-ssl2 no-ssl3 no-comp no-hw no-engine

      # build and install
      android_make_command -j9
      android_make_command -j9 install_sw

      cd "$CURRENT_DIR" || exit 1
}

function build_mbedtls() {
      # download
      cd "$THIRDPARTY" || return

      if [ ! -d mbedtls-3.4.0 ]; then
            curl -L -O https://github.com/ARMmbed/mbedtls/archive/refs/tags/v3.4.0.tar.gz
            tar -xvf v3.4.0.tar.gz
      fi
      cd mbedtls-3.4.0 || return

      # clean
      rm -rf build && mkdir build
      cd build || return

      local PARAMS=(
            "-DENABLE_ZLIB_SUPPORT=ON"
            "-DENABLE_TESTING=OFF"
            "-DENABLE_PROGRAMS=OFF"
            "-DLINK_WITH_PTHREAD=OFF"
      )

      if [ "$SHARED" == "ON" ]; then
            PARAMS+=(
                  "-DUSE_SHARED_MBEDTLS_LIBRARY=ON"
                  "-DUSE_STATIC_MBEDTLS_LIBRARY=OFF"
            )
      else
            PARAMS+=(
                  "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF"
                  "-DUSE_STATIC_MBEDTLS_LIBRARY=ON"
            )
      fi

      # build
      android_cmake_command "${PARAMS[@]}" ..

      "$CMAKE/bin/cmake" --build . --config Release

      # install
      "$CMAKE/bin/cmake" --build . --target install

      cd "$CURRENT_DIR" || exit 1
}

# build libevent with openssl/mbedtls support[openssl=ON, mbedtls=ON]
function build_libevent() {
      # check need build mbedtls or openssl support
      if [ "$1" == "ON" ]; then
            echo "Build openssl"
            build_openssl
      fi

      if [ "$2" == "ON" ]; then
            echo "Build mbedtls"
            build_mbedtls
      fi

      # download
      cd "$THIRDPARTY" || return

      if [ ! -d libevent-028385f685585b4b247bdd4acae3cd12de2b4da4 ]; then
            curl -L https://github.com/libevent/libevent/archive/028385f685585b4b247bdd4acae3cd12de2b4da4.zip -o libevent.zip
            unzip libevent.zip
      fi
      cd libevent-028385f685585b4b247bdd4acae3cd12de2b4da4 || return

      # clean
      rm -rf build && mkdir build
      cd build || return

      # build
      local PARAMS=(
            "-DEVENT__DISABLE_SAMPLES=ON"
            "-DEVENT__DISABLE_TESTS=ON"
            "-DEVENT__DOXYGEN=OFF"
            "-DEVENT__DISABLE_BENCHMARK=ON"
            "-DEVENT__DISABLE_THREAD_SUPPORT=ON"
      )

      local LIB_POSTFIX=""
      if [ "$SHARED" == "ON" ]; then
            PARAMS+=(
                  "-DEVENT__LIBRARY_TYPE=SHARED"

            )
            LIB_POSTFIX=".so"
      else
            PARAMS+=(
                  "-DEVENT__LIBRARY_TYPE=STATIC"

            )
            LIB_POSTFIX=".a"
      fi

      if [ "$1" == "ON" ]; then
            PARAMS+=(
                  "-DEVENT__DISABLE_OPENSSL=OFF"
                  "-DOPENSSL_INCLUDE_DIR=$SYSROOT/usr/include"
                  "-DOPENSSL_ROOT_DIR=$SYSROOT/usr"
                  "-DOPENSSL_CRYPTO_LIBRARY=$SYSROOT/usr/lib/libcrypto$LIB_POSTFIX"
                  "-DOPENSSL_SSL_LIBRARY=$SYSROOT/usr/lib/libssl$LIB_POSTFIX"
            )
      else
            PARAMS+=(
                  "-DEVENT__DISABLE_OPENSSL=ON"
            )
      fi

      if [ "$2" == "ON" ]; then
            PARAMS+=(
                  "-DEVENT__DISABLE_MBEDTLS=OFF"
                  "-DMBEDTLS_INCLUDE_DIR=$SYSROOT/usr/include"
                  "-DMBEDTLS_ROOT_DIR=$SYSROOT/usr"
                  "-DMBEDTLS_LIBRARY=$SYSROOT/usr/lib/libmbedtls$LIB_POSTFIX"
                  "-DMBEDTLS_CRYPTO_LIBRARY=$SYSROOT/usr/lib/libmbedcrypto$LIB_POSTFIX"
                  "-DMBEDTLS_X509_LIBRARY=$SYSROOT/usr/lib/libmbedx509$LIB_POSTFIX"
            )
      else
            PARAMS+=(
                  "-DEVENT__DISABLE_MBEDTLS=ON"
            )
      fi

      if [ "$SHARED" == "ON" ] && [ "$2" == "ON" ]; then
            PARAMS+=("-DMBEDTLS_USE_STATIC_LIBS=ON"
            )
      fi

      android_cmake_command "${PARAMS[@]}" ..

      "$CMAKE/bin/cmake" --build . --config Release

      # install
      "$CMAKE/bin/cmake" --build . --target install

      cd "$CURRENT_DIR" || exit 1
}

export_autoconf_variables
