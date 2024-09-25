<details>
<summary><h1>All In One Script</h1></summary>

- [V2ray](#v2ray)
- [Xray](#xray)
- [Nginx](#nginx)
- [Openresty](#openresty)
- [Armbian](#armbian)
- [Proxmox VE](#proxmox-ve)
- [IBM Cloud Foundry](#ibm-cloud-foundry)
- [Cloudflare partner,workers](#cloudflare-partnerworkers)
- [FFmpeg](#ffmpeg)
  - [自动解析直播源](#自动解析直播源)
  - [快捷键](#快捷键)
  - [参数详解](#参数详解)
  - [举例](#举例)
- [Alist](#alist)
- [Rclone](#rclone)
- [Calibre](#calibre)
- [LianHuanHua](#lianhuanhua)
- [Docker](#docker)
- [HAProxy](#haproxy)
- [tests](#tests)
- [Dev](#dev)

</details>

## V2ray

``` bash
wget https://woniuzfb.github.io/iptv/v2.sh && bash v2.sh
```

`v2` 打开 v2ray 管理面板

---

## Xray

``` bash
wget https://woniuzfb.github.io/iptv/x.sh && bash x.sh
```

`x` 打开 xray 管理面板

---

## Nginx

``` bash
wget https://woniuzfb.github.io/iptv/nx.sh && bash nx.sh
```

<details>

`nx` 打开 Nginx 管理面板

- 使用官方 crossplane 解析配置
- 支持修改最多五级指令
- SNI/SSL/APLN 分流
- nodejs
- mongodb
- postfix
- mmproxy
- dnscrypt proxy
- iperf3

</details>

---

## Openresty

``` bash
wget https://woniuzfb.github.io/iptv/or.sh && bash or.sh
```

<details>

`or` 打开 OpenResty 管理面板

</details>

---

## Armbian

``` bash
wget https://woniuzfb.github.io/iptv/arm.sh && bash arm.sh
```

<details>

`arm` 打开 Armbian 管理面板

- docker
- dnscrypt proxy
- openwrt (旁路由)
- openwrt-v2ray
- xray/v2ray core 切换
- 一键配置透明代理(直连国内, 代理国外), 配置文件保存/切换
- NAT类型检测

</details>

---

## Proxmox VE

``` bash
wget https://woniuzfb.github.io/iptv/pve.sh && bash pve.sh
```

<details>

`pve` 打开 Proxmox VE 管理面板

- nbfc
- dnscrypt proxy
- openwrt-v2ray
- xray/v2ray core 切换
- 一键配置透明代理(直连国内, 代理国外), 配置文件保存/切换

</details>

---

## IBM Cloud Foundry

``` bash
wget https://woniuzfb.github.io/iptv/ibm.sh && bash ibm.sh
```

<details>

`ibm` 打开 ibm CF 管理面板

`ibm v2` 打开 ibm v2ray APP 管理面板

`ibm x` 打开 ibm xray  APP 管理面板

</details>

---

## Cloudflare partner,workers

``` bash
wget https://woniuzfb.github.io/iptv/cf.sh && bash cf.sh
```

<details>

`cf` 打开 cloudflare partner,workers 管理面板

`cf w` 打开 cloudflare workers 管理面板

- 多 CFP 管理
- 开启 workers 监控
  - 可以在超过请求数( 默认 100000 )时自动上传 worker 到其他账号并移动域名 CNAME 记录
  - 准备工作
    - 脚本添加用户
    - [ 可省略 ] 需要 Token (API 令牌): workers 和 zone 编辑权限 或 使用 Global API Key (官网添加或查看)
    - 脚本添加源站 CNAME 记录(一个 CNAME 对应一个 worker), 所有域名必须在同一 cloudflare 账号
    - 如果是新账号需要登录官网完成验证邮箱并点击 workers 设置站点域名
  - 可以设置中转 IBM CF
- 账号可能会被 cloudflare 列入黑名单, 无法使用 api

</details>

---

## FFmpeg

``` bash
wget https://woniuzfb.github.io/iptv/iptv.sh && bash iptv.sh
```

<details>

`tv` 打开 iptv 管理面板

- 计划任务(定时开启/关闭)
- 监控
- 防护
- 防盗链
- 节目表
- VIP

### 自动解析直播源

`cx` 打开 xtream codes 账号/频道 管理面板

`tv 4g` 打开 4gtv 频道管理面板

`tv d` 添加演示频道

- tvb
- fengshows
- lotus macau
- youtube
- twitch
- hbo asia

### 快捷键

见 `tv -h`

`tv c <en|zh_CN|...>` 更改语言

`tv color` 自定义文字和背景颜色

### 参数详解

使用方法: tv -i [直播源] [-s 分片时长(秒)] [-o 输出目录名称] [-c m3u8包含的分片数目] [-b 码率] [-r 分辨率] [-p m3u8文件名称] [-C] [-R] [-l] [-P http代理]

```bash
-i  直播源(支持 mpegts / hls / flv / youtube ...)
    可以是视频路径
    可以输入不同链接地址(监控按顺序尝试使用)，用空格分隔
-s  分片时长(秒)(默认：6)
-o  输出目录名称(默认：随机名称)

-l  非无限时长直播, 无法设置切割分片数且无法监控(默认：不设置)
-P  FFmpeg 的 http 代理, 直播源是 http 链接时可用(默认：不设置)

-p  m3u8名称(前缀)(默认：随机)
-c  m3u8里包含的分片数目(默认：5)
-S  分片所在子目录名称(默认：不使用子目录)
-t  分片名称(前缀)(默认：跟m3u8名称相同)
-a  音频编码(默认：aac) (不需要转码时输入 copy)
-v  视频编码(默认：libx264) (不需要转码时输入 copy)
-f  画面或声音延迟(格式如： v_3 画面延迟3秒，a_2 声音延迟2秒 画面声音不同步时使用)
-d  dvb teletext 字幕解码成的格式,可选: text,ass (默认: 不设置)
-q  CRF 固定质量因子, 多个 CRF 用逗号分隔(默认: 不设置)
    如果同时设置了输出视频码率, 则优先使用 CRF 值控制视频质量
    取值每 +/- 6 会大概导致码率的减半或加倍
    x264 和 x265 取值范围为 [0,51]
    x264 的默认值是 23, 视觉无损值 18
    x265 的默认值是 28, 视觉无损值 24
    VP9 取值范围为 [0,63], 建议取值范围为 [15,35]
-b  输出视频的码率(k)(多个用逗号分隔 比如: 800,1000,1500)(默认: 900)
    如果已经设置 CRF 固定质量因子, 用于 VBV 的 -maxrate 和 -bufsize (capped CRF)
    如果没有设置 CRF 固定质量因子, 用于指定输出视频码率(ABR 或 CBR)
    可以输入 omit 省略此选项
-r  输出视频的分辨率(多个用逗号分隔 比如: 960x540,1280x720)(默认: 1280x720)
-C  限制性编码(设置码率的情况下有效)(默认: 否)
    如果已经设置 CRF 固定质量因子, 使用限制性编码 VBV (capped CRF)
    如果没有设置 CRF 固定质量因子, 使用限制性编码 VBV (ABR)
-R  固定码率 CBR (设置 -C 情况下有效)(默认: 否)
-e  加密分片(默认：不加密)
-K  Key名称(默认：随机)
-z  频道名称(默认：跟m3u8名称相同)

也可以不输出 HLS，比如 flv 推流
-k  设置推流类型，比如 -k flv
-H  推流 h265(默认: 不设置)
-T  设置推流地址，比如 rtmp://127.0.0.1/flv/xxx
-L  输入拉流(播放)地址(可省略)，比如 http://domain.com/flv?app=flv&stream=xxx

-m  FFmpeg 额外的输入参数
    (默认：-copy_unknown -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -rw_timeout 10000000 -y -nostats -nostdin -hide_banner -loglevel fatal)
    如果输入的直播源是 hls 链接，需去除 -reconnect_at_eof 1
    如果输入的直播源是 rtmp 或本地链接，需去除 -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000
    如果要查看详细日志 fatal 改成 error / warning / ...
-n  FFmpeg 额外的输出参数, 可以输入 omit 省略此选项 (除非有特殊需求, 不需要转码时请省略此选项)
    (默认：-g 60 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main)
```

### 举例

- 使用 CRF 固定质量因子控制视频质量:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo1 -p hbo1 -q 15 -b 1500 -r 1280x720 -z 'hbo直播1'`

- 使用码率控制视频质量[ 默认 ]:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo2 -p hbo2 -b 900 -r 1280x720 -z 'hbo直播2'`

- 不需要转码的设置: -a copy -v copy -n omit

- 不输出 HLS, 推流 flv :

    `tv -i http://xxx/xxx.ts -a aac -v libx264 -b 3000 -k flv -T rtmp://127.0.0.1/flv/xxx`

- 或者输入 tv 打开 HLS 面板， tv f 打开 FLV 面板，使用方法  **Enter**

</details>

## Alist

```bash
./debug ali
```

## Rclone

```bash
./debug rc
```

<details>

- remote
- mount
- serve
- sync

</details>

## Calibre

```bash
./debug cw
```

<details>

- calibre-web
- kcc

</details>

## LianHuanHua

```bash
./debug lhh
```

<details>

- 1w+ 某某分享 (知乎 + 头条)
- 某某全站 (号称7成连环画?)

</details>

## Docker

```bash
./debug dr
```

<details>

- traefik
- authelia
- postgresql
- yq

</details>

## HAProxy

```bash
./debug ha
```

<details>

- static/dynamic linking pcre/zlib/lua/openssl/quictls

</details>

## tests

```bash
./debug tt
```

## Dev

v2.0.0 broken atm

```bash
./debug [tv|cf|v2|x|...] [options]

./make [install]
```
