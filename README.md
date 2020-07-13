# 一键管理 IPTV / v2ray / Nginx / OpenResty / cloudflare partner,workers / IBM CF 脚本

## A ffmpeg / v2ray / Nginx / OpenResty wrapper (... => hls <=> flv <= ...)

## [演示](http://mtime.info/)

## 一键管理 v2ray 脚本

``` bash
wget -q http://hbo.epub.fun/v2.sh && bash v2.sh

输入 v2 打开 v2ray 管理面板

```

- 多用户多账号管理
- 代理转发账号管理
  
---

## 一键管理 IBM Cloud Foundry 脚本

``` bash
wget -q http://hbo.epub.fun/ibm.sh && bash ibm.sh

输入 ibm 打开 ibm CF 管理面板

- 快捷键: ibm v2 打开 ibm v2ray APP 管理面板

```

- 多 用户、APP、路由 管理, 定时重启 APP
- 管理 v2ray APP
  - 代理端口、账号管理
  - 转发端口管理

---

## 一键管理 cloudflare partner,workers 脚本

``` bash
wget -q http://hbo.epub.fun/cf.sh && bash cf.sh

输入 cf 打开 cloudflare partner,workers 管理面板

- 快捷键: cf w 打开 cloudflare workers 管理面板

```

Mac/Linux 一键获取最优 IP 可以用脚本 [cloudflare-fping](https://github.com/woniuzfb/cloudflare-fping)

- 多 CFP 管理
- 勿更改公开的 CFP host key
- 开启 workers 监控
  - 可以在超过请求数( 默认 100000 )时自动上传 worker 到其他账号并移动域名 CNAME 记录
  - 准备工作
    - 所有账号必须是邮箱验证完成的
    - 在 partner 面板添加源站 CNAME 记录, 所有源站必须在同一 cloudflare 账号
    - 一个 CNAME 对应一个 worker, 否则会出错
    - 如果没有添加 Token (workers 和 zone 编辑权限) 脚本会尝试添加
    - 可以设置中转 IBM CF

---

## 一键管理 nginx 脚本

``` bash
wget -q http://hbo.epub.fun/nx.sh && bash nx.sh

输入 nx 打开 Nginx 管理面板

```

- 多域名管理
  
---

## 一键管理 OpenResty 脚本

``` bash
wget -q http://hbo.epub.fun/or.sh && bash or.sh

输入 or 打开 OpenResty 管理面板

```

- 配置文件和上面的 nginx 不相关

---

## 一键管理 IPTV 脚本 - A ffmpeg wrapper

``` bash
wget -q http://hbo.epub.fun/iptv.sh && bash iptv.sh

始终用最新的脚本，升级方式
  - 通过 tv 面板（推荐）
  或
  - 用这里的 iptv.sh 覆盖 /usr/local/bin/tv ，删除主目录 /usr/local/iptv 下的 lock 文件

```

## 一键管理 xtream codes 频道

``` bash
输入 cx 打开 Xtream Codes 账号/频道 管理面板
```

## 自动解析 youtube, 4gtv, tvb ... 等链接

- 输入 youtube 链接
- 输入 tv 4g 打开 4gtv 频道面板
- 输入凤凰秀(fengshows.cn)直播链接
- 输入 tvb 官网直播页面链接
- 输入 澳门莲花官网免费[直播链接](http://live-hls.macaulotustv.com/lotustv/5562e9e4d409d24c9600075c.m3u8)

## VIP 面板 ING ... [付费]

``` bash
输入 tv v 直接打开 VIP 面板, 享 VIP 直播源
```

- IP 控制
- 自带 m3u, epg
- 出售资源

---

- 自带加密 NODE.JS <- HTTP -> NginX <- HTTPS -> CLIENT
- 自带防护
- 自带监控
- 自带防盗链
- 自建节目表
- 自带 VIP 模块
- 添加频道
  - 可以用命令行，详见 tv -h
  - 也可以使用 shell 对话，输入 tv 打开面板
- 管理频道
  - 输入 tv 打开 HLS 面板
  - 输入 tv f 打开 FLV 推流管理面板
- 主目录在 /usr/local/iptv
  - channels.json [ 默认值和频道列表 ]
  - HLS-Stream-Creator 本尊
  - FFmpeg-git*-static
  - jq
  - live/ [ hls输出目录 ]
  - node/ [ 加密 session ]

## 自动更新指定的json文件

```bash
"sync_file":"/usr/local/nginx/html/channels.json", # 公开目录的json，多个文件用空格分隔
"sync_index":"data:2:channels", # 必须指定到m3u8直播源所在的数组这一级，比如这里 ObjectJson.data[2].channels ， 多个 sync_index 用空格分隔
"sync_pairs":"chnl_name:channel_name,chnl_id:output_dir_name,chnl_pid:pid,chnl_cat=港澳台,url=http://xxx.com/live,schedule:output_dir_name", # 值映射用:号，如果直接赋值用=号（公开的live根目录会自动补上完整的m3u8地址）
"schedule_file":"/usr/local/nginx/html/schedule.json" # 使用命令 tv s 自建节目表
```

- 操作频道，添加，删除，重启等都会自动更新指定的json文件

## 快捷键

- tv e 手动修改 channels.json
- tv s 打开节目表管理面板 CCTV/台湾/香港/国外 节目表
  - 手动选择需要每日更新节目表的频道
  - 自动配置到 cron
- tv ffmpeg 在主目录下自建 FFmpeg 镜像
- tv ts 打开广电直播源 注册/登录 面板
  - 在命令行注册账号
  - 登录账号以获取 mpegts 链接
  - 同步 mpegts 链接到 channels.json

   ```bash
    广电直播源mpegts转hls的设置(1核以上, 根据核数和带宽调整)
    "video_codec": "libx264",
    "audio_codec": "copy",
    "quality": "40",
    "bitrates": "800",
    片段大小700~800K，但是非常吃CPU

    也可以直接 copy ，相当于复制
    "video_codec": "copy",
    "audio_codec": "copy",
    "output_flags": ""
    原画输出，不吃CPU，但是片段大，吃带宽
   ```

- nx 安装管理 nginx  后才能开启 防护 AntiDDoS
- tv m 开启监控 flv推流 和 hls 输出目录，用来应对直播源出现变化导致 ffmpeg 无法继续分割的情况
  - 防护 AntiDDoS  默认每2分钟清除被禁 ip，很多时候因为直播源重启/网络等问题浏览器会不停的发送请求同一个文件，所以会有误伤，选项：
    - 封禁端口（可多个, 默认80）
    - 是否开启 SYN flood 攻击防护
    - 是否开启 iptv 防护
    - 封禁时间（默认120秒）
    - 封禁等级（1-9）（默认6，数值越低越严格，也越容易误伤）
  - 防盗链 选项：
    - 是否开启
    - 每小时随机重启次数
    - 每当重启 FLV 频道更改成随机的推流和拉流地址
    - 每当重启 HLS 频道更改成随机的 m3u8 名称和段名称
    - 每隔多少秒更改加密频道的 key
  - 监控 FLV 选项：
    - 是否监控超时（默认20秒）
    - 重启次数（默认20次）
  - 监控 HLS 选项：
    - 是否监控超时（默认120秒,必须大于段时长*段数目）
    - 最低比特率 (默认低于500kb/s会自动重启频道)
    - 最大片段 (默认5MB,超过会自动重启频道)
    - 重启次数（默认20次）
  - 定时检查直播源(如可用即开启频道)的间隔时间
  - tv m s 停止监控
  - tv m l 查看监控日志
  - 在 leech 直播源的时候必须打开监控选项，以应对输出低比特率/直播源服务器频繁重启/音轨丢失/等问题
- tv l 列出所有开启的 flv 和 hls 频道
- tv d 请求演示频道 ( 3个凤凰台,1个hbo中文频道 )，添加到 channels.json
  - 都需要先替换 mpegts 链接才能开启
- ...

## 参数详解

使用方法: tv -i [直播源] [-s 段时长(秒)] [-o 输出目录名称] [-c m3u8包含的段数目] [-b 比特率] [-p m3u8文件名称] [-C] [-l] [-P http代理]

```bash
-i  直播源(支持 mpegts / hls / flv / youtube ...)
    可以是视频路径
    可以输入不同链接地址(监控按顺序尝试使用)，用空格分隔
-s  段时长(秒)(默认：6)
-o  输出目录名称(默认：随机名称)

-l  非无限时长直播, 无法设置切割段数目且无法监控(默认：不设置)
-P  ffmpeg 的 http 代理, 直播源是 http 链接时可用(默认：不设置)

-p  m3u8名称(前缀)(默认：随机)
-c  m3u8里包含的段数目(默认：5)
-S  段所在子目录名称(默认：不使用子目录)
-t  段名称(前缀)(默认：跟m3u8名称相同)
-a  音频编码(默认：aac) (不需要转码时输入 copy)
-v  视频编码(默认：libx264) (不需要转码时输入 copy)
-f  画面或声音延迟(格式如： v_3 画面延迟3秒，a_2 声音延迟2秒
    使用此功能*暂时*会忽略部分参数，画面声音不同步时使用)
-q  crf视频质量(如果设置了输出视频比特率，则优先使用crf视频质量)(数值0~63 越大质量越差)
    (默认: 不设置crf视频质量值)
-b  输出视频的比特率(kb/s)(默认：900-1280x720)
    如果已经设置crf视频质量值，则比特率用于 -maxrate -bufsize
    如果没有设置crf视频质量值，则可以继续设置是否固定码率
    多个比特率用逗号分隔(注意-如果设置多个比特率，就是生成自适应码流)
    同时可以指定输出的分辨率(比如：-b 600-600x400,900-1280x720)
    可以输入 omit 省略此选项
-C  固定码率(只有在没有设置crf视频质量的情况下才有效)(默认：否)
-e  加密段(默认：不加密)
-K  Key名称(默认：随机)
-z  频道名称(默认：跟m3u8名称相同)

也可以不输出 HLS，比如 flv 推流
-k  设置推流类型，比如 -k flv
-T  设置推流地址，比如 rtmp://127.0.0.1/flv/xxx
-L  输入拉流(播放)地址(可省略)，比如 http://domain.com/flv?app=flv&stream=xxx

-m  ffmpeg 额外的 INPUT FLAGS
    (默认：-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -rw_timeout 10000000 -y -nostats -nostdin -hide_banner -loglevel fatal)
    如果输入的直播源是 hls 链接，需去除 -reconnect_at_eof 1
    如果输入的直播源是 rtmp 或本地链接，需去除 -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000
    如果要查看详细日志 fatal 改成 error / warning / ...
-n  ffmpeg 额外的 OUTPUT FLAGS, 可以输入 omit 省略此选项 (除非有特殊需求, 不需要转码时请省略此选项)
    (默认：-g 25 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main)
```

## 举例

- 使用crf值控制视频质量:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo1 -p hbo1 -q 15 -b 1500-1280x720 -z 'hbo直播1'`

- 使用比特率控制视频质量[ 默认 ]:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo2 -p hbo2 -b 900-1280x720 -z 'hbo直播2'`

- 不需要转码的设置: -a copy -v copy -n omit

- 不输出 HLS, 推流 flv :

    `tv -i http://xxx/xxx.ts -a aac -v libx264 -b 3000 -k flv -T rtmp://127.0.0.1/flv/xxx`

- 或者输入 tv 打开 HLS 面板， tv f 打开 FLV 面板，使用方法  **Enter**
