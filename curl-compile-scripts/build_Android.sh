#!/bin/bash

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
export SSL_PATH="$1" #$SCRIPTPATH/../openssl"

if [ -z "$ANDROID_NDK_ROOT" ]; then
  echo "Please set your ANDROID_NDK_ROOT environment variable first"
  exit 1
fi

if [[ "$ANDROID_NDK_ROOT" == .* ]]; then
  echo "Please set your ANDROID_NDK_ROOT to an absolute path"
  exit 1
fi

_ANDROID_API=${_ANDROID_API:-"android-18"}
if [ ! -z "${ANDROID_API_VERSION}" ]; then
  _ANDROID_API=${ANDROID_API_VERSION}
fi

_ANDROID_ARCH="arch-arm"
if [ ! -z "${ANDROID_ARCH}" ]; then
  _ANDROID_ARCH=${ANDROID_ARCH}
fi

_ANDROID_EABI="arm-linux-androideabi-4.8"
if [[ ! -z "${ANDROID_NDK_TOOLCHAIN_PREFIX}" && ! -z "${ANDROID_NDK_TOOLCHAIN_PREFIX}" ]]; then
  _ANDROID_EABI="${ANDROID_NDK_TOOLCHAIN_PREFIX}-${ANDROID_NDK_TOOLCHAIN_VERSION}"
fi

case $_ANDROID_ARCH in
	arch-arm)	  
      ANDROID_TOOLS="arm-linux-androideabi-gcc arm-linux-androideabi-ranlib arm-linux-androideabi-ld"
	  ;;
  arch-arm64)	  
      ANDROID_TOOLS="aarch64-linux-android-gcc aarch64-linux-android-ranlib aarch64-linux-android-ld"
	  ;;
	arch-x86)	  
      ANDROID_TOOLS="i686-linux-android-gcc i686-linux-android-ranlib i686-linux-android-ld"
	  ;;	  
	*)
	  echo "ERROR ERROR ERROR"
	  ;;
esac

ANDROID_TOOLCHAIN=""
for host in "linux-x86_64" "linux-x86" "darwin-x86_64" "darwin-x86"
do
  if [ -d "$ANDROID_NDK_ROOT/toolchains/$_ANDROID_EABI/prebuilt/$host/bin" ]; then
    ANDROID_TOOLCHAIN="$ANDROID_NDK_ROOT/toolchains/$_ANDROID_EABI/prebuilt/$host/bin"
    break
  fi
done

# Error checking
if [ -z "$ANDROID_TOOLCHAIN" ] || [ ! -d "$ANDROID_TOOLCHAIN" ]; then
  echo "Error: ANDROID_TOOLCHAIN is not valid. Please edit this script."
  # echo "$ANDROID_TOOLCHAIN"
  # exit 1
fi

for tool in $ANDROID_TOOLS
do
  # Error checking
  if [ ! -e "$ANDROID_TOOLCHAIN/$tool" ]; then
    echo "Error: Failed to find $tool. Please edit this script."
    # echo "$ANDROID_TOOLCHAIN/$tool"
    # exit 1
  fi
done

# Only modify/export PATH if ANDROID_TOOLCHAIN good
if [ ! -z "$ANDROID_TOOLCHAIN" ]; then
  export ANDROID_TOOLCHAIN="$ANDROID_TOOLCHAIN"
  export PATH="$ANDROID_TOOLCHAIN":"$PATH"
fi

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

PREFIXDIR=$SCRIPTPATH/build 
mkdir -p $PREFIXDIR

export SYSROOT="$ANDROID_NDK_ROOT/platforms/$ANDROID_NDK_PLATFORM/$_ANDROID_ARCH"
export CFLAGS="-I$SYSROOT/usr/include --sysroot=$SYSROOT"
export CPPFLAGS="-I$SYSROOT/usr/include --sysroot=$SYSROOT"
export CXXFLAGS="-I$SYSROOT/usr/include --sysroot=$SYSROOT"
export LIBS="-lssl -lcrypto"

host=""
platform=""
cross=""
case $_ANDROID_ARCH in
	arch-arm)	  

      host="arm-linux-androideabi"
      platform="armeabi-v7a"
      export LDFLAGS="-L$SSL_PATH/libs/armeabi-v7a -L$SCRIPTPATH/obj/local/armeabi"
	  ;;
  arch-arm64)	  
      host="aarch64-linux-android"
      platform="arm64-v8a"
      export LDFLAGS="-L$SSL_PATH/libs/arm64-v8a -L$SCRIPTPATH/obj/local/arm64"
	  ;;
	arch-x86)	  
      host="i686-linux-android"
      platform="x86"
      export LDFLAGS="-L$SSL_PATH/libs/x86 -L$SCRIPTPATH/obj/local/x86"
	  ;;	  
	*)
	  echo "ERROR ERROR ERROR"
	  ;;
esac

export CC="$ANDROID_TOOLCHAIN/$host-gcc"
export LD="$ANDROID_TOOLCHAIN/$host-ld"
export CPP="$ANDROID_TOOLCHAIN/$host-cpp"
export CXX="$ANDROID_TOOLCHAIN/$host-g++"
export AS="$ANDROID_TOOLCHAIN/$host-as"
export AR="$ANDROID_TOOLCHAIN/$host-ar"
export RANLIB="$ANDROID_TOOLCHAIN/$host-ranlib"


# Logs
echo
echo "SYSROOT: $SYSROOT" 
echo "ANDROID_TOOLCHAIN: $ANDROID_TOOLCHAIN"
echo "ANDROID_ARCH: $ANDROID_ARCH"
echo "ANDROID_API: $ANDROID_NDK_PLATFORM"
echo "CC: $CC"
echo

# Configure
./configure --host=$host --target=$host \
            --prefix=$PREFIXDIR --with-ssl=$SSL_PATH \
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

# HAVE_GETPWUID no exist in android < 21 but seems detected ? so patched
if [[ $OSTYPE == darwin* ]]
then
  sed -i '' -e 's/#define HAVE_GETPWUID 1/#undef HAVE_GETPWUID/g' lib/curl_config.h
  sed -i '' -e 's/#define HAVE_GETPWUID_R 1/#undef HAVE_GETPWUID_R/g' lib/curl_config.h
else
  sed -i 's/#define HAVE_GETPWUID 1/#undef HAVE_GETPWUID/g' lib/curl_config.h
  sed -i 's/#define HAVE_GETPWUID_R 1/#undef HAVE_GETPWUID_R/g' lib/curl_config.h
fi
cd "$PWD"


# BUILD
cd $CURLPATH
#make clean
make
make install

# STRIP and INSTALL
STRIP=$($SCRIPTPATH/ndk-which strip $platform)

DESTDIR=$SCRIPTPATH/../prebuilt/android
mkdir -p $DESTDIR/$platform

SRC=$SCRIPTPATH/build/lib/libcurl.a
DEST=$DESTDIR/$platform/libcurl.a

if [ -z "$STRIP" ]; then
  echo "WARNING: Could not find 'strip' for $platform"
  cp $SRC $DEST
else
  echo
  echo "STRIP: $STRIP"
  echo "  - SRC: $SRC"
  echo "  - DST: $DEST"
  echo
  $STRIP $SRC --strip-debug -o $DEST
fi

rm -rf $PREFIXDIR
#Copying cURL headers
cp -R $CURLPATH/include $DESTDIR/
rm $DESTDIR/include/curl/.gitignore

exit 0
