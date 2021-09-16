# LuCI in Docker
[![License](https://img.shields.io/github/license/lisaac/luci-in-docker?style=flat-square)](https://github.com/lisaac/luci-in-docker/blob/master/LICENSE)
[![Telegram Group](https://img.shields.io/badge/telegam-group-_?style=flat-square)](https://t.me/joinchat/G5mqjhrlU9S8TMkXeBmj0w)
- 在使用 `Docker` 的过程中，很多容器的配置文件需要管理，使用过程中不少人对命令行及配置文件不熟悉，所以考虑将 `luci` 装入容器，配合 [`luci-lib-docker`](https://github.com/lisaac/luci-lib-docker) 以进行 `Docker` 容器的配置文件管理
- `luci-in-docker` 将 `openwrt` 中 `ubus` 去除，宿主为 `alpine`，方便后期增加插件
- `luci-in-docker` 目的是将家用 `NAS` 服务全部部署在 `Docker` 中，并通过 `luci` 进行管理，从而实现 `NAS IN DOCKER`

## [`lisaac/luci:latest`](https://hub.docker.com/r/lisaac/luci)
> [`lisaac/luci:latest`](https://hub.docker.com/r/lisaac/luci) 内置 [`luci-app-dockerman`](https://github.com/lisaac/luci-app-dockerman) [`luci-app-diskman`](https://github.com/lisaac/luci-app-diskman) [`luci-app-podsamba`](https://github.com/lisaac/luci-app-podsamba) 等常用插件（陆续增加，以实现简单 NAS 功能），需要骨架 `luci` 请使用 `lisaac/luci:nano`

> tips: 由于 `luci-app-diskman` `luci-app-dockerman` 中的依赖较多，第一次启动安装依赖可能会比较慢，需要多等一会，通过 `docker logs luci` 可以看到运行日志
```
docker pull lisaac/luci:latest
docker run -d \
  --name luci \
  --restart unless-stopped \
  --privileged \
  -p 80:80 \
  -p 7682:7682 \
  -e TZ=Asia/Shanghai \
  -v $HOME/pods/luci:/external:rslave \
  -v /media:/media:rshared \
  -v /dev:/dev:rslave \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --tmpfs /tmp:exec \
  --tmpfs /run \
  lisaac/luci:latest
```

## [`lisaac/luci:nano`](https://hub.docker.com/r/lisaac/luci)
- [`lisaac/luci:nano`](https://hub.docker.com/r/lisaac/luci) 版本只包含 `luci` 骨架，不含内置插件, 可以根据自己需要安装插件，插件目录结构请参考下一章节。
```
docker pull lisaac/luci:nano
docker run -d \
  --name luci \
  --restart unless-stopped \
  --privileged \
  -p 80:80 \
  -p 7682:7682 \
  -e TZ=Asia/Shanghai \
  -v $HOME/pods/luci:/external:rslave \
  -v /media:/media:rshared \
  -v /dev:/dev:rslave \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --tmpfs /tmp:exec \
  --tmpfs /run \
  lisaac/luci:nano
```

## 目录结构
```
/
  |- external         # 外部目录，需要外部挂载
    |-cfg.d
      |-config        # UCI cofnig 目录，用于存放配置文件，启动后 link 至/etc/config
      |-crontab       # crontab
      |-periodic      # crond 定期执行目录
      |-rc.local      # rc.local 本地启动执行脚本
      |-shadow        # 密码保存
    |-plugin          # 插件目录
      |-luci-app-diskman    # 插件，会忽略以 _ 开头的目录，方便调试，插件结构如下：
        |-Makefile    # 判定有效插件目录标志
        |-root        # 插件所需的 root 目录，合并至/tmp/.luci/
        |-luasrc      # 插件所需的 lua 文件目录，合并至/tmp/.luci/usr/lib/lua/luci
        |-htdoc       # 插件所需的 html 文件目录，合并至/tmp/.luci/www
        |-po          # 插件所需的 po 文件目录
        |-depends.lst # 插件所需要 alpine 依赖列表文件, 依赖用' '隔开, 只用来存放 alpine 依赖
        |-preinst     # 插件所需的初始化脚本(合并前)
        |-postinst    # 插件所需的初始化脚本(合并后), 若没有此脚本, 会尝试执行 /root/etc/uci-defaults/ 下的插件初始化脚本
      |-...
  |- internal         # 内部 luci-in-docker 自带插件目录(用户无需关心)
    |-plugin          # 内部插件目录
      |-luci          # luci 目录
        |-Makefile    # 判定有效插件目录标志
        |-root        # 插件所需的 root 目录，合并至/tmp/.luci/
        |-luasrc      # 插件所需的 lua 文件目录，合并至/tmp/.luci/usr/lib/lua/luci
        |-htdoc       # 插件所需的 html 文件目录，合并至/tmp/.luci/www
        |-po          # 插件所需的 po 文件目录
        |-depends.lst # 插件所需要 alpine 依赖列表文件, 依赖用' '隔开, 只用来存放 alpine 依赖
        |-preinst     # 插件所需的初始化脚本(合并前)
        |-postinst    # 插件所需的初始化脚本(合并后)
      |-...
  |tmp
    |-.luci           # 合并后的 luci root 目录
```
- 通过遍历 `internal/external` 目录下 `plugin` 中的各个插件目录，将其合并至 `/temp/.luci` 目录中，并修改 `path` 环境变量
- 同时保证兼容性和持久性 `config` 目录存储位置为 `external/cfg.d/config`, 挂载至 `/etc/config`
- 遍历时先执行`preinst`，插件目录合并到 `/temp/.luci` 后，会通过 `apk add` 方式安装插件目录下 `depends.lst` 中需要的依赖，最后执行插件目录下 `postinst`

## 插件

- 插件合并时不会执行按照 `Makefile` 编译，所以需要编译完成后 `ipk` 中的 `data` 目录中的内容，或者纯 `lua` 源码 + 二进制文件
- 插件中 `po` 目录下的翻译文件会自动转换成对应 `lmo`，并合并至 `luci/i18n` 目录
- 插件中依赖文件 `depends.lst` 为 `alpine` 依赖，并非 `openwrt` 中的依赖
- 插件中的 `preinst`及 `postinst` 是在遍历插件目录执行的，可能执行 `preinst` 及 `postinst` 存在依赖其他插件的情况，可以将插件目录开头的加上数字，来确定遍历顺序
- 插件目录名若以 `_` 开头，则会跳过此插件

## 谢致
- [openwrt/luci](https://github.com/openwrt/luci)
- [openwrt/openwrt](https://github.com/openwrt/openwrt)