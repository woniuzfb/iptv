# 看HBO直播 + 一键管理 IPTV 脚本 mpegts => hls

- HBO 中文直播 + 集各广电直播源
- 默认如果没有本地频道（channels.json）,会请求远程服务器频道
- 带节目表
- 广电源支持回看
- HBO 支持节目预告
- 仅作为宽带测试用

## 怎么看

- 广电+港澳台 <http://hbo.epub.fun/>, 港澳台 <http://mtime.info/>
- 自定义频道，需把 iptv.html 放到**本地服务器**目录下，修改channels.json

---

## iptv.sh 一键管理 IPTV 脚本 mpegts => hls

- 【自动化】HLS-Stream-Creator
- 自建节目表
- 添加频道
  - 可以用命令行，详见 tv -h
  - 也可以使用 shell 对话，输入 tv 打开面板
- 管理频道
  - 输入 tv 打开面板
- 主目录在 /usr/local/iptv
  - channels.json [ 默认值和频道列表 ]
  - HLS-Stream-Creator 本尊
  - FFmpeg
  - jq
  - live/ [ hls输出目录 ]

``` bash
bash -c "$(wget --no-check-certificate -qO- https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh)"
```

## 自动更新指定的json文件

```bash
"sync_file":"/var/www/html/channels.json", # 公开目录的json
"sync_index":"data:2:channels", # 必须指定到m3u8直播源所在的数组这一级，比如这里 ObjectJson.data[2].channels
"sync_pairs":"chnl_name:channel_name,chnl_id:output_dir_name,chnl_pid:pid,chnl_cat=港澳台,url=http://xxx.com/live,schedule:output_dir_name", # 值映射用:号，如果直接赋值用=号（公开的live根目录会自动补上完整的m3u8地址）
"schedule":"/var/www/html/schedule.json" # 使用命令 tv s 自建节目表
```

- 操作频道，添加，删除，重启等都会自动更新指定的json文件

## 快捷键

- tv e 手动修改 channels.json
- tv s 自建150+节目表
- tv s hbo 更新 hbo 节目表
- tv s disney 更新迪士尼频道节目表
- ~~tv d 请求默认频道 ( 40多港澳台频道 - **在墙外**)，添加到 channels.json~~
- ...

## 参数详解

使用方法: tv -i [直播源] [-s 段时长(秒)] [-o 输出目录名称] [-c m3u8包含的段数目] [-b 比特率] [-p m3u8文件名称] [-C]

```bash
-i  直播源(仅支持mpegts)
-s  段时长(秒)(默认：6)
-o  输出目录名称(默认：随机名称)

-p  m3u8名称(前缀)(默认：随机)
-c  m3u8里包含的段数目(默认：5)
-S  段所在子目录名称(默认：不使用子目录)
-t  段名称(前缀)(默认：跟m3u8名称相同)
-a  音频编码(默认：aac)
-v  视频编码(默认：h264)
-q  crf视频质量(如果设置了输出视频比特率，则优先使用crf视频质量)(数值1~63 越大质量越差)
    (默认: 不设置crf视频质量值)
-b  输出视频的比特率(bits/s)(默认：900-1280x720)
    如果已经设置crf视频质量值，则比特率用于 -maxrate -bufsize
    如果没有设置crf视频质量值，则可以继续设置是否固定码率
    多个比特率用逗号分隔(注意-如果设置多个比特率，就是生成自适应码流)
    同时可以指定输出的分辨率(比如：-b 600-600x400,900-1280x720)
    这里不能不设置比特率(空)，因为大多数直播源没有设置比特率，无法让FFmpeg按输入源的比特率输出
-C  固定码率(CBR 而不是 AVB)(只有在没有设置crf视频质量的情况下才有效)(默认：否)
-e  加密段(默认：不加密)
-K  Key名称(默认：跟m3u8名称相同)
-z  频道名称(默认：跟m3u8名称相同)

-m  ffmpeg 额外的 INPUT FLAGS
    (默认："-reconnect 1 -reconnect_at_eof 1 
    -reconnect_streamed 1 -reconnect_delay_max 2000 
    -timeout 2000000000 -y -thread_queue_size 55120 
    -nostats -nostdin -hide_banner -loglevel 
    fatal -probesize 65536")
-n  ffmpeg 额外的 OUTPUT FLAGS
    (默认："-g 30 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main")
```

## 举例

- 使用crf值控制视频质量:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo1 -p hbo1 -q 15 -b 1500-1280x720 -z 'hbo直播1'`

- 使用比特率控制视频质量[ 默认 ]:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo2 -p hbo2 -b 900-1280x720 -z 'hbo直播2'`

- 或者输入 tv 打开面板，使用方法  **Enter**
