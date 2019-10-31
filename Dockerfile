FROM alpine as compile_stage

MAINTAINER lisaac <lisaac.cn@gmail.com>

#sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
RUN apk update && \
    apk add git cmake make gcc libc-dev json-c-dev lua5.1 lua5.1-dev openssl-dev && \
    cd /tmp && git clone https://git.openwrt.org/project/libubox.git && \
    cd /tmp/libubox && cmake . && make && make install && \
    cd && git clone https://git.openwrt.org/project/uci.git && \
    cd /tmp/uci && cmake . && make && \
    cd /tmp && git clone https://git.openwrt.org/project/ustream-ssl.git && \
    cd /tmp/ustream-ssl && cmake . && make && make install && \
    cd /tmp && git clone https://git.openwrt.org/project/uhttpd.git &&\
    cd /tmp/uhttpd && sed -i 's/clearenv();/\/\/clearenv();/g' cgi.c && \
    cmake -DUBUS_SUPPORT=OFF . && make && cd /tmp && \
    mkdir -p /tmp/dst/lib && mkdir -p /tmp/dst/lua && mkdir -p /tmp/dst/bin && \
    cp /tmp/libubox/*.so /tmp/dst/lib/ && cp /tmp/libubox/lua/*.so /tmp/dst/lua/ && \
    cp /tmp/ustream-ssl/*.so /tmp/dst/lib/ &&\
    cp /tmp/uci/*.so /tmp/dst/lib/ && cp /tmp/uci/lua/*.so /tmp/dst/lua/ && cp /tmp/uci/uci /tmp/dst/bin/ && \
    cp /tmp/uhttpd/*.so /tmp/dst/lib/ && cp /tmp/uhttpd/lua/*.so /tmp/dst/lua/ && cp /tmp/uhttpd/uhttpd /tmp/dst/bin/

FROM alpine

ENV PLUGIN_DIR='/external/plugin' CONFIG_DIR='/external/cfg.d' ORIGINAL_DIR='/.luci'

RUN apk update && \
    apk add lua5.1 json-c libgcc tzdata smartmontools && \
    mkdir $ORIGINAL_DIR && \
    ln -s /usr/lib/liblua.so.5 /usr/lib/liblua.so.5.1.5

COPY init.sh /
COPY luci $ORIGINAL_DIR
COPY --from=compile_stage /tmp/dst/lib $ORIGINAL_DIR/usr/lib/
COPY --from=compile_stage /tmp/dst/lua $ORIGINAL_DIR/usr/lib/lua/
COPY --from=compile_stage /tmp/dst/bin $ORIGINAL_DIR/usr/sbin/

RUN chmod +x /init.sh