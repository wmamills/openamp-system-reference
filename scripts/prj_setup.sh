#!/bin/bash

readonly TARGET="$1"

ZEPHYR_TOOLCHAIN_VARIANT=zephyr
ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk
ZEPHYR_SDK_VERSION=0.16.1
ZEPHYR_SDK_DOWNLOAD_FOLDER=https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v$ZEPHYR_SDK_VERSION
ZEPHYR_SDK_SETUP_DIR=zephyr-sdk-$ZEPHYR_SDK_VERSION
ZEPHYR_SDK_SETUP_TAR=${ZEPHYR_SDK_SETUP_DIR}_linux-x86_64.tar.xz
ZEPHYR_SDK_DOWNLOAD_URL=$ZEPHYR_SDK_DOWNLOAD_FOLDER/$ZEPHYR_SDK_SETUP_TAR

FREERTOS_ZIP_URL=https://cfhcable.dl.sourceforge.net/project/freertos/FreeRTOS/V10.0.1/FreeRTOSv10.0.1.zip

pre_build(){
	apt update &&
	apt-get install -y make || exit 1
	sudo pip3 install cmake || exit 1
}

build_linux(){
	echo  " Build for linux"
	apt-get install -y libsysfs-dev libhugetlbfs-dev gcc &&
	mkdir -p build-linux &&
	cd build-linux &&
	cmake .. -DWITH_TESTS_EXEC=on &&
	make VERBOSE=1 all test &&
	exit 0
}

build_generic(){
	echo  " Build for generic platform "
	apt-get install -y gcc-arm-none-eabi &&
	mkdir -p build-generic &&
	cd build-generic &&
	cmake .. -DCMAKE_TOOLCHAIN_FILE=template-generic &&
	make VERBOSE=1 &&
	exit 0
}

build_freertos(){
	echo  " Build for freertos OS "
      	apt-get install -y gcc-arm-none-eabi unzip &&
      	wget $FREERTOS_ZIP_URL --dot-style=giga > /dev/null &&
      	unzip FreeRTOSv10.0.1.zip > /dev/null &&
	mkdir -p build-freertos &&
	cd build-freertos && export &&
	cmake .. -DCMAKE_TOOLCHAIN_FILE=template-freertos \
		-DCMAKE_C_FLAGS="-I$PWD/../FreeRTOSv10.0.1/FreeRTOS/Source/include/ \
		-I$PWD/../FreeRTOSv10.0.1/FreeRTOS/Demo/CORTEX_STM32F107_GCC_Rowley \
		-I$PWD/../FreeRTOSv10.0.1/FreeRTOS/Source/portable/GCC/ARM_CM3" &&
	make VERBOSE=1 &&
	exit 0
}

build_zephyr(){
	echo  " Build for Zephyr OS "
	sudo apt-get install -y git cmake ninja-build gperf || exit 1
	sudo apt-get install -y ccache dfu-util device-tree-compiler wget pv || exit 1
	sudo apt-get install -y python3-dev python3-pip python3-setuptools python3-tk \
		python3-wheel xz-utils file || exit 1
	sudo apt-get install -y make gcc gcc-multilib g++-multilib libsdl2-dev || exit 1
	sudo apt-get install -y libc6-dev-i386 gperf g++ python3-ply python3-yaml \
		device-tree-compiler ncurses-dev uglifyjs -qq || exit 1
	sudo pip3 install pyelftools || exit 1
	pip3 install --user -U west
	echo 'export PATH=~/.local/bin:"$PATH"' >> ~/.bashrc
	source ~/.bashrc

	wget $ZEPHYR_SDK_DOWNLOAD_URL --dot-style=giga || exit 1
	echo "Extracting $ZEPHYR_SDK_SETUP_TAR"
	pv $ZEPHYR_SDK_SETUP_TAR -i 3 -ptebr -f | tar xJ || exit 1
	rm -rf $ZEPHYR_SDK_INSTALL_DIR || exit 1
	yes | ./$ZEPHYR_SDK_SETUP_DIR/setup.sh || exit 1
	cd top || exit 1
	west init -l ./openamp-system-reference || exit 1
	west update --narrow || exit 1
	west zephyr-export || exit 1
	pip3 install --user -r ./zephyr/scripts/requirements.txt || exit 1

	west build -p -b stm32mp157c_dk2 openamp-system-reference/examples/zephyr/rpmsg_multi_services || exit 1
	west build -p -b kv260_r5        openamp-system-reference/examples/zephyr/rpmsg_multi_services || exit 1
	exit 0
}

main(){
	pre_build;

	if [[ "$TARGET" == "linux" ]]; then
		build_linux
	fi
	if [[ "$TARGET" == "generic" ]]; then
		build_generic
	fi
	if [[ "$TARGET" == "freertos" ]]; then
		build_freertos
	fi
	if [[ "$TARGET" == "zephyr" ]]; then
		build_zephyr
	fi
}

main
