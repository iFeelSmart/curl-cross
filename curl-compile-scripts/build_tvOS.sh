#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

XCODE="/Applications/Xcode.app/Contents/Developer"
if [ ! -d "$XCODE" ]; then
	echo "You have to install Xcode and the command line tools first"
	exit 1
fi

REL_SCRIPT_PATH="$(dirname $0)"
SCRIPTPATH=$(realpath "$REL_SCRIPT_PATH")
CURLPATH="$SCRIPTPATH/../curl"

PWD=$(pwd)
cd "$CURLPATH"

if [ ! -x "$CURLPATH/configure" ]; then
	echo "Curl needs external tools to be compiled"
	echo "Make sure you have autoconf, automake and libtool installed"

	./buildconf

	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the buildconf program"
		cd "$PWD"
		exit $EXITCODE
	fi
fi

git apply ../patches/patch_curl_fixes1172.diff

export CC="$XCODE/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
DESTDIR="$SCRIPTPATH/../prebuilt/tvOS"
mkdir -p $DESTDIR

TVOS_MIN_SDK_VERSION=${TVOS_DEPLOYMENT_TARGET:-"10.1"}
ARCHS=(arm64 x86_64)
HOSTS=(arm x86_64)
PLATFORMS=(AppleTVOS AppleTVSimulator)
SDK=(AppleTVOS AppleTVSimulator)

#Build for all the architectures
for (( i=0; i<${#ARCHS[@]}; i++ )); do
	ARCH=${ARCHS[$i]}
	export CFLAGS="-arch $ARCH -pipe -Os -gdwarf-2 -isysroot $XCODE/Platforms/${PLATFORMS[$i]}.platform/Developer/SDKs/${SDK[$i]}.sdk -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode -Werror=partial-availability"
	export LDFLAGS="-arch $ARCH -isysroot $XCODE/Platforms/${PLATFORMS[$i]}.platform/Developer/SDKs/${SDK[$i]}.sdk"
	if [ "${PLATFORMS[$i]}" = "AppleTVSimulator" ]; then
		export CPPFLAGS="-D__IPHONE_OS_VERSION_MIN_REQUIRED=${TVOS_MIN_SDK_VERSION%%.*}0000"
		export CPPFLAGS="-D__APPLETV_OS_VERSION_MIN_REQUIRED=${TVOS_MIN_SDK_VERSION%%.*}0000"
	fi
	cd "$CURLPATH"
	./configure	--host="${HOSTS[$i]}-apple-darwin" \
			--with-darwinssl \
			--enable-static \
			--disable-shared \
			--enable-threaded-resolver \
			--disable-verbose \
			--enable-ipv6 \
			--disable-ntlm-wb
	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the cURL configure program"
		cd "$PWD"
		exit $EXITCODE
	fi

	# Patch to not use fork() since it's not available on tvOS
	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./lib/curl_config.h"
	LANG=C sed -i -- 's/HAVE_FORK"]=" 1"/HAVE_FORK\"]=" 0"/' "config.status"

	make -j $(sysctl -n hw.logicalcpu_max)
	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the make program"
		cd "$PWD"
		exit $EXITCODE
	fi
	mkdir -p "$DESTDIR/$ARCH"
	cp "$CURLPATH/lib/.libs/libcurl.a" "$DESTDIR/$ARCH/"
	cp "$CURLPATH/lib/.libs/libcurl.a" "$DESTDIR/libcurl-$ARCH.a"
	make clean
done

git checkout $CURLPATH

#Build a single static lib with all the archs in it
cd "$DESTDIR"
lipo -create -output libcurl.a libcurl-*.a
rm libcurl-*.a

#Copying cURL headers
cp -R "$CURLPATH/include" "$DESTDIR/"
rm "$DESTDIR/include/curl/.gitignore"

#Patch headers for 64-bit archs
cd "$DESTDIR/include/curl"
sed 's/#define CURL_SIZEOF_LONG 8/\
#ifdef __LP64__\
#define CURL_SIZEOF_LONG 8\
#else\
#define CURL_SIZEOF_LONG 4\
#endif/'< curlbuild.h > curlbuild.h.temp

sed 's/#define CURL_SIZEOF_CURL_OFF_T 8/\
#ifdef __LP64__\
#define CURL_SIZEOF_CURL_OFF_T 8\
#else\
#define CURL_SIZEOF_CURL_OFF_T 4\
#endif/' < curlbuild.h.temp > curlbuild.h
rm curlbuild.h.temp

cd "$PWD"
