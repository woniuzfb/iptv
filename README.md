# 看HBO直播 + 一键管理 IPTV 脚本 mpegts / flv => hls

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

## iptv.sh 一键管理 IPTV 脚本 mpegts / flv => hls

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
  - FFmpeg-git*-static
  - jq
  - live/ [ hls输出目录 ]

``` bash
wget -q http://hbo.epub.fun/iptv.sh && bash iptv.sh
```

## 自动更新指定的json文件

```bash
"sync_file":"/var/www/html/channels.json", # 公开目录的json
"sync_index":"data:2:channels", # 必须指定到m3u8直播源所在的数组这一级，比如这里 ObjectJson.data[2].channels
"sync_pairs":"chnl_name:channel_name,chnl_id:output_dir_name,chnl_pid:pid,chnl_cat=港澳台,url=http://xxx.com/live,schedule:playlist_name", # 值映射用:号，如果直接赋值用=号（公开的live根目录会自动补上完整的m3u8地址）
"schedule_file":"/var/www/html/schedule.json" # 使用命令 tv s 自建节目表
```

- 操作频道，添加，删除，重启等都会自动更新指定的json文件

## 快捷键

- tv e 手动修改 channels.json
- tv s 更新 150+ 节目表
- tv s hbo 更新 hbo 节目表
- tv s disney 更新迪士尼频道节目表
- tv s foxmovies 更新 FOX MOVIES 节目表
- tv ffmpeg 在主目录下自建 FFmpeg 镜像
- tv ts 打开广电直播源 注册/登录 面板
  - 在命令行注册账号
  - 登录账号以获取 mpegts 链接
  - 同步 mpegts 链接到 channels.json

   ```bash
    广电直播源mpegts转hls的设置(1核以上, 根据核数和带宽调整)
    "video_codec": "h264",
    "audio_codec": "copy",
    "quality": "40",
    "bitrates": "800",
    "const": "",
    片段大小700~800K，但是非常吃CPU

    也可以直接 copy ，相当于复制
    "video_codec": "copy",
    "audio_codec": "copy",
    "output_flags": ""
    原画输出，不吃CPU，但是片段大，吃带宽
   ```

- tv m 开启监控 hls 输出目录，用来应对直播源出现变化导致 ffmpeg 无法继续分割的情况
  - 如果片段大小大于5MB(默认)会自动重启频道(可以 tv m 数字 指定大小)。
  - 打开监控后会有选择是否对某些频道监控超时(在超时时只有重启频道才能继续连接直播源的情况)
  - tv m stop 停止监控
  - 建议在 copy 直播源的时候开启监控
- tv d 请求演示频道 ( 3个凤凰台,1个hbo中文频道 )，添加到 channels.json
  - 都需要先替换 mpegts 链接才能开启
- ...

## 参数详解

使用方法: tv -i [直播源] [-s 段时长(秒)] [-o 输出目录名称] [-c m3u8包含的段数目] [-b 比特率] [-p m3u8文件名称] [-C]

```bash
-i  直播源(仅支持 mpegts / flv)
-s  段时长(秒)(默认：6)
-o  输出目录名称(默认：随机名称)

-p  m3u8名称(前缀)(默认：随机)
-c  m3u8里包含的段数目(默认：5)
-S  段所在子目录名称(默认：不使用子目录)
-t  段名称(前缀)(默认：跟m3u8名称相同)
-a  音频编码(默认：aac) (不需要转码时输入 copy)
-v  视频编码(默认：h264) (不需要转码时输入 copy)
-f  画面或声音延迟(格式如： v_3 画面延迟3秒，a_2 声音延迟2秒
    如果转码时使用此功能*暂时*会忽略部分参数，建议 copy 直播源(画面声音不同步)时使用)
-q  crf视频质量(如果设置了输出视频比特率，则优先使用crf视频质量)(数值1~63 越大质量越差)
    (默认: 不设置crf视频质量值)
-b  输出视频的比特率(bits/s)(默认：900-1280x720)
    如果已经设置crf视频质量值，则比特率用于 -maxrate -bufsize
    如果没有设置crf视频质量值，则可以继续设置是否固定码率
    多个比特率用逗号分隔(注意-如果设置多个比特率，就是生成自适应码流)
    同时可以指定输出的分辨率(比如：-b 600-600x400,900-1280x720)
    可以输入 copy 省略此选项(不需要转码时)
-C  固定码率(CBR 而不是 AVB)(只有在没有设置crf视频质量的情况下才有效)(默认：否)
-e  加密段(默认：不加密)
-K  Key名称(默认：跟m3u8名称相同)
-z  频道名称(默认：跟m3u8名称相同)

-m  ffmpeg 额外的 INPUT FLAGS
    (默认："-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -timeout 2000000000 -y -thread_queue_size 55120 -nostats -nostdin -hide_banner -loglevel fatal -probesize 65536")
-n  ffmpeg 额外的 OUTPUT FLAGS, 可以输入 copy 省略此选项(不需要转码时)
    (默认："-g 30 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main")
```

## 举例

- 使用crf值控制视频质量:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo1 -p hbo1 -q 15 -b 1500-1280x720 -z 'hbo直播1'`

- 使用比特率控制视频质量[ 默认 ]:

    `tv -i http://xxx/xxx.ts -s 6 -o hbo2 -p hbo2 -b 900-1280x720 -z 'hbo直播2'`

- 不需要转码的设置: -a copy -v copy -n copy

- 或者输入 tv 打开面板，使用方法  **Enter**
