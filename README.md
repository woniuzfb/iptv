# 看HBO直播 + 一键管理 IPTV 脚本 [mpegts => hls]

- HBO中文直播 + 100多个电视台（N个高清台）
- promise based
- 默认如果没有本地频道（channels.json）,会请求远程服务器频道
- 不支持IE浏览器
- 支持画中画
- 仅作为宽带测试用

## 怎么看？

- 用浏览器打开 iptv.html
- 或者直接去 <http://hbo.epub.fun/>
- 需用手机号注册后才能看各直播源[ 直播源来自各广电系 ]

## 账号登录错误？

- 使用一段时间后可能会出现这种情况
  - 个别直播源服务端已经删除你的账号，也可能是把你的IP加入防火墙了。

---

## iptv.sh 一键管理 IPTV 脚本 [mpegts => hls]

- 【自动化】HLS-Stream-Creator【手动麻烦】
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