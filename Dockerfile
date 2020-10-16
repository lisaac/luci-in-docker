FROM alpine:latest as compile_stage

LABEL maintainer='lisaac <lisaac.cn@gmail.com>'

ENV DST_LUCI_ROOT='/tmp/dst/luci/root'

COPY root $DST_LUCI_ROOT
COPY po /tmp/dst/luci/po
#sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories && \
#sed -i -e '/^http:\/\/.*\/main/h' -e'$G' -e '${s|\(^http://.*/\)main|\1testing|}' /etc/apk/repositories && \
RUN apk update && \
    apk add git cmake make gcc libc-dev json-c-dev lua5.1 lua5.1-dev openssl-dev linux-headers && \
    # libubox
    cd /tmp && git clone https://git.openwrt.org/project/libubox.git && \
    cd /tmp/libubox && \
    # git checkout 43a103ff17ee5872669f8712606578c90c14591d && \
    cmake . && make && make install && \
    # uci
    cd /tmp && git clone https://git.openwrt.org/project/uci.git && \
    cd /tmp/uci && \
    # git checkout 165b444131453d63fc78c1d86f23c3ca36a2ffd7 && \
    cmake . && make && \
    # ustream-ssl
    cd /tmp && git clone https://git.openwrt.org/project/ustream-ssl.git && \
    cd /tmp/ustream-ssl && \
    # git checkout 30cebb4fc78e49e0432a404f7c9dd8c9a93b3cc3 && \
    cmake . && make && make install && \
    # uhttpd
    cd /tmp && git clone https://git.openwrt.org/project/uhttpd.git && \
    cd /tmp/uhttpd && \
    # git checkout 5f9ae5738372aaa3a6be2f0a278933563d3f191a && \
    sed -i 's/clearenv();/\/\/clearenv();/g' cgi.c && \
    cmake -DUBUS_SUPPORT=OFF . && make && cd /tmp && \
    # libnl-tiny
    cd /tmp && git clone https://git.openwrt.org/project/libnl-tiny.git && \
    cd /tmp/libnl-tiny && \
    # git checkout 0219008cc8767655d7e747497e8e1133a3e8f840 && \
    cmake . && make && \
    mkdir -p /usr/lib && cp *.so /usr/lib/ && cp -R /tmp/libnl-tiny/include/* /usr/include/ && \
    # liblucihttp
    cd /tmp/ && git clone https://github.com/jow-/lucihttp.git && \
    cd /tmp/lucihttp && \
    # git checkout a34a17d501c0e23f0a91dd9d3e87697347c861ba && \
    cmake . && make && \
    # luci
    cd /tmp && git clone https://github.com/openwrt/luci.git && \
    cd /tmp/luci && git checkout openwrt-18.06 && \
    # luci-lib-ip
    cd /tmp/luci/libs/luci-lib-ip/src && make && \
    # luci-lib-jsonc
    cd /tmp/luci/libs/luci-lib-jsonc/src && \
    sed -i 's/return json_object_new_int(nd);/return json_object_new_int64(nd);/g' jsonc.c && make && \
    # luci-lib-nixio
    cd /tmp/luci/libs/luci-lib-nixio/src && \
    sed -i 's/^CFLAGS *+=/CFLAGS       += -fPIC /g' Makefile && make && \
    # parser.so & po2lmo
    cd /tmp/luci/modules/luci-base/src && sed -i '1i\CFLAGS += -fPIC' Makefile && \
    make parser.so && make po2lmo && \
    # make jsmin && \
    # copy to dst
    mkdir -p $DST_LUCI_ROOT/usr/lib $DST_LUCI_ROOT/usr/lib/lua $DST_LUCI_ROOT/usr/sbin $DST_LUCI_ROOT/usr/bin $DST_LUCI_ROOT/usr/local/share/libubox/ $DST_LUCI_ROOT/usr/lib/lua/luci/template $DST_LUCI_ROOT/www && \
    cp /tmp/libubox/*.so $DST_LUCI_ROOT/usr/lib/ && cp /tmp/libubox/lua/*.so $DST_LUCI_ROOT/usr/lib/lua/ && cp /tmp/libubox/jshn $DST_LUCI_ROOT/usr/bin && cp /tmp/libubox/sh/jshn.sh $DST_LUCI_ROOT/usr/local/share/libubox/ && \
    cp /tmp/ustream-ssl/*.so $DST_LUCI_ROOT/usr/lib/ && \
    cp /tmp/uci/*.so $DST_LUCI_ROOT/usr/lib/ && cp /tmp/uci/lua/*.so $DST_LUCI_ROOT/usr/lib/lua/ && cp /tmp/uci/uci $DST_LUCI_ROOT/usr/sbin/ && \
    cp /tmp/uhttpd/*.so $DST_LUCI_ROOT/usr/lib/ && cp /tmp/uhttpd/uhttpd $DST_LUCI_ROOT/usr/sbin/ && \
    cp /tmp/libnl-tiny/*.so $DST_LUCI_ROOT/usr/lib/ && \
    cp /tmp/luci/libs/luci-lib-ip/src/*.so $DST_LUCI_ROOT/usr/lib/lua/luci/ && \
    cp /tmp/luci/libs/luci-lib-jsonc/src/*.so $DST_LUCI_ROOT/usr/lib/lua/luci/ && \
    cp /tmp/luci/libs/luci-lib-nixio/src/*.so  $DST_LUCI_ROOT/usr/lib/lua/ && \
    cp /tmp/lucihttp/lucihttp.so $DST_LUCI_ROOT/usr/lib/lua && cp /tmp/lucihttp/liblucihttp.so* $DST_LUCI_ROOT/usr/lib && \
    cp /tmp/luci/modules/luci-base/src/po2lmo $DST_LUCI_ROOT/usr/sbin/ && \
    # cp /tmp/luci/modules/luci-base/src/jsmin $DST_LUCI_ROOT/usr/sbin/ && \
    cp /tmp/luci/modules/luci-base/src/parser.so $DST_LUCI_ROOT/usr/lib/lua/luci/template

FROM alpine:latest

ENV PLUGIN_DIR='/external/plugin' CONFIG_DIR='/external/cfg.d/config' INTERNAL_PLUGIN_DIR='/internal/plugin' TZ=Asia/Shanghai

RUN apk --no-cache update && \
    apk --no-cache add lua5.1 json-c libgcc tzdata ca-certificates tini && \
    mkdir -p $INTERNAL_PLUGIN_DIR $PLUGIN_DIR $CONFIG_DIR && \
    ln -s /usr/lib/liblua.so.5 /usr/lib/liblua.so.5.1.5 && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY init.sh /
COPY --from=compile_stage /tmp/dst $INTERNAL_PLUGIN_DIR/

RUN chmod +x /init.sh
EXPOSE 80/tcp

CMD ["tini", "--", "/init.sh", "daemon"]
