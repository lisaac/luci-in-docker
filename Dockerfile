FROM alpine:edge as compile_stage

MAINTAINER lisaac <lisaac.cn@gmail.com>

#sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
RUN sed -i -e '/^http:\/\/.*\/main/h' -e'$G' -e '${s|\(^http://.*/\)main|\1testing|}' /etc/apk/repositories && \
    apk update && \
    apk add git cmake make gcc libc-dev json-c-dev lua5.1 lua5.1-dev openssl-dev linux-headers && \
    # libubox
    cd /tmp && git clone https://git.openwrt.org/project/libubox.git && \
    cd /tmp/libubox && cmake . && make && make install && \
    # uci
    cd /tmp && git clone https://git.openwrt.org/project/uci.git && \
    cd /tmp/uci && cmake . && make && \
    # ustream-ssl
    cd /tmp && git clone https://git.openwrt.org/project/ustream-ssl.git && \
    cd /tmp/ustream-ssl && cmake . && make && make install && \
    # uhttpd
    cd /tmp && git clone https://git.openwrt.org/project/uhttpd.git && \
    cd /tmp/uhttpd && sed -i 's/clearenv();/\/\/clearenv();/g' cgi.c && \
    cmake -DUBUS_SUPPORT=OFF . && make && cd /tmp && \
    # libnl-tiny
    cd /tmp && git clone https://git.openwrt.org/project/libnl-tiny.git && \
    cd /tmp/libnl-tiny/src && sed -i 's/^CFLAGS=/CFLAGS=-fPIC /g' Makefile && make && \
    mkdir -p /usr/lib && cp *.so /usr/lib/ && cp -R /tmp/libnl-tiny/src/include/* /usr/include/ && \
    # luci
    cd /tmp && git clone https://github.com/openwrt/luci.git && cd /tmp/luci && git checkout openwrt-18.06 && \
    # luci-lib-ip
    cd /tmp/luci/libs/luci-lib-ip/src && make && \
    # luci-lib-jsonc
    cd /tmp/luci/libs/luci-lib-jsonc/src && make && \
    # luci-lib-nixio
    cd /tmp/luci/libs/luci-lib-nixio/src && \
    sed -i 's/^CFLAGS *+=/CFLAGS       += -fPIC /g' Makefile && make && \
    # parser.so & po2lmo
    cd /tmp/luci/modules/luci-base/src && sed -i '1i\CFLAGS += -fPIC' Makefile && \
    make parser.so && make po2lmo && \
    # liblucihttp
    cd /tmp/ && git clone https://github.com/jow-/lucihttp.git && \
    cd /tmp/lucihttp && cmake . && make && \
    # copy to dst
    mkdir -p /tmp/dst/lib && mkdir -p /tmp/dst/lua && mkdir -p /tmp/dst/bin && mkdir -p /tmp/dst/luci/template && \
    cp /tmp/libubox/*.so /tmp/dst/lib/ && cp /tmp/libubox/lua/*.so /tmp/dst/lua/ && \
    cp /tmp/ustream-ssl/*.so /tmp/dst/lib/ && \
    cp /tmp/uci/*.so /tmp/dst/lib/ && cp /tmp/uci/lua/*.so /tmp/dst/lua/ && cp /tmp/uci/uci /tmp/dst/bin/ && \
    cp /tmp/uhttpd/*.so /tmp/dst/lib/ && cp /tmp/uhttpd/uhttpd /tmp/dst/bin/ && \
    cp /tmp/libnl-tiny/src/*.so /tmp/dst/lib/ && \
    cp /tmp/luci/libs/luci-lib-ip/src/*.so /tmp/dst/luci/ && \
    cp /tmp/luci/libs/luci-lib-jsonc/src/*.so /tmp/dst/luci/ && \
    cp /tmp/luci/libs/luci-lib-nixio/src/*.so  /tmp/dst/lua/ && \
    cp /tmp/lucihttp/lucihttp.so /tmp/dst/lua && cp /tmp/lucihttp/liblucihttp.so* /tmp/dst/lib && \
    cp /tmp/luci/modules/luci-base/src/po2lmo /tmp/dst/bin/ && \
    cp /tmp/luci/modules/luci-base/src/parser.so /tmp/dst/luci/template

FROM alpine:edge

ENV PLUGIN_DIR='/external/plugin' CONFIG_DIR='/external/cfg.d' ORIGINAL_DIR='/.luci'

RUN sed -i -e '/^http:\/\/.*\/main/h' -e'$G' -e '${s|\(^http://.*/\)main|\1testing|}' /etc/apk/repositories && \
    apk  --no-cache update && \
    apk -no-cache add lua5.1 json-c libgcc tzdata && \
    mkdir $ORIGINAL_DIR && \
    ln -s /usr/lib/liblua.so.5 /usr/lib/liblua.so.5.1.5 && \
    wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
    cd /tmp && wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.30-r0/glibc-2.30-r0.apk && \
    apk -no-cache add glibc-2.30-r0.apk && rm /tmp/glibc-2.30-r0.apk

COPY init.sh /
COPY root $ORIGINAL_DIR
COPY --from=compile_stage /tmp/dst/lib $ORIGINAL_DIR/usr/lib/
COPY --from=compile_stage /tmp/dst/lua $ORIGINAL_DIR/usr/lib/lua/
COPY --from=compile_stage /tmp/dst/luci $ORIGINAL_DIR/usr/lib/lua/luci
COPY --from=compile_stage /tmp/dst/bin $ORIGINAL_DIR/usr/sbin/

RUN chmod +x /init.sh
EXPOSE 80/tcp

CMD ["/init.sh","daemon"]