#!/bin/bash

# fail on any error
set -e

readonly TARGET="$1"

ZEPHYR_TOOLCHAIN_VARIANT=zephyr
ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk
ZEPHYR_SDK_VERSION=0.16.1
ZEPHYR_SDK_DOWNLOAD_FOLDER=https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v$ZEPHYR_SDK_VERSION
ZEPHYR_SDK_SETUP_DIR=zephyr-sdk-$ZEPHYR_SDK_VERSION
ZEPHYR_SDK_SETUP_TAR=${ZEPHYR_SDK_SETUP_DIR}_linux-x86_64.tar.xz
ZEPHYR_SDK_DOWNLOAD_URL=$ZEPHYR_SDK_DOWNLOAD_FOLDER/$ZEPHYR_SDK_SETUP_TAR

FREERTOS_ZIP_URL=https://cfhcable.dl.sourceforge.net/project/freertos/FreeRTOS/V10.0.1/FreeRTOSv10.0.1.zip

setup_common() {
	apt update
	apt-get install -y make
	sudo pip3 install cmake
}

setup_linux() {
	echo " Setup for linux"
	sudo apt-get install -y libsysfs-dev libhugetlbfs-dev gcc
}

build_linux() {
	mkdir -p build-linux
	cd build-linux
	cmake .. -DWITH_TESTS_EXEC=on
	make VERBOSE=1 all test
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
	wget $FREERTOS_ZIP_URL --dot-style=giga > /dev/null
	unzip FreeRTOSv10.0.1.zip > /dev/null
}

build_freertos() {
	mkdir -p build-freertos
	cd build-freertos export
	cmake .. -DCMAKE_TOOLCHAIN_FILE=template-freertos \
		-DCMAKE_C_FLAGS="-I$PWD/../FreeRTOSv10.0.1/FreeRTOS/Source/include/ \
		-I$PWD/../FreeRTOSv10.0.1/FreeRTOS/Demo/CORTEX_STM32F107_GCC_Rowley \
		-I$PWD/../FreeRTOSv10.0.1/FreeRTOS/Source/portable/GCC/ARM_CM3"
	make VERBOSE=1
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
	sudo pip3 install pyelftools
	pip3 install --user -U west
	echo 'export PATH=~/.local/bin:"$PATH"' >> ~/.bashrc
	source ~/.bashrc

	# Install the zephyr SDK
	wget $ZEPHYR_SDK_DOWNLOAD_URL --dot-style=giga
	echo "Extracting $ZEPHYR_SDK_SETUP_TAR"
	pv $ZEPHYR_SDK_SETUP_TAR -i 3 -ptebr -f | tar xJ
	rm -rf $ZEPHYR_SDK_INSTALL_DIR
	yes | ./$ZEPHYR_SDK_SETUP_DIR/setup.sh

	# The users should be in the dir they want for the top level
	# Pre-clone the whole Zephyr workspace
	# It is fine that we pre-clone main as the versions will get fixed up
	# by the real manifest
	west init
	west update --narrow

	# exporting zephyr cmake resources is not needed if you build in a
	# zephyr workspace or define ZEPHYR_BASE
	# Things are more predictable w/o this
	# west zephyr-export

	# now remove the manifest so we can supply our own in the build
	# use a bit of a sanity test be we do this
	if [ -d zephyr ]; then
		rm -rf .west
	fi

	# Install python packages zephyr needs
	pip3 install --user -r ./zephyr/scripts/requirements.txt
}

build_zephyr() {
	echo  " Build for Zephyr OS "

	# The users should be in the top dir
	# Clone the whole Zephyr workspace
	west init -l ./openamp-system-reference
	west update --narrow

	# Recheck python packages incase they have changed
	pip3 install --user -r ./zephyr/scripts/requirements.txt

	west build -p -b stm32mp157c_dk2 openamp-system-reference/examples/zephyr/rpmsg_multi_services
	west build -p -b kv260_r5        openamp-system-reference/examples/zephyr/rpmsg_multi_services
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
