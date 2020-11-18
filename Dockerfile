FROM lisaac/luci:nano

LABEL maintainer='lisaac <lisaac.cn@gmail.com>'

ENV PLUGIN_DIR='/external/plugin' CONFIG_DIR='/external/cfg.d/config' INTERNAL_PLUGIN_DIR='/internal/plugin' TZ=Asia/Shanghai

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && /init.sh update

EXPOSE 80/tcp

CMD ["tini", "--", "/init.sh", "daemon"]
