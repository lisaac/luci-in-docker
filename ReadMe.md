## 关于 LuCI in Docker
在使用docker的过程中，很多容器的配置文件需要管理，使用过程中不少人对命令行及配置文件不熟悉，所以考虑将luci装入容器，以进行docker容器的配置文件管理。
`luci-in-docker`将`openwrt`中`ubus`去除，宿主为`alpine`，方便后期增加插件。

## 目录结构
```
/
  |-.luci             # luci原始目录
  |- external         # 外部目录，一般为容器外部挂载
    |-cfg.d           # cofnig目录，用于存放配置文件，启动后挂载至/etc/config
    |-plugin          # 插件目录
      |-luci-samba    # 插件，会忽略以 _ 开头的目录，方便调试，插件结构如下：
        |-root        # 插件所需的 root 目录，合并至/tmp/.luci/
        |-luasrc      # 插件所需的 lua 文件目录，合并至/tmp/.luci/usr/lib/lua/luci
        |-htdoc       # 插件所需的 html 文件目录，合并至/tmp/.luci/www
        |-po          # 插件所需的 po 文件目录
  |tmp
    |-.luci           # luci root目录
```

## 运行容器
```
docker run -dit \
  --name luci-in-docker \
  --restart unless-stopped \
  --privileged \
  --network dMACvLAN --ip 10.1.1.253 \
  -e TZ=Asia/Shanghai \
  -v $HOME/.docker/lucitest:/external:rslave \
  -v /media:/media:rshared \
  -v /dev:/dev \
  -v /usr/bin/docker:/usr/bin/docker \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --tmpfs /tmp:exec \
  --tmpfs /run \
  lisaac/luci /bin/sh
```