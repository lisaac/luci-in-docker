#!/bin/sh

PLUGIN_DIR='/external/plugin'
CONFIG_DIR='/external/cfg.d'
INTERNAL_PLUGIN_DIR='/internal/plugin'
export LUCI_SYSROOT='/tmp/.luci' #`cd $1; pwd`
export IPKG_INSTROOT=$LUCI_SYSROOT
export LD_LIBRARY_PATH="$LUCI_SYSROOT/usr/lib:$LD_LIBRARY_PATH"
export PATH="$LUCI_SYSROOT/bin:$LUCI_SYSROOT/sbin:$LUCI_SYSROOT/usr/sbin:$LUCI_SYSROOT/usr/bin:$PATH"
export LUA_PATH="$LUCI_SYSROOT/usr/lib/lua/?.lua;$LUCI_SYSROOT/usr/lib/lua/?/init.lua;;"
export LUA_CPATH="$LUCI_SYSROOT/usr/lib/lua/?.so;;"
export DYLD_LIBRARY_PATH="$LUCI_SYSROOT/usr/lib:$DYLD_LIBRARY_PATH"

installed_apk=$(apk info | sed ':a;N;s/\n/ /g;ta')

merge() {
  echo "Merging plugin $1.."
  src=$1
  dst=$2
  mkdir -p $dst
    # 执行 preinst
  [ -f "$src/preinst" ] && echo -e "\tExecuting preinst.."  && chmod +x $src/preinst && $src/preinst
  #合并root
  [ -d "$src/root" ] && cp -R $src/root/. $dst/ &&\
  #合并config
  mkdir -p $dst/etc/config
  if [ -d "$src/root/etc/config" ]; then
    for cfg in $src/root/etc/config/*
    do
      if [ -f "$cfg" ]; then
        cfg_name=$(echo $cfg | awk -F'/' '{print $NF}')
        [ ! -f $CONFIG_DIR/config/$cfg_name ] && cp $cfg $CONFIG_DIR/config/
      elif [ -d "$cfg" ]; then
        cfg_name=$(basename $cfg)
        [ ! -d $CONFIG_DIR/config/$cfg_name ] && cp -R $cfg $CONFIG_DIR/config/
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
          po2lmo $po $dst/usr/lib/lua/luci/i18n/$po_name.lmo
        }
      done
    done
  fi
  # 安装 depends
  [ -f "$src/depends.lst" ] && {
    depends=$(cat $src/depends.lst)
    for depend in $depends
    do
      [ -n "$(echo $depend | grep -E '^[^_]+')" ] && \
      [ -z "$(echo $installed_apk | grep $depend)" ] && \
      need_install="$need_install $depend"
    done
    [ -n "$need_install" ] && echo -e "\tInstalling depends.." && apk add $need_install
  }
  # 执行 postinst
  [ -f "$src/postinst" ] && echo -e "\tExecuting postinst.."  && chmod +x $src/postinst && $src/postinst
}

merge_luci_root() {
  echo "MERGING LUCI ROOT.."
  mkdir -p $LUCI_SYSROOT
  mkdir -p $PLUGIN_DIR
  mkdir -p $CONFIG_DIR/config
  rm -fr $LUCI_SYSROOT/*

  echo "MERGING INTERNAL PLUGIN.."
  for d in $INTERNAL_PLUGIN_DIR/*
  do
    local valid_d=$(echo $d | awk -F'/' '{print $NF}' | grep -E "^[^_]+")
    [ -n "$valid_d" ] && \
    local valid_d2=$(find $d -iname Makefile -type f -exec dirname {} ';' | head -n 1)
      # 目录中存在 makefile 则认定其为 luasrc/root/po/htdoc 有效目录
    [ -n "$valid_d2" ] && \
    merge $valid_d2 $LUCI_SYSROOT
  done

  echo "MERGING EXTERNAL PLUGIN.."
  for d in $PLUGIN_DIR/*
  do
    local valid_d=$(echo $d | awk -F'/' '{print $NF}' | grep -E "^[^_]+")
    [ -n "$valid_d" ] && \
    local valid_d2=$(find $d -iname Makefile -type f -exec dirname {} ';' | head -n 1)
    # 目录中存在 makefile 则认定其为 luasrc/root/po/htdoc 有效目录
    [ -n "$valid_d2" ] && \
    merge $valid_d2 $LUCI_SYSROOT
  done

  chmod +x $LUCI_SYSROOT/etc/init.d/*
  
  echo "Mounting rc.common.."
  touch /etc/rc.common
  umount /etc/rc.common 2&> /dev/null
  mount -o bind $LUCI_SYSROOT/etc/rc.common /etc/rc.common
}

start_uhttpd() {
  echo "Starting uhttpd.."
  rm -fr /tmp/luci-*
  $LUCI_SYSROOT/usr/sbin/uhttpd -p 80 -t 1200 -h $LUCI_SYSROOT/www -f &
}

mount_config() {
  echo "Mounting config.."
  mkdir -p /etc/config
  mkdir -p $CONFIG_DIR/config
  umount /etc/config 2&> /dev/null
  mount -o bind $CONFIG_DIR/config /etc/config
  [ ! -f "$CONFIG_DIR/rc.local" ] && touch $CONFIG_DIR/rc.local
  [ ! -f "/etc/rc.local" ] && touch /etc/rc.local
  umount /etc/rc.local 2&> /dev/null
  mount -o bind $CONFIG_DIR/rc.local /etc/rc.local
}

run_rcloal() {
  chmod +x /etc/rc.local
  /etc/rc.local
}

update_internal_plugin(){
  echo "Updating internal plugins.."
  local tmp_dir="/tmp/plugin"
  mkdir -p ${tmp_dir}

  echo "Updating dockerman.."
  local dockerman="https://github.com/lisaac/luci-app-dockerman/archive/master.zip"
  wget ${dockerman} -O ${tmp_dir}/dockerman.zip
  unzip ${tmp_dir}/dockerman.zip "*/applications/luci-app-dockerman/*" -o -d ${tmp_dir}

  echo "Updating lib-docker.."
  local libdocker="https://github.com/lisaac/luci-lib-docker/archive/master.zip"
  wget ${libdocker} -O ${tmp_dir}/libdocker.zip
  unzip ${tmp_dir}/libdocker.zip "*/collections/luci-lib-docker/*" -o -d ${tmp_dir}

  echo "Updating diskman.."
  local diskman="https://github.com/lisaac/luci-app-diskman/archive/master.zip"
  wget ${diskman} -O ${tmp_dir}/diskman.zip
  unzip ${tmp_dir}/diskman.zip "*/applications/luci-app-diskman/*" -o -d ${tmp_dir}

  echo "Updating podsamba.."
  local podsamba="https://github.com/lisaac/luci-app-podsamba/archive/master.zip"
  wget ${podsamba} -O ${tmp_dir}/podsamba.zip
  unzip ${tmp_dir}/podsamba.zip "*/applications/luci-app-podsamba/*" -o -d ${tmp_dir}

  echo "Updating podminidlna.."
  local podminidlna="https://github.com/lisaac/luci-app-podminidlna/archive/master.zip"
  wget ${podminidlna} -O ${tmp_dir}/podminidlna.zip
  unzip ${tmp_dir}/podminidlna.zip "*/applications/luci-app-podminidlna/*" -o -d ${tmp_dir}

  # echo "Updating podclash.."
  # local podclash="https://github.com/lisaac/luci-app-podclash/archive/main.zip"
  # wget ${podclash} -O ${tmp_dir}/podclash.zip
  # unzip ${tmp_dir}/podclash.zip "*/applications/luci-app-podclash/*" -o -d ${tmp_dir}

  cp -R ${tmp_dir}/*/applications/* ${INTERNAL_PLUGIN_DIR}
  cp -R ${tmp_dir}/*/collections/* ${INTERNAL_PLUGIN_DIR}

  rm -fr ${tmp_dir}
}

case $1 in
  start)         merge_luci_root; mount_config; start_uhttpd;;
  stop)          kill -9 $(pidof uhttpd) &> /dev/null;;
  daemon)        merge_luci_root; mount_config; start_uhttpd; run_rcloal; tail -f /dev/null;;
  restart)       kill -9 $(pidof uhttpd) &> /dev/null; merge_luci_root; mount_config; start_uhttpd;;
  merge)         merge;;
  update)        update_internal_plugin;;
  *)             kill -9 $(pidof uhttpd) &> /dev/null; merge_luci_root; mount_config; start_uhttpd;;
esac
