#!/bin/bash

function build_bl30() {
	if [ "${CONFIG_BYPASS_AOCPU}" == "y" ]; then
		echo "bypass aocpu"
	else
		# $1: src_folder, $2: bin_folder, $3: soc
		echo -n "Build $3 bl30 of ${BL30_SELECT}...Please wait..."
		local tartget
		if [ "${CONFIG_RTOS_SDK_ENABLE}" == "1" ]; then
			echo "Build bl30 from new RTOS SDK."
			local current_dir=$(cd $(dirname $0); pwd)
			local work_dir=${current_dir}/bl30/rtos_sdk
			local output_dir
			local ir_power_file=${work_dir}/boards/riscv/${CONFIG_BOARD_PACKAGE_NAME}/power.c
			if [ "${CONFIG_BOARD_PACKAGE_NAME}" == "bm201_s905x5m" ] && [ -f "${ir_power_file}" ]; then
				local old_ir_init="vIRInit(MODE_HARD_NEC, GPIODV_0, PIN_FUNC1, prvPowerKeyList,"
				local new_ir_init="vIRInit(GPIODV_0, PIN_FUNC1, prvPowerKeyList,"
				sed -i "s#${old_ir_init}#${new_ir_init}#" "${ir_power_file}"
			fi
			cd $work_dir && source scripts/env.sh riscv $CONFIG_SOC_NAME $CONFIG_BOARD_PACKAGE_NAME aocpu && make distclean &&  make REPO_DIR=$REPO_DIR && make docs REPO_DIR=$REPO_DIR &&    \
				output_dir=$work_dir/output/riscv-$CONFIG_BOARD_PACKAGE_NAME-$PRODUCT/freertos
			target=$output_dir/bl30.bin
			cp -arf $output_dir/freertos.bin $output_dir/bl30.bin
		else
			# co-work with bl30 build script under bl30.git
			target="$1/bl30.bin"
			cd $1
			#export CROSS_COMPILE=${AARCH32_TOOL_CHAIN}
			local soc=$3
			if [ "$soc" == "gxtvbb" ]; then
				soc="gxtvb"
			fi
			#make clean BOARD=$soc &> /dev/null
			#make BOARD=$soc &> /dev/null
			if [[ "${BL30_SELECT}" != "" ]]; then
				/bin/bash mk ${BL30_SELECT}
			else
				/bin/bash mk $soc
			fi
		fi
		if [ $? != 0 ]; then
			cd ${MAIN_FOLDER}
			echo "Error: Build bl30 failed... abort"
			exit -1
		fi
		cd ${MAIN_FOLDER}
		cp ${target} $2 -f
		echo "done"
	fi
	return
}
