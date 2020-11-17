FROM alpine:latest as compile_stage

LABEL maintainer='lisaac <lisaac.cn@gmail.com>'

RUN apk --no-cache update && \ 
    apk --no-cache add git && \
    cd /tmp/ && \
    git clone https://github.com/lisaac/luci-lib-docker.git && \
    git clone https://github.com/lisaac/luci-app-dockerman.git && \
    git clone https://github.com/lisaac/luci-app-diskman.git && \
    mkdir -p /plugin && \
    cp -R /tmp/luci-lib-docker /collections/luci-lib-docker       /plugin/luci-lib-docker && \
    cp -R /tmp/luci-app-dockerman/applications/luci-app-dockerman   /plugin/luci-app-dockerman && \
    cp -R /tmp/luci-app-diskman/applications/luci-app-diskman     /plugin/luci-app-diskman && \
    cp -R /tmp/luci-app-podclash/applications/luci-app-podclash    /plugin/luci-app-podclash
    # cp -R /tmp/luci-app-podsamba/applications/luci-app-podsamba    /plugin/luci-app-podsamba && \
    # cp -R /tmp/luci-app-podminidlna/applications/luci-app-podminidlna /plugin/luci-app-podminidlna

FROM lisaac/luci:nano

ENV PLUGIN_DIR='/external/plugin' CONFIG_DIR='/external/cfg.d/config' INTERNAL_PLUGIN_DIR='/internal/plugin' TZ=Asia/Shanghai

COPY --from=compile_stage /plugin $INTERNAL_PLUGIN_DIR/

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

EXPOSE 80/tcp

CMD ["tini", "--", "/init.sh", "daemon"]
