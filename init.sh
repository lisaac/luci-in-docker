#!/bin/sh

PLUGIN_DIR='/external/plugin'
CONFIG_DIR='/external/cfg.d'
UCI_CONFIG_DIR='/etc/config'
INTERNAL_PLUGIN_DIR='/internal/plugin'

init_env() {
	export LUCI_SYSROOT='/tmp/.luci'
	export IPKG_INSTROOT=$LUCI_SYSROOT
	export LD_LIBRARY_PATH="$LUCI_SYSROOT/usr/lib:$LD_LIBRARY_PATH"
	export PATH="$LUCI_SYSROOT/bin:$LUCI_SYSROOT/sbin:$LUCI_SYSROOT/usr/sbin:$LUCI_SYSROOT/usr/bin:$PATH"
	export LUA_PATH="$LUCI_SYSROOT/usr/lib/lua/?.lua;$LUCI_SYSROOT/usr/lib/lua/?/init.lua;;"
	export LUA_CPATH="$LUCI_SYSROOT/usr/lib/lua/?.so;;"
	export DYLD_LIBRARY_PATH="$LUCI_SYSROOT/usr/lib:$DYLD_LIBRARY_PATH"
}

log_info() {
	echo -e "$(date +%Y-%m-%d\ %T) $1"
}

merge() {
	src=$1
	dst=$2
	# 跳过以_开头的目录
	[[ $(echo $src | awk -F'/' '{print $NF}') = "_*" ]] && return
	log_info "Merging plugin $src.."
	mkdir -p $dst
		# 执行 preinst
	[ -f "$src/preinst" ] && log_info "\tExecuting preinst.."	&& chmod +x $src/preinst && $src/preinst
	#合并root
	[ -d "$src/root" ] && cp -R $src/root/. $dst/ &&\
	#合并config
	# mkdir -p $dst/etc/config
	if [ -d "$src/root/$UCI_CONFIG_DIR" ]; then
		for cfg in $src/root/$UCI_CONFIG_DIR/*
		do
			if [ -f "$cfg" ]; then
				cfg_name=$(echo $cfg | awk -F'/' '{print $NF}')
				# [ ! -f $CONFIG_DIR/config/$cfg_name ] && cp $cfg $CONFIG_DIR/config/
				[ ! -f $UCI_CONFIG_DIR/$cfg_name ] && cp $cfg $UCI_CONFIG_DIR/
			elif [ -d "$cfg" ]; then
				cfg_name=$(basename $cfg)
				# [ ! -d $CONFIG_DIR/config/$cfg_name ] && cp -R $cfg $CONFIG_DIR/config/
				[ ! -d $UCI_CONFIG_DIR/$cfg_name ] && cp -R $cfg $UCI_CONFIG_DIR/
			fi
		done
	fi
	# 合并 luasrc
	mkdir -p $dst/usr/lib/lua/luci/
	[ -d "$src/luasrc" ] && cp -R $src/luasrc/. $dst/usr/lib/lua/luci/
	# 合并 htdocs
	mkdir -p $dst/www/
	[ -d "$src/htdocs" ] && cp -R $src/htdocs/. $dst/www/
	# i18n
	mkdir -p $dst/usr/lib/lua/luci/i18n/
	if [ -d "$src/po" ]; then
		for i18n in $src/po/*
		do
			for po in $i18n/*
			do
				[ -n "$(echo $po | grep -E '.po$')" ] && {
					po_name=$(echo $po | awk -F'/' '{print $NF}' | awk -F'.' '{print $1}').$(echo $i18n | awk -F'/' '{print $NF}')
					lang=$(echo $po_name | awk -F '[-.]' '{print $2}')
					if [ $lang = "zh_Hans" ]; then
						po_name="$(echo $po_name | awk -F '[-.]' '{print $1}').zh-cn"
					elif [ $lang = "zh_Hant" ]; then
						po_name="$(echo $po_name | awk -F '[-.]' '{print $1}').zn-tw"
					elif [ $lang = "pt_BR" ]; then
						po_name="$(echo $po_name | awk -F '[-.]' '{print $1}').pt-br"
					elif [ $lang = "nb_NO" ]; then
						po_name="$(echo $po_name | awk -F '[-.]' '{print $1}').nb"
					elif [ $lang = "bn_BD" ]; then
						po_name="$(echo $po_name | awk -F '[-.]' '{print $1}').bn"
					fi
					po2lmo $po $dst/usr/lib/lua/luci/i18n/$po_name.lmo
				}
			done
		done
	fi
	# 安装 depends
	[ -f "$src/depends.lst" ] && {
		need_install=
		installed_apk=$(apk info | sed ':a;N;s/\n/ /g;ta')
		depends=$(cat $src/depends.lst)
		for depend in $depends
		do
			[ -n "$(echo $depend | grep -E '^[^_]+')" ] && \
			[ -z "$(echo $installed_apk | grep $depend)" ] && {
				need_install="$need_install $depend"
			}
		done
		[ -n "$need_install" ] && log_info "\tInstalling depends: $need_install .." && apk add $need_install
	}
	# 执行 postinst
	[ -f "$src/postinst" ] && log_info "\tExecuting postinst.."	&& chmod +x $src/postinst && $src/postinst
}

merge_plugins() {
	directory=$1
	for d in $(find $directory/* -maxdepth 0 -type d 2&>/dev/null | sort -g)
	do
		local valid_d=$(echo $d | awk -F'/' '{print $NF}' | grep -E "^[^_]+")
		# 跳过_开头的插件
		[ -n "$valid_d" ] && {
			local valid_d2=$(find $d -iname Makefile -type f -exec dirname {} ';' | sort -g)
			# 插件中存在 makefile, 则认定其为有效插件
			[ -n "$valid_d2" ] && {
				for plugin in $valid_d2
				do
					merge $plugin $LUCI_SYSROOT
				done
			}
		}
	done
}

merge_luci_root() {
	log_info "MERGING LUCI ROOT.."
	mkdir -p $LUCI_SYSROOT
	mkdir -p $PLUGIN_DIR
	mkdir -p $CONFIG_DIR/config
	rm -fr $LUCI_SYSROOT/*

	log_info "MERGING INTERNAL PLUGIN.."
	merge_plugins $INTERNAL_PLUGIN_DIR

	log_info "MERGING EXTERNAL PLUGIN.."
	merge_plugins $PLUGIN_DIR

	chmod +x $LUCI_SYSROOT/etc/init.d/*

	log_info "Linking rc.common.."
	ln -sf $LUCI_SYSROOT/etc/rc.common /etc/rc.common

	log_info "Linking /www.."
	rm /www
	ln -sf $LUCI_SYSROOT/www /www

	log_info "Creating nobody session.."
	mkdir -p /tmp/luci-sessions
	echo '{"acls":{"access-group":{"unauthenticated":["read"]},"ubus":{"luci":["getFeatures"],"session":["access","login"]}},"data":{},"atime":-1,"session":"00000000000000000000000000000000"}' > /tmp/luci-sessions/00000000000000000000000000000000 && \
	chmod 700 /tmp/luci-sessions && \
	chmod 600 /tmp/luci-sessions/00000000000000000000000000000000
}

start_uhttpd() {
	log_info "Starting uhttpd.."
	kill -9 $(pidof uhttpd) &> /dev/null
	rm -fr /tmp/luci-modulecache &> /dev/null
	rm -fr /tmp/luci-indexcache* &> /dev/null
	$LUCI_SYSROOT/usr/sbin/uhttpd -p 80 -t 1200 -h $LUCI_SYSROOT/www -f &
}

link_config() {
	log_info "Linking config.."
	rm $UCI_CONFIG_DIR
	mkdir -p $CONFIG_DIR/config
	ln -sf $CONFIG_DIR/config $UCI_CONFIG_DIR

	log_info "Linking rc.local.."
	[ ! -f "$CONFIG_DIR/rc.local" ] && touch $CONFIG_DIR/rc.local
	ln -sf $CONFIG_DIR/rc.local /etc/rc.local

	log_info "Updating shadow.."
	[ ! -f "$CONFIG_DIR/shadow" ] && cp /etc/shadow $CONFIG_DIR/shadow || cp $CONFIG_DIR/shadow /etc/shadow 
}

run_rcloal() {
	log_info "Executing rc.local.."
	chmod +x /etc/rc.local
	/etc/rc.local
}

update_internal_plugin(){
	log_info "Updating internal plugins.."
	local tmp_dir="/tmp/plugin"
	mkdir -p ${tmp_dir}

	log_info "Updating dockerman.."
	local dockerman="https://github.com/lisaac/luci-app-dockerman/archive/master.zip"
	wget ${dockerman} -O ${tmp_dir}/dockerman.zip
	unzip ${tmp_dir}/dockerman.zip "*/applications/luci-app-dockerman/*" -o -d ${tmp_dir}

	log_info "Updating lib-docker.."
	local libdocker="https://github.com/lisaac/luci-lib-docker/archive/master.zip"
	wget ${libdocker} -O ${tmp_dir}/libdocker.zip
	unzip ${tmp_dir}/libdocker.zip "*/collections/luci-lib-docker/*" -o -d ${tmp_dir}

	log_info "Updating diskman.."
	local diskman="https://github.com/lisaac/luci-app-diskman/archive/master.zip"
	wget ${diskman} -O ${tmp_dir}/diskman.zip
	unzip ${tmp_dir}/diskman.zip "*/applications/luci-app-diskman/*" -o -d ${tmp_dir}

	log_info "Updating podsamba.."
	local podsamba="https://github.com/lisaac/luci-app-podsamba/archive/master.zip"
	wget ${podsamba} -O ${tmp_dir}/podsamba.zip
	unzip ${tmp_dir}/podsamba.zip "*/applications/luci-app-podsamba/*" -o -d ${tmp_dir}

	log_info "Updating podminidlna.."
	local podminidlna="https://github.com/lisaac/luci-app-podminidlna/archive/master.zip"
	wget ${podminidlna} -O ${tmp_dir}/podminidlna.zip
	unzip ${tmp_dir}/podminidlna.zip "*/applications/luci-app-podminidlna/*" -o -d ${tmp_dir}

	# log_info "Updating podclash.."
	# local podclash="https://github.com/lisaac/luci-app-podclash/archive/main.zip"
	# wget ${podclash} -O ${tmp_dir}/podclash.zip
	# unzip ${tmp_dir}/podclash.zip "*/applications/luci-app-podclash/*" -o -d ${tmp_dir}

	cp -R ${tmp_dir}/*/applications/* ${INTERNAL_PLUGIN_DIR}
	cp -R ${tmp_dir}/*/collections/* ${INTERNAL_PLUGIN_DIR}

	rm -fr ${tmp_dir}
}

case $1 in
	env)
		init_env 2>&1 | tee -a /tmp/daemon.log
		;;

	start)
		init_env 2>&1 | tee -a /tmp/daemon.log
		link_config 2>&1 | tee -a /tmp/daemon.log
		merge_luci_root 2>&1 | tee -a /tmp/daemon.log
		start_uhttpd 2>&1 | tee -a /tmp/daemon.log &
		;;

	stop)
		init_env 2>&1 | tee -a /tmp/daemon.log
		kill -9 $(pidof uhttpd) &> /dev/null;;

	daemon)
		init_env 2>&1 | tee -a /tmp/daemon.log
		link_config 2>&1 | tee -a /tmp/daemon.log
		merge_luci_root 2>&1 | tee -a /tmp/daemon.log
		run_rcloal 2>&1 | tee -a /tmp/daemon.log
		start_uhttpd 2>&1 | tee -a /tmp/daemon.log &
		tail -f /dev/null;;

	restart)
		init_env 2>&1 | tee -a /tmp/daemon.log
		link_config 2>&1 | tee -a /tmp/daemon.log
		merge_luci_root 2>&1 | tee -a /tmp/daemon.log
		start_uhttpd 2>&1 | tee -a /tmp/daemon.log &
		;;

	merge)
		init_env 2>&1 | tee -a /tmp/daemon.log
		merge 2>&1 | tee -a /tmp/daemon.log
		;;

	update)
		init_env 2>&1 | tee -a /tmp/daemon.log
		update_internal_plugin 2>&1 | tee -a /tmp/daemon.log
		;;

	*)
		init_env 2>&1 | tee -a /tmp/daemon.log
		link_config 2>&1 | tee -a /tmp/daemon.log
		merge_luci_root 2>&1 | tee -a /tmp/daemon.log
		start_uhttpd 2>&1 | tee -a /tmp/daemon.log &
		;;
esac