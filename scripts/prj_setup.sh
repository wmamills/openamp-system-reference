#!/bin/bash

# Setup a workspace to build RTOS applications for OpenAMP
# Also support using your Linux native system as a "RTOS stand-in"

# NOTE: As of now this is appropriate for containers and VMs
# I would not want to run it on my real Linux system as of yet

# TODO:
# * check if steps are already done before doing them
# * support split admin_setup from user_setup for people w/o sudo
# * allow user to disallow sudo
# * check if needed before doing sudo

# fail on any error
set -e

readonly TARGET="$1"

# Assume this for now
HOSTOS=linux-x86_64

ZEPHYR_TOOLCHAIN_VARIANT=zephyr
#ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk
ZEPHYR_SDK_VERSION=0.16.1
ZEPHYR_SDK_FOLDER=https://github.com/zephyrproject-rtos/sdk-ng/releases/download
ZEPHYR_SDK_SETUP_DIR=zephyr-sdk-$ZEPHYR_SDK_VERSION
ZEPHYR_SDK_SETUP_TAR=${ZEPHYR_SDK_SETUP_DIR}_${HOSTOS}.tar.xz
ZEPHYR_SDK_URL=$ZEPHYR_SDK_FOLDER/v$ZEPHYR_SDK_VERSION/$ZEPHYR_SDK_SETUP_TAR

FREERTOS_VERSION=202212.01
FREERTOS_GITHUB_FOLDER=https://github.com/FreeRTOS/FreeRTOS/releases/download/
FREERTOS_DIR=FreeRTOSv${FREERTOS_VERSION}
FREERTOS_FILE=FreeRTOSv${FREERTOS_VERSION}.zip
FREERTOS_URL=${FREERTOS_GITHUB_FOLDER}/${FREERTOS_VERSION}/${FREERTOS_FILE}

setup_common() {
	sudo apt update
	sudo apt-get install -y make git python3 python3-pip wget
	sudo pip3 install cmake
}

setup_linux() {
	echo " Setup for linux"
	sudo apt-get install -y libsysfs-dev libhugetlbfs-dev gcc
}

# Build Linux examples for the native host
# These will not do anything useful if your native host is not
# OpenAMP enabled, but you can still build them
build_linux() {
	cd openamp-system-reference/examples/linux
	make -C rpmsg-echo-test clean all
	make -C rpmsg-mat-mul clean all
	make -C rpmsg-proxy-app clean all
	make -C rpmsg-utils clean all
}

setup_generic() {
	echo " Setup for generic platform "
	sudo apt-get install -y gcc-arm-none-eabi
}

build_generic() {
	mkdir -p build-generic
	cd build-generic
	cmake .. -DCMAKE_TOOLCHAIN_FILE=template-generic
	make VERBOSE=1
}

setup_freertos() {
	echo  " Setup for freertos OS "
	sudo apt-get install -y gcc-arm-none-eabi unzip
	wget $FREERTOS_URL --dot-style=giga > /dev/null
	echo  "   Extracting $FREERTOS_FILE"
	unzip $FREERTOS_FILE > /dev/null
}

build_freertos() {
	# Build the stock FreeRTOS Demos that are cross GCC & Makefile & QEMU
	MY_CWD=$(pwd)
	cd $FREERTOS_DIR/FreeRTOS/Demo
	make -C CORTEX_M3_MPS2_QEMU_GCC
	make -C CORTEX_MPS2_QEMU_IAR_GCC/build/gcc
	make -C CORTEX_MPU_M3_MPS2_QEMU_GCC

	# Build the stock FreeRTOS Demos that are Cmake based
	cd $MY_CWD
	if [ ! -e pico-sdk/pico_sdk_init.cmake ]; then
		# Don't do recursive here as tinyusb has TON of submodule
		# we don't need every usb hal know to man
		git clone https://github.com/raspberrypi/pico-sdk.git
		(cd pico-sdk; git submodule update)
	fi

	export PICO_SDK_PATH=$PWD/pico-sdk
	mkdir -p build_freertos/rp2040
	S=$FREERTOS_DIR/FreeRTOS/Demo/ThirdParty/Community-Supported/CORTEX_M0+_RP2040
	B=build_freertos/rp2040
	for i in Standard UsingCMSIS OnEitherCore; do
		cmake -S $S/$1 -B $B/$i
	done
}

ensure_local_bin() {
	# ensure that ~/.local/bin is in the path

	# Note1: some distros (Ubuntu for one) will add ~/.local/bin to the
	# PATH in the system level (/etc/) rc files, but only if it already
	# exists in the user home dir.  It is hard to count on that so we add
	# it to the .bashrc file anyway but we make it conditional so it is not
	# added twice

	# Note2: many distros (Ubuntu included) test for an interactive shell
	# at the top of the .bashrc and skip the rest of the file if not.
	# We want ./local/bin in the path even for non-interactive shells and
	# for containers and job VMs we can't rely on an interactive shell
	# having already run.  So we add our bit at the top of .bashrc

	NOW=$(date +%Y-%m-%d-%H:%M:%S)
	cat > bashrc-header <<EOF
if ! echo $PATH | grep -q /.local/bin >/dev/null; then
    export PATH="$HOME/.local/bin:$PATH"
fi
EOF
	if ! grep -q /.local/bin ~/.bashrc; then
		mv ~/.bashrc ~/.bashrc.$NOW
		cat bashrc-header ~/.bashrc.$NOW >~/.bashrc
	fi

	# now handle this shell
	source bashrc-header
}

setup_zephyr() {
	echo  " Setup for Zephyr OS "

	# install needed packages from OS
	sudo apt-get install -y git cmake ninja-build gperf
	sudo apt-get install -y ccache dfu-util device-tree-compiler wget pv
	sudo apt-get install -y python3-dev python3-pip python3-setuptools python3-tk \
		python3-wheel xz-utils file
	sudo apt-get install -y make gcc gcc-multilib g++-multilib libsdl2-dev
	sudo apt-get install -y libc6-dev-i386 gperf g++ python3-ply python3-yaml \
		device-tree-compiler ncurses-dev uglifyjs -qq

	# Install things from python pip
	ensure_local_bin
	pip3 install --user -U pyelftools
	pip3 install --user -U west

	# Install the zephyr SDK
	wget $ZEPHYR_SDK_URL --dot-style=giga
	echo "Extracting $ZEPHYR_SDK_SETUP_TAR"
	pv $ZEPHYR_SDK_SETUP_TAR -i 3 -ptebr -f | tar xJ
	#rm -rf $ZEPHYR_SDK_INSTALL_DIR
	yes | ./$ZEPHYR_SDK_SETUP_DIR/setup.sh
}

precache_zephyr() {
	echo  " Pre-cache zephyr for fast west init"

	# The users should be in the dir they want for the top level
	# Pre-clone the whole Zephyr workspace
	# It is fine that we pre-clone main as the versions will get fixed up
	# by the real manifest
	west init
	west update

	# exporting zephyr cmake resources is not needed if you build in a
	# zephyr workspace or define ZEPHYR_BASE
	# Things are more predictable w/o this
	# west zephyr-export

	# now remove the manifest so we can supply our own in the build
	# use a bit of a sanity test before we do this
	if [ -d zephyr ]; then
		rm -rf .west
	fi

	# Install python packages zephyr needs
	pip3 install --user -r ./zephyr/scripts/requirements.txt
}

build_zephyr() {
	echo  " Build for Zephyr OS "
	ensure_local_bin

	# The users should be in the top dir
	# Clone the whole Zephyr workspace
	cd openamp-system-reference
	west init -l .
	west update --narrow

	# Recheck python packages incase they have changed
	pip3 install --user -r ../zephyr/scripts/requirements.txt

	west build -p -b stm32mp157c_dk2 examples/zephyr/rpmsg_multi_services
	west build -p -b kv260_r5        examples/zephyr/rpmsg_multi_services
}

main() {
	case "$TARGET" in
	setup_linux)
		setup_common
		setup_linux
		;;
	setup_generic)
		setup_common
		setup_generic
		;;
	setup_freertos)
		setup_common
		setup_freertos
		;;
	setup_zephyr)
		setup_common
		setup_zephyr
		;;
	setup_all)
		setup_common
		setup_linux
		setup_generic
		setup_freertos
		setup_zephyr
		;;
	linux)
		build_linux
		;;
	generic)
		build_generic
		;;
	freertos)
		build_freertos
		;;
	zephyr)
		build_zephyr
		;;
	all)
		build_linux
		build_generic
		build_freertos
		build_zephyr
		;;
	*)
		echo "Unknown target $TARGET" && false
	esac
}

main
