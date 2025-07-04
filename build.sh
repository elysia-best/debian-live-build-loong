#!/bin/bash

# If a command fails, make the whole script exit
set -e
# Use return code for any command errors in part of a pipe
set -o pipefail # Bashism

# Lingmo's default values
DEBIAN_DIST="sid"
DEBIAN_VERSION="$(date +%Y%m%d)"
DEBIAN_VARIANT="default"
IMAGE_TYPE="live"
TARGET_DIR="$(dirname $0)/images"
TARGET_SUBDIR=""
SUDO="sudo"
VERBOSE="false"
DEBUG=""
HOST_ARCH=$(dpkg --print-architecture)

image_name() {
	case "$IMAGE_TYPE" in
	live)
		live_image_name
		;;
	installer)
		installer_image_name
		;;
	esac
}

live_image_name() {
	case "$DEBIAN_ARCH" in
	i386 | amd64 | arm64)
		echo "live-image-$DEBIAN_ARCH.hybrid.iso"
		;;
	loong64)
		echo "live-image-$DEBIAN_ARCH.iso"
		;;
	armel | armhf)
		echo "live-image-$DEBIAN_ARCH.img"
		;;
	esac
}

installer_image_name() {
	if [ "$DEBIAN_VARIANT" = "netinst" ]; then
		echo "simple-cdd/images/debian-$DEBIAN_VERSION-$DEBIAN_ARCH-NETINST-1.iso"
	else
		echo "simple-cdd/images/debian-$DEBIAN_VERSION-$DEBIAN_ARCH-BD-1.iso"
	fi
}

target_image_name() {
	local arch=$1

	IMAGE_NAME="$(image_name $arch)"
	IMAGE_EXT="${IMAGE_NAME##*.}"
	if [ "$IMAGE_EXT" = "$IMAGE_NAME" ]; then
		IMAGE_EXT="img"
	fi
	if [ "$IMAGE_TYPE" = "live" ]; then
		if [ "$DEBIAN_VARIANT" = "default" ]; then
			echo "${TARGET_SUBDIR:+$TARGET_SUBDIR/}debian-linux-$DEBIAN_VERSION-live-$DEBIAN_ARCH.$IMAGE_EXT"
		else
			echo "${TARGET_SUBDIR:+$TARGET_SUBDIR/}debian-linux-$DEBIAN_VERSION-live-$DEBIAN_VARIANT-$DEBIAN_ARCH.$IMAGE_EXT"
		fi
	else
		if [ "$DEBIAN_VARIANT" = "default" ]; then
			echo "${TARGET_SUBDIR:+$TARGET_SUBDIR/}debian-linux-$DEBIAN_VERSION-installer-$DEBIAN_ARCH.$IMAGE_EXT"
		else
			echo "${TARGET_SUBDIR:+$TARGET_SUBDIR/}debian-linux-$DEBIAN_VERSION-installer-$DEBIAN_VARIANT-$DEBIAN_ARCH.$IMAGE_EXT"
		fi
	fi
}

target_build_log() {
	TARGET_IMAGE_NAME=$(target_image_name $1)
	echo ${TARGET_IMAGE_NAME%.*}.log
}

default_version() {
	case "$1" in
	debian-*)
		echo "${1#debian-}"
		;;
	*)
		echo "$1"
		;;
	esac
}

failure() {
	echo "Build of $DEBIAN_DIST/$DEBIAN_VARIANT/$DEBIAN_ARCH $IMAGE_TYPE image failed (see build.log for details)" >&2
	echo "Log: $BUILD_LOG" >&2
	exit 2
}

run_and_log() {
	if [ -n "$VERBOSE" ] || [ -n "$DEBUG" ]; then
		printf "RUNNING:" >&2
		for _ in "$@"; do
			[[ $_ =~ [[:space:]] ]] && printf " '%s'" "$_" || printf " %s" "$_"
		done >&2
		printf "\n" >&2
		"$@" 2>&1 | tee -a "$BUILD_LOG"
	else
		"$@" >>"$BUILD_LOG" 2>&1
	fi
	return $?
}

debug() {
	if [ -n "$DEBUG" ]; then
		echo "DEBUG: $*" >&2
	fi
}

clean() {
	debug "Cleaning"

	# Live
	run_and_log $SUDO lb clean --purge
	#run_and_log $SUDO umount -l $(pwd)/chroot/proc
	#run_and_log $SUDO umount -l $(pwd)/chroot/dev/pts
	#run_and_log $SUDO umount -l $(pwd)/chroot/sys
	#run_and_log $SUDO rm -rf $(pwd)/chroot
	#run_and_log $SUDO rm -rf $(pwd)/binary

	# Installer
	run_and_log $SUDO rm -rf "$(pwd)/simple-cdd/tmp"
	run_and_log $SUDO rm -rf "$(pwd)/simple-cdd/debian-cd"
}

print_help() {
	echo "Usage: $0 [<option>...]"
	echo
	for x in $(echo "${BUILD_OPTS_LONG}" | sed 's_,_ _g'); do
		x=$(echo $x | sed 's/:$/ <arg>/')
		echo "  --${x}"
	done
	echo
	echo "More information: https://www.debian.org/docs/development/live-build-a-custom-debian-iso/"
	exit 0
}

# Allowed command line options
. $(dirname $0)/.getopt.sh

BUILD_LOG="$(pwd)/build.log"
debug "BUILD_LOG: $BUILD_LOG"
# Create empty file
: >"$BUILD_LOG"

# Parsing command line options (see .getopt.sh)
temp=$(getopt -o "$BUILD_OPTS_SHORT" -l "$BUILD_OPTS_LONG,get-image-path" -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
	-d | --distribution)
		DEBIAN_DIST="$2"
		shift 2
		;;
	-p | --proposed-updates)
		OPT_pu="1"
		shift 1
		;;
	-a | --arch)
		DEBIAN_ARCH="$2"
		shift 2
		;;
	-v | --verbose)
		VERBOSE="1"
		shift 1
		;;
	-D | --debug)
		DEBUG="1"
		shift 1
		;;
	-s | --salt) shift ;;
	-h | --help) print_help ;;
	--installer)
		IMAGE_TYPE="installer"
		shift 1
		;;
	--live)
		IMAGE_TYPE="live"
		shift 1
		;;
	--variant)
		DEBIAN_VARIANT="$2"
		shift 2
		;;
	--version)
		DEBIAN_VERSION="$2"
		shift 2
		;;
	--subdir)
		TARGET_SUBDIR="$2"
		shift 2
		;;
	--get-image-path)
		ACTION="get-image-path"
		shift 1
		;;
	--clean)
		ACTION="clean"
		shift 1
		;;
	--no-clean)
		NO_CLEAN="1"
		shift 1
		;;
	--)
		shift
		break
		;;
	*)
		echo "ERROR: Invalid command-line option: $1" >&2
		exit 1
		;;
	esac
done

# Set default values
DEBIAN_ARCH=${DEBIAN_ARCH:-$HOST_ARCH}
if [ "$DEBIAN_ARCH" = "x64" ]; then
	DEBIAN_ARCH="amd64"
elif [ "$DEBIAN_ARCH" = "x86" ]; then
	DEBIAN_ARCH="i386"
fi
debug "DEBIAN_ARCH: $DEBIAN_ARCH"

if [ -z "$DEBIAN_VERSION" ]; then
	DEBIAN_VERSION="$(default_version $DEBIAN_DIST)"
fi
debug "DEBIAN_VERSION: $DEBIAN_VERSION"

# Check parameters
debug "HOST_ARCH: $HOST_ARCH"
if [ "$HOST_ARCH" != "$DEBIAN_ARCH" ] && [ "$IMAGE_TYPE" != "installer" ]; then
	case "$HOST_ARCH/$DEBIAN_ARCH" in
	amd64/i386 | i386/amd64) ;;
	*)
		echo "Can't build $DEBIAN_ARCH image on $HOST_ARCH system." >&2
		exit 1
		;;
	esac
fi

# Build parameters for lb config
DEBIAN_CONFIG_OPTS="--distribution $DEBIAN_DIST -- --variant $DEBIAN_VARIANT"
CODENAME=$DEBIAN_DIST # for simple-cdd/debian-cd
if [ -n "$OPT_pu" ]; then
	DEBIAN_CONFIG_OPTS="$DEBIAN_CONFIG_OPTS --proposed-updates"
	DEBIAN_DIST="$DEBIAN_DIST+pu"
fi
debug "DEBIAN_CONFIG_OPTS: $DEBIAN_CONFIG_OPTS"
debug "CODENAME: $CODENAME"
debug "DEBIAN_DIST: $DEBIAN_DIST"

# Set sane PATH (cron seems to lack /sbin/ dirs)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
debug "PATH: $PATH"

if grep -q -e "^ID=debian" -e "^ID_LIKE=debian" /usr/lib/os-release; then
	debug "OS: $(. /usr/lib/os-release && echo $NAME $VERSION)"
elif [ -e /etc/debian_version ]; then
	debug "OS: $(cat /etc/debian_version)"
else
	echo "ERROR: Non Debian-based OS" >&2
fi

debug "IMAGE_TYPE: $IMAGE_TYPE"
case "$IMAGE_TYPE" in
live)
	if [ ! -d "$(dirname $0)/debian-config/variant-$DEBIAN_VARIANT" ]; then
		echo "ERROR: Unknown variant of Lingmo live configuration: $DEBIAN_VARIANT" >&2
	fi

	ver_live_build=$(dpkg-query -f '${Version}' -W live-build)
	if dpkg --compare-versions "$ver_live_build" lt "1:20230502"; then
		echo "ERROR: You need live-build (>= 1:20230502), you have $ver_live_build" >&2
		exit 1
	fi
	debug "ver_live_build: $ver_live_build"

	ver_debootstrap=$(dpkg-query -f '${Version}' -W debootstrap)
	if dpkg --compare-versions "$ver_debootstrap" lt "1.0.97"; then
		echo "ERROR: You need debootstrap (>= 1.0.97), you have $ver_debootstrap" >&2
		exit 1
	fi
	debug "ver_debootstrap: $ver_debootstrap"
	;;
installer)
	if [ ! -d "$(dirname $0)/debian-config/installer-$DEBIAN_VARIANT" ]; then
		echo "ERROR: Unknown variant of Lingmo installer configuration: $DEBIAN_VARIANT" >&2
	fi

	ver_debian_cd=$(dpkg-query -f '${Version}' -W debian-cd)
	if dpkg --compare-versions "$ver_debian_cd" lt 3.2.1; then
		echo "ERROR: You need debian-cd (>= 3.2.1), you have $ver_debian_cd" >&2
		exit 1
	fi
	debug "ver_debian_cd: $ver_debian_cd"

	ver_simple_cdd=$(dpkg-query -f '${Version}' -W simple-cdd)
	if dpkg --compare-versions "$ver_simple_cdd" lt 0.6.9; then
		echo "ERROR: You need simple-cdd (>= 0.6.9), you have $ver_simple_cdd" >&2
		exit 1
	fi
	debug "ver_simple_cdd: $ver_simple_cdd"
	;;
*)
	echo "ERROR: Unsupported IMAGE_TYPE selected ($IMAGE_TYPE)" >&2
	exit 1
	;;
esac

# We need root rights at some point
if [ "$(whoami)" != "root" ]; then
	if ! which $SUDO >/dev/null; then
		echo "ERROR: $0 is not run as root and $SUDO is not available" >&2
		exit 1
	fi
else
	SUDO="" # We're already root
fi
debug "SUDO: $SUDO"

IMAGE_NAME="$(image_name $DEBIAN_ARCH)"
debug "IMAGE_NAME: $IMAGE_NAME"

debug "ACTION: $ACTION"
if [ "$ACTION" = "get-image-path" ]; then
	echo $(target_image_name $DEBIAN_ARCH)
	exit 0
fi

if [ "$NO_CLEAN" = "" ]; then
	clean
fi
if [ "$ACTION" = "clean" ]; then
	exit 0
fi

cd $(dirname $0)
mkdir -p $TARGET_DIR/$TARGET_SUBDIR

# Don't quit on any errors now
set +e

case "$IMAGE_TYPE" in
live)
	debug "Stage 1/2 - Config"
	run_and_log lb config -a $DEBIAN_ARCH $DEBIAN_CONFIG_OPTS "$@"
	[ $? -eq 0 ] || failure

	debug "Stage 2/2 - Build"
	run_and_log $SUDO lb build
	if [ $? -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
		failure
	fi
	;;
installer)
	# Override some debian-cd environment variables
	export BASEDIR="$(pwd)/simple-cdd/debian-cd"
	export ARCHES=$DEBIAN_ARCH
	export ARCH=$DEBIAN_ARCH
	export DEBVERSION=$DEBIAN_VERSION
	debug "BASEDIR: $BASEDIR"
	debug "ARCHES: $ARCHES"
	debug "ARCH: $ARCH"
	debug "DEBVERSION: $DEBVERSION"

	if [ "$DEBIAN_VARIANT" = "netinst" ]; then
		export DISKTYPE="NETINST"
		profiles="debian"
		auto_profiles="debian"
	elif [ "$DEBIAN_VARIANT" = "purple" ]; then
		export DISKTYPE="BD"
		profiles="debian debian-purple offline"
		auto_profiles="debian debian-purple offline"
		export KERNEL_PARAMS="debian-installer/theme=Clearlooks-Purple"
	else # plain installer
		export DISKTYPE="BD"
		profiles="debian offline"
		auto_profiles="debian offline"
	fi
	debug "DISKTYPE: $DISKTYPE"
	debug "profiles: $profiles"
	debug "auto_profiles: $auto_profiles"
	[ -v KERNEL_PARAMS ] && debug "KERNEL_PARAMS: $KERNEL_PARAMS"

	if [ -e .mirror ]; then
		debian_mirror=$(cat .mirror)
	else
		debian_mirror=http://debian-archive.trafficmanager.net/debian
	fi
	if ! echo "$debian_mirror" | grep -q '/$'; then
		debian_mirror="$debian_mirror/"
	fi
	debug "debian_mirror: $debian_mirror"

	debug "Stage 1/2 - File(s)"
	# Setup custom debian-cd to make our changes
	cp -aT /usr/share/debian-cd simple-cdd/debian-cd
	[ $? -eq 0 ] || failure

	# Use the same grub theme as in the live images
	# Until debian-cd is smart enough: http://bugs.debian.org/1003927
	cp -f debian-config/common/bootloaders/grub-pc/grub-theme.in simple-cdd/debian-cd/data/$CODENAME/grub-theme.in

	# Keep 686-pae udebs as we changed the default from 686
	# to 686-pae in the debian-installer images
	sed -i -e '/686-pae/d' \
		simple-cdd/debian-cd/data/$CODENAME/exclude-udebs-i386
	[ $? -eq 0 ] || failure

	# Configure the debian profile with the packages we want
	grep -v '^#' debian-config/installer-$DEBIAN_VARIANT/packages \
		>simple-cdd/profiles/debian.downloads
	[ $? -eq 0 ] || failure

	# Tasksel is required in the mirror for debian-cd
	echo tasksel >>simple-cdd/profiles/debian.downloads
	[ $? -eq 0 ] || failure

	# Grub is the only supported bootloader on arm64
	# so ensure it's on the iso for arm64.
	if [ "$DEBIAN_ARCH" = "arm64" ]; then
		debug "arm64 GRUB"
		echo "grub-efi-arm64" >>simple-cdd/profiles/debian.downloads
		[ $? -eq 0 ] || failure
	fi

	# Run simple-cdd
	debug "Stage 2/2 - Build"
	cd simple-cdd/
	run_and_log build-simple-cdd \
		--verbose \
		--debug \
		--force-root \
		--conf simple-cdd.conf \
		--dist $CODENAME \
		--debian-mirror $debian_mirror \
		--profiles "$profiles" \
		--auto-profiles "$auto_profiles"
	res=$?
	cd ../
	if [ $res -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
		failure
	fi
	;;
esac

# If a command fails, make the whole script exit
set -e

debug "Moving files"
run_and_log mv -f $IMAGE_NAME $TARGET_DIR/$(target_image_name $DEBIAN_ARCH)
run_and_log mv -f "$BUILD_LOG" $TARGET_DIR/$(target_build_log $DEBIAN_ARCH)

run_and_log echo -e "\n***\nGENERATED DEBIAN IMAGE: $TARGET_DIR/$(target_image_name $DEBIAN_ARCH)\n***"
