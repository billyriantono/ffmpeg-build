#!/bin/sh -e

#This script will compile and install a static ffmpeg build with support for nvenc un ubuntu.
#See the prefix path and compile options if edits are needed to suit your needs.

# Based on:  https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
# Based on:  https://gist.github.com/Brainiarc7/3f7695ac2a0905b05c5b
# Fix #1 By : Chromafunk : https://github.com/ilyaevseev/ffmpeg-build/commit/d3538fd5ac0063eda4c1887ee9509f36d05e7514
# Rewritten here: https://github.com/ilyaevseev/ffmpeg-build-static/


# Globals
NASM_VERSION="2.14rc15"
YASM_VERSION="1.3.0"
LAME_VERSION="3.100"
OPUS_VERSION="1.2.1"
LASS_VERSION="0.14.0"
WORK_DIR="$HOME/ffmpeg-xc-build-static-sources"
DEST_DIR="$HOME/ffmpeg-xc-build-static-binaries"

mkdir -p "$WORK_DIR" "$DEST_DIR" "$DEST_DIR/bin"

export PATH="$DEST_DIR/bin:$PATH"

MYDIR="$(cd "$(dirname "$0")" && pwd)"  #"

####  Routines  ################################################

Wget() { wget -cN "$@"; }

Make() { make -j$(nproc); make "$@"; }

Clone() {
    local DIR="$(basename "$1" .git)"

    cd "$WORK_DIR/"
    test -d "$DIR/.git" || git clone --depth=1 "$@"

    cd "$DIR"
    git pull
}

PKGS="autoconf automake libtool patch make cmake bzip2 unzip wget git mercurial cmake"

installAptLibs() {
    sudo apt-get update
    sudo apt-get -y --force-yes install $PKGS \
      build-essential pkg-config texi2html software-properties-common \
      libfreetype6-dev libgpac-dev libsdl1.2-dev libtheora-dev libva-dev \
      libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev zlib1g-dev libfribidi-dev \
      gnutls-dev libharfbuzz-dev libxml2-dev
}

installYumLibs() {
    sudo yum -y install $PKGS freetype-devel gcc gcc-c++ pkgconfig zlib-devel \
      libtheora-devel libvorbis-devel libva-devel
}

installLibs() {
    echo "Installing prerequisites"
    . /etc/os-release
    case "$ID" in
        ubuntu | linuxmint ) installAptLibs ;;
        * )                  installYumLibs ;;
    esac
}

installNvidiaSDK() {
    echo "Installing the nVidia NVENC SDK."
    Clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    make
    make install PREFIX="$DEST_DIR"
    patch --force -d "$DEST_DIR" -p1 < "$MYDIR/dynlink_cuda.h.patch" ||
        echo "..SKIP PATCH, POSSIBLY NOT NEEDED. CONTINUED.."
}

compileNasm() {
    echo "Compiling nasm"
    cd "$WORK_DIR/"
    Wget "http://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.gz"
    tar xzvf "nasm-$NASM_VERSION.tar.gz"
    cd "nasm-$NASM_VERSION"
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin"
    Make install distclean
}

compileYasm() {
    echo "Compiling yasm"
    cd "$WORK_DIR/"
    Wget "http://www.tortall.net/projects/yasm/releases/yasm-$YASM_VERSION.tar.gz"
    tar xzvf "yasm-$YASM_VERSION.tar.gz"
    cd "yasm-$YASM_VERSION/"
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin"
    Make install distclean
}

compileLibX264() {
    echo "Compiling libx264"
    cd "$WORK_DIR/"
    Wget https://download.videolan.org/pub/x264/snapshots/x264-snapshot-20191216-2245.tar.bz2
    rm -rf x264-snapshot*/ || :
    tar xjvf x264-snapshot-20191216-2245.tar.bz2
    cd x264-snapshot*
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin" --enable-static --enable-pic
    Make install distclean
}

compileLibX265() {
    if cd "$WORK_DIR/x265/"; then
        hg pull
        hg update
    else
        cd "$WORK_DIR/"
        hg clone https://bitbucket.org/multicoreware/x265
    fi

    cd "$WORK_DIR/x265/build/linux/"
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DENABLE_SHARED:bool=off ../../source
    Make install

    # forward declaration should not be used without struct keyword!
    sed -i.orig -e 's,^ *x265_param\* zoneParam,struct x265_param* zoneParam,' "$DEST_DIR/include/x265.h"
}

compileLibAom() {
    echo "Compiling libaom"
    Clone https://aomedia.googlesource.com/aom
    mkdir ../aom_build
    cd ../aom_build
    which cmake && PROG=cmake || PROG=cmake
    $PROG -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DENABLE_SHARED=off -DENABLE_NASM=on ../aom
    Make install
}

compileLibfdkcc() {
    echo "Compiling libfdk-cc"
    cd "$WORK_DIR/"
    Wget -O fdk-aac.zip https://github.com/mstorsjo/fdk-aac/zipball/master
    unzip -o fdk-aac.zip
    cd mstorsjo-fdk-aac*
    autoreconf -fiv
    ./configure --prefix="$DEST_DIR" --disable-shared
    Make install distclean
}

compileLibMP3Lame() {
    echo "Compiling libmp3lame"
    cd "$WORK_DIR/"
    Wget "http://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
    tar xzvf "lame-$LAME_VERSION.tar.gz"
    cd "lame-$LAME_VERSION"
    ./configure --prefix="$DEST_DIR" --enable-nasm --disable-shared
    Make install distclean
}

compileLibOpus() {
    echo "Compiling libopus"
    cd "$WORK_DIR/"
    Wget "http://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"
    tar xzvf "opus-$OPUS_VERSION.tar.gz"
    cd "opus-$OPUS_VERSION"
    #./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared
    Make install distclean
}

compileLibVpx() {
    echo "Compiling libvpx"
    Clone https://chromium.googlesource.com/webm/libvpx
    ./configure --prefix="$DEST_DIR" --disable-examples --enable-runtime-cpu-detect --enable-vp9 --enable-vp8 \
    --enable-postproc --enable-vp9-postproc --enable-multi-res-encoding --enable-webm-io --enable-better-hw-compatibility \
    --enable-vp9-highbitdepth --enable-onthefly-bitpacking --enable-realtime-only \
    --cpu=native --as=nasm --disable-docs
    Make install clean
}

compileLibAss() {
    echo "Compiling libass"
    cd "$WORK_DIR/"
    Wget "https://github.com/libass/libass/releases/download/$LASS_VERSION/libass-$LASS_VERSION.tar.xz"
    tar Jxvf "libass-$LASS_VERSION.tar.xz"
    cd "libass-$LASS_VERSION"
    autoreconf -fiv
    ./configure --prefix="$DEST_DIR" --disable-shared
    Make install distclean
}

compileLibOgg() {
    echo "Compiling libogg"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/ogg/archive/v1.3.3.tar.gz" -O "libogg.tar.gz"
    tar zxvf "libogg.tar.gz"
    cd "ogg*"
    ./autogen.sh
    ./configure --prefix=$DEST_DIR --disable-shared
    Make install distclean
}

compileLibVorbis() {
    echo "Compiling libvorbis"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/vorbis/archive/v1.3.6.tar.gz" -O "vorbis.tar.gz"
    tar zxvf "vorbis.tar.gz"
    cd "vorbis"
    ./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared
    Make install distclean
}

compileLibRtmp() {
    echo "Compiling librtmp"
    cd "$WORK_DIR/"
    Wget "https://rtmpdump.mplayerhq.hu/download/rtmpdump-2.3.tgz"
    tar zxvf "rtmpdump-2.3.tgz"
    cd "rtmpdump-*"
    cd librtmp
    sed -i "/INC=.*/d" ./Makefile # Remove INC if present from previous run.
    sed -i "s/prefix=.*/prefix=${DEST_DIR}\nINC=-I\$(prefix)\/include/" ./Makefile
    sed -i "s/SHARED=.*/SHARED=no/" ./Makefile
    make install_base
}

compileNvidiaSdk() {
    echo "Compiling nv_sdk"
    cd $DEST_DIR
    wget -c https://s3-us-west-1.amazonaws.com/backups.reticulum-dev-7f8d39c45878ee2e/streaming-deps/Video_Codec_SDK_8.2.16.zip
    unzip Video_Codec_SDK_8.2.16.zip
    sudo cp -vr Video_Codec_SDK_8.2.16/Samples/External/* /usr/include/
    mv Video_Codec_SDK_8.2.16 nv_sdk
}

compileFfmpeg(){
    echo "Compiling ffmpeg"
    Clone https://github.com/XtreamCodes/FFmpeg -b master

    export PATH="$CUDA_DIR/bin:$PATH"  # ..path to nvcc
    PKG_CONFIG_PATH="$DEST_DIR/lib/pkgconfig:$DEST_DIR/lib64/pkgconfig" \
    ./configure \
      --pkg-config-flags="--static" \
      --prefix="$DEST_DIR" \
      --bindir="$DEST_DIR/bin" \
      --extra-cflags="-I $DEST_DIR/include -I $CUDA_DIR/include/ I$DEST_DIR/nv_sdk" \
      --extra-ldflags="-L $DEST_DIR/lib -L $CUDA_DIR/lib64/ -L$DEST_DIR/nv_sdk" \
      --extra-libs="-lpthread" \
      --extra-version="PandawaX" \
      --enable-cuvid \
       --enable-nvenc \
       --enable-ffnvcodec \
      --enable-gpl \
      --enable-libass \
      --enable-libfdk-aac \
      --enable-libfreetype \
      --enable-libmp3lame \
      --enable-libopus \
      --enable-libtheora \
      --enable-libvorbis \
      --enable-libvpx \
      --enable-libx264 \
      --enable-libx265 \
      --enable-nonfree \
      --enable-libaom \
      --enable-nvenc \
      --enable-gnutls \
      --disable-debug \
      --disable-shared \
      --disable-ffplay \
      --disable-doc \
      --enable-librtmp \
      --enable-gpl \
      --enable-pthreads \
      --enable-postproc \
      --enable-version3 \
      --enable-gray \
      --enable-runtime-cpudetect \
      --enable-libfreetype \
      --enable-fontconfig \
      --enable-libfreetype \
      --enable-static \
      --enable-demuxer=dash \
      --enable-libxml2 \
    make install distclean
    hash -r
}

installLibs
installNvidiaSDK

compileNasm
compileYasm
compileLibX264
compileLibX265
compileLibAom
compileLibVpx
compileLibfdkcc
compileLibMP3Lame
compileLibOpus
compileLibAss
compileLibOgg
compileLibVorbis
compileLibRtmp
compileFfmpeg

echo "Complete!"

## END ##
