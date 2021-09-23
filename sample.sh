#!/bin/bash

. toolchain.sh "$@" # this will get arm and api from command line options

# first build openssl
build_openssl

# try to build curl for android
wget https://github.com/curl/curl/releases/download/curl-7_79_1/curl-7.79.1.tar.xz
tar -xvf curl-7.79.1.tar.xz
cd curl-7.79.1/

rm -rf build && mkdir build && cd build
android_cmake_command ..
"$CMAKE/bin/cmake" --build . --config Release # CMAKE is set in toolchain script

$STRIP -s lib/libcurl.so -o $OUTPUT_DIR/libcurl.so # STRIP and OUTPUT_DIR is set in toolchain script
