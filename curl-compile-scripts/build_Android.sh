#!/bin/bash
TARGET=android-22

real_path() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

#Change this env variable to the number of processors you have
if [ -f /proc/cpuinfo ]; then
  JOBS=$(grep flags /proc/cpuinfo |wc -l)
elif [ ! -z $(which sysctl) ]; then
  JOBS=$(sysctl -n hw.ncpu)
else
  JOBS=2
fi

REL_SCRIPT_PATH="$(dirname $0)"
SCRIPTPATH=$(real_path $REL_SCRIPT_PATH)
CURLPATH="$SCRIPTPATH/../curl"
export SSLPATH="$1" #$SCRIPTPATH/../openssl"
export NDK_ROOT="$ANDROID_NDK_ROOT"

if [ -z "$NDK_ROOT" ]; then
  echo "Please set your NDK_ROOT environment variable first"
  exit 1
fi

if [[ "$NDK_ROOT" == .* ]]; then
  echo "Please set your NDK_ROOT to an absolute path"
  exit 1
fi

#Configure OpenSSL
# cd $SSLPATH
# ./Configure android no-asm no-shared no-cast no-idea no-camellia no-whirpool
# EXITCODE=$?
# if [ $EXITCODE -ne 0 ]; then
# 	echo "Error running the ssl configure program"
# 	cd $PWD
# 	exit $EXITCODE
# fi

# #Build static libssl and libcrypto, required for cURL's configure
# cd $SCRIPTPATH
# $NDK_ROOT/ndk-build -j$JOBS -C $SCRIPTPATH ssl crypto
# EXITCODE=$?
# if [ $EXITCODE -ne 0 ]; then
# 	echo "Error building the libssl and libcrypto"
# 	cd $PWD
# 	exit $EXITCODE
# fi

#Configure cURL
cd $CURLPATH
if [ ! -x "$CURLPATH/configure" ]; then
	echo "Curl needs external tools to be compiled"
	echo "Make sure you have autoconf, automake and libtool installed"

	./buildconf

	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the buildconf program"
		cd $PWD
		exit $EXITCODE
	fi
fi

DESTDIR=$SCRIPTPATH/build #$SCRIPTPATH/../prebuilt-with-ssl/android/build
export SYSROOT="$NDK_ROOT/platforms/$TARGET/arch-arm"
export CFLAGS="-I$NDK_ROOT/platforms/$TARGET/arch-arm/usr/include --sysroot=$SYSROOT"
export CPPFLAGS="-I$NDK_ROOT/platforms/$TARGET/arch-arm/usr/include --sysroot=$SYSROOT"
export CXXFLAGS="-I$NDK_ROOT/platforms/$TARGET/arch-arm/usr/include --sysroot=$SYSROOT"
export CC=$($NDK_ROOT/ndk-which gcc)
export LD=$($NDK_ROOT/ndk-which ld)
export CPP=$($NDK_ROOT/ndk-which cpp)
export CXX=$($NDK_ROOT/ndk-which g++)
export AS=$($NDK_ROOT/ndk-which as)
export AR=$($NDK_ROOT/ndk-which ar)
export RANLIB=$($NDK_ROOT/ndk-which ranlib)

export LIBS="-lssl -lcrypto"
export LDFLAGS="-L$SSLPATH/libs/armeabi-v7a -L$SCRIPTPATH/obj/local/armeabi"
./configure --host=arm-linux-androideabi --target=arm-linux-androideabi \
            --prefix=$DESTDIR --with-ssl=$SSLPATH \
            --enable-static \
            --disable-shared \
            --disable-verbose \
            --enable-threaded-resolver \
            --enable-libgcc \
            --enable-ipv6

EXITCODE=$?
if [ $EXITCODE -ne 0 ]; then
  echo "Error running the configure program"
  cd $PWD
  exit $EXITCODE
fi

#Patch headers for 64-bit archs
cd "$CURLPATH/include/curl"
sed 's/#define CURL_SIZEOF_LONG 4/\
#ifdef __LP64__\
#define CURL_SIZEOF_LONG 8\
#else\
#define CURL_SIZEOF_LONG 4\
#endif/'< curlbuild.h > curlbuild.h.temp

mv curlbuild.h.temp curlbuild.h

cd $CURLPATH
make
make install


STRIP=$($SCRIPTPATH/ndk-which strip $p)

p=armeabi-v7a
mkdir -p $SCRIPTPATH/../prebuilt-with-ssl/android/$p
#SRC=$SCRIPTPATH/obj/local/$p/lib/libcurl.a
SRC=$SCRIPTPATH/build/lib/libcurl.a
DEST=$SCRIPTPATH/../prebuilt-with-ssl/android/$p/libcurl.a

if [ -z "$STRIP" ]; then
  echo "WARNING: Could not find 'strip' for $p"
  cp $SRC $DEST
else
  $STRIP $SRC --strip-debug -o $DEST
fi

exit 0

# #Build cURL
# $NDK_ROOT/ndk-build -j$JOBS -C $SCRIPTPATH curl
# EXITCODE=$?
# if [ $EXITCODE -ne 0 ]; then
# 	echo "Error running the ndk-build program"
# 	exit $EXITCODE
# fi

#Strip debug symbols and copy to the prebuilt folder
PLATFORMS=(arm64-v8a x86_64 mips64 armeabi armeabi-v7a x86 mips)
DESTDIR=$SCRIPTPATH/../prebuilt-with-ssl/android

for p in ${PLATFORMS[*]}; do
  mkdir -p $DESTDIR/$p
  STRIP=$($SCRIPTPATH/ndk-which strip $p)

  SRC=$SCRIPTPATH/obj/local/$p/lib/libcurl.a
  DEST=$DESTDIR/$p/libcurl.a

  if [ -z "$STRIP" ]; then
    echo "WARNING: Could not find 'strip' for $p"
    cp $SRC $DEST
  else
    $STRIP $SRC --strip-debug -o $DEST
  fi
done

#Copying cURL headers
cp -R $CURLPATH/include $DESTDIR/
rm $DESTDIR/include/curl/.gitignore

cd $PWD
exit 0
