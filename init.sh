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

merge() {
  echo "merging plugin $1.."
  src=$1
  dst=$2
  mkdir -p $dst
  #合并root
  [ -d $src/root ] && cp -R $src/root/. $dst/ &&\
  #合并config
  mkdir -p $dst/etc/config
  if [ -d $src/root/etc/config ]; then
    for cfg in $src/root/etc/config/*
    do
      if [ -f $cfg ]; then
        cfg_name=$(echo $cfg | awk -F'/' '{print $NF}')
        [ ! -f $CONFIG_DIR/config/$cfg_name ] && cp $cfg $CONFIG_DIR/config/
      fi
    done
  fi
  # 合并 luasrc
  mkdir -p $dst/usr/lib/lua/luci/
  [ -d $src/luasrc ] && cp -R $src/luasrc/. $dst/usr/lib/lua/luci/
  # 合并 htdoc
  mkdir -p $dst/www/
  [ -d $src/htdoc ] && cp -R $src/htdoc/. $dst/www/
  # i18n
  mkdir -p $dst/usr/lib/lua/luci/i18n/
  if [ -d $src/po ]; then
    for i18n in $src/po/*
    do
      for po in $i18n/*.po
      do
        po_name=$(echo $po | awk -F'/' '{print $NF}' | awk -F'.' '{print $1}').$(echo $i18n | awk -F'/' '{print $NF}')
        po2lmo $po $dst/usr/lib/lua/luci/i18n/$po_name.lmo
      done
    done
  fi
  # 安装 depends
  [ -f $src/depends.lst ] && depends=$(cat $src/depends.lst) && apk add $depends
}

merge_luci_root() {
  echo "merging luci root.."
  mkdir -p $LUCI_SYSROOT
  mkdir -p $PLUGIN_DIR
  mkdir -p $CONFIG_DIR/config
  rm -fr $LUCI_SYSROOT/*

  echo "mergeing internal plugin.."
  for d in $INTERNAL_PLUGIN_DIR/*
  do
    valid_d=$(echo $d | awk -F'/' '{print $NF}' | grep -E "^[^_].+")
    [ -n "$valid_d" ] && merge $d $LUCI_SYSROOT
  done

  echo "mergeing external plugin.."
  for d in $PLUGIN_DIR/*
  do
    valid_d=$(echo $d | awk -F'/' '{print $NF}' | grep -E "^[^_].+")
    [ -n "$valid_d" ] && merge $d $LUCI_SYSROOT
  done
}

start_uhttpd() {
  echo "starting uhttpd.."
  rm -fr /tmp/luci-*
  $LUCI_SYSROOT/usr/sbin/uhttpd -p 80 -t 1200 -h $LUCI_SYSROOT/www -f &
}

mount_config() {
  echo "mounting config.."
  mkdir -p /etc/config
  mkdir -p $CONFIG_DIR/config
  umount /etc/config 2&> /dev/null
  mount -o bind $CONFIG_DIR/config /etc/config
}

case $1 in
  start)         merge_luci_root ; mount_config ; start_uhttpd;;
  stop)          killall uhttpd &> /dev/null;;
  daemon)        merge_luci_root ; mount_config ; start_uhttpd; tail -f /dev/null;;
  restart)       killall uhttpd &> /dev/null ; merge_luci_root ; mount_config ; start_uhttpd;;
  merge)         merge;;
  *)             killall uhttpd &> /dev/null ; merge_luci_root ; mount_config ; start_uhttpd;;
esac
