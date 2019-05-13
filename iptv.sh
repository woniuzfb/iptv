#!/bin/bash

set -euxo pipefail

sh_ver="0.1"
SH_FILE="/usr/local/bin/tv"
IPTV_PATH="$HOME/iptv"
CREATOR_FILE="$IPTV_PATH/HLS-Stream-Creator.sh"
JQ_FILE="$IPTV_PATH/jq"
CHANNELS_File="$IPTV_PATH/channels.json"
LIVE_PATH="$IPTV_PATH/live"
green="\033[32m"
red="\033[31m"
plain="\033[0m"
info="${green}[信息]$plain"
error="${red}[错误]$plain"
tip="${green}[注意]$plain"

[ $EUID -ne 0 ] && echo -e "[$error] 当前账号非ROOT(或没有ROOT权限),无法继续操作,请使用$green sudo su $plain来获取临时ROOT权限（执行后会提示输入当前账号的密码）." && exit 1

CheckRelease()
{
    if grep -Eqi "(Red Hat|CentOS|Fedora|Amazon)" < /etc/issue
    then
        release="rpm"
    elif grep -Eqi "Debian" < /etc/issue
    then
        release="deb"
    elif grep -Eqi "Ubuntu" < /etc/issue
    then
        release="ubu"
    else
        if grep -Eqi "(redhat|centos|Red\ Hat)" < /proc/version
        then
            release="rpm"
        elif grep -Eqi "debian" < /proc/version
        then
            release="deb"
        elif grep -Eqi "ubuntu" < /proc/version
        then
            release="ubu"
        fi
    fi

    if [ -s "/etc/redhat-release" ]
    then
        release_ver=$(grep -oE  "[0-9.]+" /etc/redhat-release)
    else
        release_ver=$(grep -oE  "[0-9.]+" /etc/issue)
    fi
    release_ver_main=${release_ver%%.*}

    if [ "$(uname -m | grep -c 64)" -gt 0 ]
    then
        release_bit="64"
    else
        release_bit="32"
    fi

    update_once=0
    depends=(unzip vim curl cron crond)
    
    for depend in "${depends[@]}"; do
        DEPEND_PATH="$(command -v "$depend" || true)"
        if [ -z "$DEPEND_PATH" ]
        then
            case "$release" in
                "rpm")
                    if [ "$depend" != "cron" ]
                    then
                        if [ $update_once == 0 ]
                        then
                            yum -y update >/dev/null 2>&1
                            update_once=1
                        fi
                        if yum -y install "$depend" >/dev/null 2>&1
                        then
                            echo -e "$info 依赖 $depend 安装成功..."
                        else
                            echo -e "$error 依赖 $depend 安装失败..." && exit 1
                        fi
                    fi
                ;;
                "deb"|"ubu")
                    if [ "$depend" != "crond" ]
                    then
                        if [ $update_once == 0 ]
                        then
                            apt-get -y update >/dev/null 2>&1
                            update_once=1
                        fi
                        if apt-get -y install "$depend" >/dev/null 2>&1
                        then
                            echo -e "$info 依赖 $depend 安装成功..."
                        else
                            echo -e "$error 依赖 $depend 安装失败..." && exit 1
                        fi
                    fi
                ;;
                *) echo -e "\n系统不支持!" && exit 1
                ;;
            esac
            
        fi
    done
}

InstallFfmpeg()
{
    FFMPEG=$(dirname "$IPTV_PATH/ffmpeg-git-*/ffmpeg")
    if [ ! -e "$FFMPEG" ]
    then
        if [ "$release_bit" == "64" ]
        then
            FFMPEG_STATIC="ffmpeg-git-amd64-static"
        else
            FFMPEG_STATIC="ffmpeg-git-i686-static"
        fi
        FFMPEG_PATH="$IPTV_PATH/$FFMPEG_STATIC"
        wget --no-check-certificate "https://johnvansickle.com/ffmpeg/builds/$FFMPEG_STATIC.tar.xz" -qO "$FFMPEG_PATH.tar.xz"
        [ ! -e "$FFMPEG_PATH.tar.xz" ] && echo -e "$error ffmpeg压缩包 下载失败 !" && exit 1
        tar -xJf "$FFMPEG_PATH.tar.xz" -C "$IPTV_PATH" && rm -rf "$FFMPEG_PATH.tar.xz"
        FFMPEG=$(dirname "$IPTV_PATH/ffmpeg-git-*/ffmpeg")
        [ ! -e "$FFMPEG" ] && echo -e "$error ffmpeg压缩包 解压失败 !" && exit 1
        export FFMPEG
        echo -e "$info ffmpeg 安装完成..."
    else
        echo -e "$info ffmpeg 已安装..."
    fi
}

InstallJq()
{
    if [ ! -e "$JQ_FILE" ]
    then
        echo -e "$info 开始下载/安装 JSNO解析器 JQ..."
        #experimental# grep -Po '"tag_name": "jq-\K.*?(?=")'
        jq_ver=$(curl --silent -m 10 "https://api.github.com/repos/stedolan/jq/releases/latest" |  grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
        if [ -n "$jq_ver" ]
        then
            wget --no-check-certificate "https://github.com/stedolan/jq/releases/download/$jq_ver/jq-linux$release_bit" -qO "$JQ_FILE"
        fi
        [ ! -e "$JQ_FILE" ] && echo -e "$error 下载JQ解析器失败，请检查 !" && exit 1
        chmod +x "$JQ_FILE"
        echo -e "$info JQ解析器 安装完成..." 
    else
        echo -e "$info JQ解析器 已安装..."
    fi
}

Install()
{
    echo -e "$info 检查依赖..."
    CheckRelease
    if [ -e "$IPTV_PATH" ]
    then
        echo -e "$error 目录已存在，请先卸载..." && exit 1
    else
        mkdir -p "$IPTV_PATH"
        echo -e "$info 下载脚本..."
        wget --no-check-certificate "https://raw.githubusercontent.com/bentasker/HLS-Stream-Creator/master/HLS-Stream-Creator.sh" -qO "$CREATOR_FILE" && chmod +x "$CREATOR_FILE"
        echo -e "$info 脚本就绪..."
        InstallFfmpeg
        InstallJq
        echo -e "$info 安装完成..."
    fi
}

Uninstall()
{
    [ ! -e "$IPTV_PATH" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    CheckRelease
    echo "确定要 卸载此脚本以及产生的全部文件？[Y/n]" && echo
    read -p "(默认: n):" uninstall_yn
    [ -z "$uninstall_yn" ] && uninstall_yn="n"
    if [[ "$uninstall_yn" == [Yy] ]]; then
        rm -rf "$IPTV_PATH"
        echo && echo "$info 卸载完成 !" && echo
    else
        echo && echo "$info 卸载已取消..." && echo
    fi
}

Update()
{
    sh_new_ver=$(wget --no-check-certificate -qO- -t1 -T3 "https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
    [ -z "$sh_new_ver" ] && echo -e "$error 无法链接到 Github !" && exit 1
    wget --no-check-certificate "https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh" -qO "$SH_FILE" && chmod +x "$SH_FILE"
    echo -e "脚本已更新为最新版本[ $sh_new_ver ] !(输入: tv 使用)" && exit 0
}

RandStr()
{
    str_size=8
    str_array=(
        q w e r t y u i o p a s d f g h j k l z x c v b n m Q W E R T Y U I O P A S D
F G H J K L Z X C V B N M
    )
    str_array_size=${#str_array[*]}
    str_len=0
    rand_str=""
    while [ $str_len -lt $str_size ]; do
        str_index=$((RANDOM%str_array_size))
        rand_str="$rand_str${str_array[$str_index]}"
        str_len=$((str_len+1))
    done
    echo "$rand_str"
}

RandOutputDirName()
{
    while :;do
        output_dir_name=$(RandStr)
        str_info=$($JQ_FILE '.[]|select(.outputDirName=="'"$output_dir_name"'")' "$CHANNELS_File")
        if [ -z "$str_info" ]; then
            echo "$output_dir_name"
            break
        fi
    done
}

RandPlaylistName()
{
    while :;do
        playlist_name=$(RandStr)
        str_info=$($JQ_FILE '.[]|select(.playListName=="'"$playlist_name"'")' "$CHANNELS_File")
        if [ -z "$str_info" ]; then
            echo "$playlist_name"
            break
        fi
    done
}

RandSegDirName()
{
    while :;do
        seg_dir_name=$(RandStr)
        str_info=$($JQ_FILE '.[]|select(.segDirName=="'"$seg_dir_name"'")' "$CHANNELS_File")
        if [ -z "$str_info" ]; then
            echo "$seg_dir_name"
            break
        fi
    done
}

Usage()
{

cat << EOM
HTTP Live Stream Creator
Wrapper By MTimer

Copyright (C) 2013 B Tasker, D Atanasov
Released under BSD 3 Clause License
See LICENSE

使用方法: tv -i [直播源] -s [段时长(秒)] -o [输出目录名称] [-c m3u8包含的段数目] -b [比特率]  [-p m3u8文件名称]

	-i	直播源(仅支持mpegts)
	-s	段时长(秒)(默认：6)
	-o	输出目录名称(默认：随机)

	-c	m3u8里包含的段数目(默认：5)
    -a  音频编码(默认：aac)
    -v  视频编码(默认：libx264)
	-b	输出视频的比特率 (多种比特率用逗号分隔)(默认：15,20)
	-p	m3u8名称(前缀)(默认：随机)
    -S	段所在子目录名称(默认：不使用子目录)
	-t	段名称(前缀)(默认：跟m3u8名称相同)
    -C	固定码率(CBR 而不是 AVB)(默认：是)
	-q	质量(改变 CRF)(默认：22)
    -e	加密段(默认：不加密)
	-K	Key名称(默认：跟m3u8名称相同)

    -m  ffmpeg 额外的 INPUT FLAGS
        (默认：-reconnect 1 -reconnect_at_eof 1 
        -reconnect_streamed 1 -reconnect_delay_max 2000 
        -timeout 2000000000 -y -thread_queue_size 55120 
        -nostats -nostdin -hide_banner -loglevel 
        fatal -probesize 65536)
    -n  ffmpeg 额外的 OUTPUT FLAGS
        (默认：-preset superfast -pix_fmt yuv420p -profile:v main)

EOM

exit

}

if [ -e "$FFMPEG" ]
then
    if [ "$release_bit" == "64" ]
    then
        FFMPEG_STATIC="ffmpeg-git-amd64-static"
    else
        FFMPEG_STATIC="ffmpeg-git-i686-static"
    fi
    FFMPEG_PATH="$IPTV_PATH/$FFMPEG_STATIC"
    wget --no-check-certificate "https://johnvansickle.com/ffmpeg/builds/$FFMPEG_STATIC.tar.xz" -qO "$FFMPEG_PATH.tar.xz"
    [ ! -e "$FFMPEG_PATH.tar.xz" ] && echo -e "$error ffmpeg压缩包 下载失败 !" && exit 1
    tar -xJf "$FFMPEG_PATH.tar.xz" -C "$IPTV_PATH" && rm -rf "$FFMPEG_PATH.tar.xz"
    FFMPEG=$(dirname "$IPTV_PATH"/ffmpeg-git-*/ffmpeg)
    [ ! -e "$FFMPEG" ] && echo -e "$error ffmpeg压缩包 解压失败 !" && exit 1
    export FFMPEG
    echo -e "$info ffmpeg 安装完成..."
else
    echo -e "$info ffmpeg 已安装..."
fi

use_menu=1

while getopts "i:s:o:c:a:v:b:p:S:t:q:K:h:H:m:n:Ce" flag
do
	use_menu=0
        case "$flag" in
                i) stream_link="$OPTARG";;
                s) seg_length="$OPTARG";;
                o) output_dir_name="$OPTARG";;
		c) seg_count="$OPTARG";;
        a) audio_codec="$OPTARG";;
        v) video_codec="$OPTARG";;
		b) bitrates="$OPTARG";;
		p) playlist_name="$OPTARG";;
        S) seg_dir_name="$OPTARG";;
		t) seg_name="$OPTARG";;
        C) const="-C";;
		q) quality="$OPTARG";;
        e) encrypt="-e";;
		K) key_name="$OPTARG";;
        m) input_flags="$OPTARG";;
        n) output_flags="$OPTARG";;
        *) Usage;
        esac
done

if [ "$use_menu" == "1" ]
then
    [ ! -e "$SH_FILE" ] && wget --no-check-certificate "https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh" -qO "$SH_FILE" && chmod +x "$SH_FILE"
    echo -e "  IPTV 一键管理脚本（mpegts => hls）${red}[v$sh_ver]$plain
  ---- MTimer | http://hbo.epub.fun ----

  ${green}1.$plain 安装
  ${green}2.$plain 卸载
  ${green}3.$plain 升级脚本
————————————
  ${green}4.$plain 查看频道
  ${green}5.$plain 添加频道
  ${green}6.$plain 修改频道
  ${green}7.$plain 删除频道
————————————
  ${green}8.$plain 查看运行状态
  ${green}9.$plain 查看日志

 $tip 输入: tv 打开此面板" && echo
    echo && read -p "请输入数字 [1-9]：" menu_num
    case "$menu_num" in
        1) Install
        ;;
        2) Uninstall
        ;;
        3) Update
        ;;
        4) ViewChannel
        ;;
        5) AddChannel
        ;;
        6) EditChannel
        ;;
        7) DelChannel
        ;;
        8) ViewStatus
        ;;
        9) ViewLog
        ;;
        *)
        echo -e "$error 请输入正确的数字 [1-15]"
        ;;
    esac
else
    stream_link=${stream_link:-"")}
    if [ "$stream_link" == "" ]
    then
        Usage
    else
        CheckRelease
        if [ ! -e "$FFMPEG" ]
        then
            echo && read -p "尚未安装,是否现在安装？[y/N] (默认: N): " install_yn
            [ -z "$install_yn" ] && install_yn="n"
            if [[ "$install_yn" == [Yy] ]]; then
                Install
            else
                echo "已取消..." && exit 1
            fi
        else
            FFMPEG=$(dirname "$IPTV_PATH/ffmpeg-git-*/ffmpeg")
            export FFMPEG
            export FFMPEG_INPUT_FLAGS=${input_flags:-"-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -timeout 2000000000 -y -thread_queue_size 55120 -nostats -nostdin -hide_banner -loglevel fatal -probesize 65536"}
            seg_length=${seg_length:-"6")}
            output_dir_name=${output_dir_name:-"$(RandOutputDirName)"}
            output_dir_path="$LIVE_PATH/$output_dir_name"
            seg_count=${seg_count:-"5")}
            bitrates=${bitrates:-"15,20")}
            export AUDIO_CODEC=${audio_codec:-"aac"}
            export VIDEO_CODEC=${video_codec:-"libx264"}
            playlist_name=${playlist_name:-"$(RandPlaylistName)"}
            export SEGMENT_DIRECTORY=${seg_dir_name:-""}
            seg_name=${seg_name:-"$playlist_name"}
            const=${const:-""}
            quality=${quality:-"22"}
            encrypt=${encrypt:-""}
            key_name=${key_name:-"$playlist_name"}
            export FFMPEG_FLAGS=${output_flags:-"-preset superfast -pix_fmt yuv420p -profile:v main"}

            exec CREATOR_FILE -l -i "$stream_link" -s "$seg_length" \
                -o "$output_dir_path" -c "$seg_count" -b "$bitrates" \
                -p "$playlist_name" -t "$seg_name" -K "$key_name" -q "$quality" \
                "$const" "$encrypt"
        fi
    fi
fi