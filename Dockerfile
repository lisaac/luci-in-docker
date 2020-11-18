FROM lisaac/luci:nano

LABEL maintainer='lisaac <lisaac.cn@gmail.com>'

RUN /init.sh update

EXPOSE 80/tcp

CMD ["tini", "--", "/init.sh", "daemon"]
