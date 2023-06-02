#!/bin/bash

export ANDROID_USE_SHARED_LIBC=OFF
WORKING_DIRECTORY="$(pwd)"
export WORKING_DIRECTORY

export API=21

# shellcheck source=../toolchain.sh
. ../toolchain.sh "$@" # this will get arch and api level from command args

# build openssl
build_openssl

# download stunnel source code
if [ ! -d "source/stunnel-5.69" ]; then
    mkdir -p source
    cd source || return
    curl -L -O https://www.stunnel.org/downloads/stunnel-5.69.tar.gz
    tar -xvf stunnel-5.69.tar.gz
    cd ..
fi
cd source/stunnel-5.69 || return

# clean
rm -rf build && mkdir build
cd build || return

# build
android_autoconf_command .. \
    --with-ssl="$SYSROOT/usr" \
    --enable-static \
    --disable-libwrap \
    --disable-systemd \
    --disable-fips \
    --disable-largefile

android_make_command -j9
android_make_command install-exec

# install it
mv "$SYSROOT/usr/bin/stunnel" "$OUTPUT_DIR/libstunnel.so"
$STRIP -s "$OUTPUT_DIR/libstunnel.so"
