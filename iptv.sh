#!/bin/bash

set -euxo pipefail

sh_ver="0.1"
SH_FILE="/usr/local/bin/tv"
IPTV_ROOT="$HOME/iptv"
CREATOR_FILE="$IPTV_ROOT/HLS-Stream-Creator.sh"
JQ_FILE="$IPTV_ROOT/jq"
CHANNELS_FILE="$IPTV_ROOT/channels.json"
LIVE_ROOT="$IPTV_ROOT/live"
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
        DEPEND_FILE="$(command -v "$depend" || true)"
        if [ -z "$DEPEND_FILE" ]
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
    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFMPEG="$FFMPEG_ROOT/ffmpeg"
    if [ ! -e "$FFMPEG" ]
    then
        echo -e "$info 开始下载/安装 FFmpeg..."
        if [ "$release_bit" == "64" ]
        then
            ffmpeg_package="ffmpeg-git-amd64-static.tar.xz"
        else
            ffmpeg_package="ffmpeg-git-i686-static.tar.xz"
        fi
        FFMPEG_PACKAGE_FILE="$IPTV_ROOT/$ffmpeg_package"
        wget --no-check-certificate "https://johnvansickle.com/ffmpeg/builds/$ffmpeg_package" -qO "$FFMPEG_PACKAGE_FILE"
        [ ! -e "$FFMPEG_PACKAGE_FILE" ] && echo -e "$error ffmpeg压缩包 下载失败 !" && exit 1
        tar -xJf "$FFMPEG_PACKAGE_FILE" -C "$IPTV_ROOT" && rm -rf "$FFMPEG_PACKAGE_FILE"
        FFMPEG=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
        [ ! -e "$FFMPEG" ] && echo -e "$error ffmpeg压缩包 解压失败 !" && exit 1
        export FFMPEG
        echo -e "$info FFmpeg 安装完成..."
    else
        echo -e "$info FFmpeg 已安装..."
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
    if [ -e "$IPTV_ROOT" ]
    then
        echo -e "$error 目录已存在，请先卸载..." && exit 1
    else
        mkdir -p "$IPTV_ROOT"
        echo -e "$info 下载脚本..."
        wget --no-check-certificate "https://raw.githubusercontent.com/bentasker/HLS-Stream-Creator/master/HLS-Stream-Creator.sh" -qO "$CREATOR_FILE" && chmod +x "$CREATOR_FILE"
        echo -e "$info 脚本就绪..."
        InstallFfmpeg
        InstallJq
cat > "$CHANNELS_FILE" << EOM
{
    "default":
    {
        "input_flags":"-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -timeout 2000000000 -y -thread_queue_size 55120 -nostats -nostdin -hide_banner -loglevel fatal -probesize 65536",
        "seg_length":6,
        "seg_count":5,
        "bitrates":"256,384",
        "audio_codec":"aac",
        "video_codec":"libx264",
        "quality":22,
        "const":"-C",
        "output_flags":"-preset superfast -pix_fmt yuv420p -profile:v main"
    },
    "channels":[]
}
EOM
        echo -e "$info 安装完成..."
    fi
}

Uninstall()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    CheckRelease
    echo "确定要 卸载此脚本以及产生的全部文件？[Y/n]" && echo
    read -p "(默认: n):" uninstall_yn
    [ -z "$uninstall_yn" ] && uninstall_yn="n"
    if [[ "$uninstall_yn" == [Yy] ]]
    then
        rm -rf "$IPTV_ROOT"
        echo && echo -e "$info 卸载完成 !" && echo
    else
        echo && echo -e "$info 卸载已取消..." && echo
    fi
}

Update()
{
    sh_new_ver=$(wget --no-check-certificate -qO- -t1 -T3 "https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
    [ -z "$sh_new_ver" ] && echo -e "$error 无法链接到 Github !" && exit 1
    wget --no-check-certificate "https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh" -qO "$SH_FILE" && chmod +x "$SH_FILE"
    echo -e "脚本已更新为最新版本[ $sh_new_ver ] !(输入: tv 使用)" && exit 0
}

GetDefault()
{
    default_array=()
    while IFS='' read -r default_line; do
        default_array+=("$default_line");
    done < <($JQ_FILE -r '.default[] | @sh' "$CHANNELS_FILE")
    d_input_flags=${default_array[0]//\'/}
    d_seg_length=${default_array[1]//\'/}
    d_seg_count=${default_array[2]//\'/}
    d_bitrates=${default_array[3]//\'/}
    d_audio_codec=${default_array[4]//\'/}
    d_video_codec=${default_array[5]//\'/}
    d_quality=${default_array[6]//\'/}
    d_const=${default_array[7]//\'/}
    d_output_flags=${default_array[8]//\'/}
}

GetChannelsInfo()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    channels_count=$($JQ_FILE -r '.channels | length' $CHANNELS_FILE)
    [ "$channels_count" == 0 ] && echo -e "$error 没有发现 频道，请检查 !" && exit 1
    IFS=" " read -a chnls_pid <<< "$($JQ_FILE -r '[.channels[].pid] | @sh' $CHANNELS_FILE)"
    IFS=" " read -a chnls_status <<< "$($JQ_FILE -r '[.channels[].status] | @sh' $CHANNELS_FILE)"
    IFS=" " read -a chnls_name <<< "$($JQ_FILE -r '[.channels[].channel_name] | @sh' $CHANNELS_FILE)"
    IFS=" " read -a chnls_video_codec <<< "$($JQ_FILE -r '[.channels[].video_codec] | @sh' $CHANNELS_FILE)"
    IFS=" " read -a chnls_audio_codec <<< "$($JQ_FILE -r '[.channels[].audio_codec] | @sh' $CHANNELS_FILE)"
    IFS=" " read -a chnls_bitrates <<< "$($JQ_FILE -r '[.channels[].bitrates] | @sh' $CHANNELS_FILE)"
    IFS=" " read -a chnls_output_dir_name <<< "$($JQ_FILE -r '[.channels[].output_dir_name] | @sh' $CHANNELS_FILE)"
}

ListChannels()
{
    GetChannelsInfo
    chnls_list=""
    for((index = 0; index < "$channels_count"; index++)); do
        if [ "${chnls_status[index]//\'/}" == "on" ]
        then
            chnls_status_text=$green"开启"$plain
        else
            chnls_status_text=$red"关闭"$plain
        fi
        chnls_codec="${chnls_video_codec[index]//\'/}:${chnls_audio_codec[index]//\'/}"
        chnls_output_dir="$LIVE_ROOT/${chnls_output_dir_name[index]//\'/}"
        chnls_list=$chnls_list"#$((index+1)) 进程ID: $green${chnls_pid[index]//\'/}$plain\t 状态: $chnls_status_text\t 频道名称: $green${chnls_name[index]//\'/}$plain\t 编码: $green$chnls_codec$plain\t 比特率: $green${chnls_bitrates[index]//\'/}$plain\t 目录: $green${chnls_output_dir}$plain  \n"
    done
    echo && echo -e "=== 频道总数 $green $channels_count $plain"
    echo -e "$chnls_list\n"
}

GetChannelInfo(){
    chnl_info_array=()
    while IFS='' read -r chnl_line; do
        chnl_info_array+=("$chnl_line");
    done < <($JQ_FILE -r '.channels[] | select(.pid=='"$chnl_pid"') | .[] | @sh' $CHANNELS_FILE)
    chnl_pid=${chnl_info_array[0]//\'/}
    chnl_status=${chnl_info_array[1]//\'/}
    if [ "$chnl_status" == "on" ]
    then
        chnl_status_text=$green"开启"$plain
    else
        chnl_status_text=$red"关闭"$plain
    fi
    chnl_name=${chnl_info_array[2]//\'/}
    chnl_stream_link=${chnl_info_array[3]//\'/}
    chnl_seg_length=${chnl_info_array[4]//\'/}
    chnl_seg_length_text=$chnl_seg_length"s"
    chnl_output_dir_name=${chnl_info_array[5]//\'/}
    chnl_output_dir_root="$LIVE_ROOT/$chnl_output_dir_name"
    chnl_seg_count=${chnl_info_array[6]//\'/}
    chnl_bitrates=${chnl_info_array[7]//\'/}
    chnl_playlist_name=${chnl_info_array[8]//\'/}
    chnl_seg_name=${chnl_info_array[9]//\'/}
    chnl_key_name=${chnl_info_array[10]//\'/}
    chnl_quality=${chnl_info_array[11]//\'/}
    chnl_const=${chnl_info_array[12]//\'/}
    if [ "$chnl_const" == "-C" ]
    then
        chnl_const_text=$green"是"$plain
    else
        chnl_const_text=$red"否"$plain
    fi
    chnl_encrypt=${chnl_info_array[13]//\'/}
    if [ "$chnl_encrypt" == "-e" ]
    then
        chnl_encrypt_text=$green"是"$plain
        chnl_key_name_text=$green"$chnl_key_name"$plain
    else
        chnl_encrypt_text=$red"否"$plain
        chnl_key_name_text=$red"$chnl_key_name"$plain
    fi
    chnl_input_flags=${chnl_info_array[14]}
    chnl_audio_codec=${chnl_info_array[15]//\'/}
    chnl_video_codec=${chnl_info_array[16]//\'/}
    chnl_seg_dir_name=${chnl_info_array[17]//\'/}
    if [ "$chnl_seg_dir_name" == "" ] 
    then
        chnl_seg_dir_name_text="不使用"
    else
        chnl_seg_dir_name_text=$chnl_seg_dir_name
    fi
    chnl_output_flags=${chnl_info_array[18]}
}

ViewChannelInfo()
{
    clear && echo "===================================================" && echo
    echo -e " 频道 [$chnl_name] 的配置信息：" && echo
    echo -e " 进程ID\t    : $green$chnl_pid$plain"
    echo -e " 状态\t    : $chnl_status_text"
    echo -e " 视频源\t    : $green$chnl_stream_link$plain"
    echo -e " 段时长\t    : $green$chnl_seg_length_text$plain"
    echo -e " 目录\t    : $green$chnl_output_dir_root$plain"
    echo -e " m3u8包含段数目 : $green$chnl_seg_count$plain"
    echo -e " 比特率\t    : $green$chnl_bitrates$plain"
    echo -e " m3u8名称   : $green$chnl_playlist_name$plain"
    echo -e " 段名称\t    : $green$chnl_seg_name$plain"
    echo -e " 段子目录\t   : $green$chnl_seg_dir_name_text$plain"
    echo -e " 视频质量   : $green$chnl_quality$plain"
    echo -e " 视频编码   : $chnl_video_codec"
    echo -e " 音频编码   : $chnl_audio_codec"
    echo -e " 固定码率   : $chnl_const_text"
    echo -e " key名称    : $chnl_key_name_text"
    echo -e " 加密\t    : $chnl_encrypt_text"
    echo -e " input flags\t    : $chnl_input_flags"
    echo -e " output flags\t    : $chnl_output_flags"
    echo
}

InputChannelPid()
{
    echo -e "请输入频道的进程ID "
    while read -p "(默认: 取消):" chnl_pid; do
        case "$chnl_pid" in
            ("")
                echo "已取消..." && exit 1
            ;;
            (*[!0-9]*)
                echo -e "$error 请输入正确的数字！"
            ;;
            (*)
                if [ -n "$($JQ_FILE '.channels[] | select(.pid=='"$chnl_pid"')' $CHANNELS_FILE)" ]
                then
                    break;
                else
                    echo -e "$error 请输入正确的进程ID！"
                fi
            ;;
        esac
    done
}

ViewChannelMenu(){
    ListChannels
    InputChannelPid
    GetChannelInfo
    ViewChannelInfo
}

AddChannel()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    SetStreamLink
    SetSegLength
    SetOutputDirName
    SetSegCount
    SetAudioCodec
    SetVideoCodec
    SetBitrates
    SetPlaylistName
    SetSegName
    SetConst
    SetQuality
    SetEncrypt
    SetKeyName
    SetInputFlags
    SetOutputFlags
}

EditChannel()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
}

ToggleChannel()
{
    ListChannels
    InputChannelPid
    GetChannelInfo
    if [ "$chnl_status" == "on" ] 
    then
        StopChannel
    else
        StartChannel
    fi
}

StartChannel()
{
    GetDefault
    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFMPEG="$FFMPEG_ROOT/ffmpeg"
    export FFMPEG
    FFMPEG_INPUT_FLAGS=$chnl_input_flags
    AUDIO_CODEC=$chnl_audio_codec
    VIDEO_CODEC=$chnl_video_codec
    SEGMENT_DIRECTORY=$chnl_seg_dir_name
    FFMPEG_FLAGS=$chnl_output_flags
    export FFMPEG_INPUT_FLAGS
    export AUDIO_CODEC
    export VIDEO_CODEC
    export SEGMENT_DIRECTORY
    export FFMPEG_FLAGS
    rm -rf "${chnl_output_dir_root:-'notfound'}"/*
    exec "$CREATOR_FILE" -l -i "$chnl_stream_link" -s "$chnl_seg_length" \
        -o "$chnl_output_dir_root" -c "$chnl_seg_count" -b "$chnl_bitrates" \
        -p "$chnl_playlist_name" -t "$chnl_seg_name" -K "$chnl_key_name" -q "$chnl_quality" \
        "$chnl_const" "$chnl_encrypt" &
    new_pid=$!
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'|(.channels[]|select(.pid=='"$new_pid"')|.status)="on"' "$CHANNELS_FILE" > channels.tmp
    mv channels.tmp "$CHANNELS_FILE"
    echo && echo -e "$info 频道进程已开启 !" && echo
}

StopChannel()
{
    creator_pids=$(pgrep -P $chnl_pid)
    for creator_pid in $creator_pids
    do
        ffmpeg_pids=$(pgrep -P $creator_pid || true)
        for ffmpeg_pid in $ffmpeg_pids
        do
            kill -9 $ffmpeg_pid || true
        done
        #or pkill -TERM -P $creator_pid
    done
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.status)="off"' "$CHANNELS_FILE" > channels.tmp
    mv channels.tmp "$CHANNELS_FILE"
    echo && echo -e "$info 频道进程已停止 !" && echo
}

RestartChannel()
{
    ListChannels
    InputChannelPid
    StopChannel
    GetChannelInfo
    StartChannel
}

DelChannel()
{
    ListChannels
    InputChannelPid
    StopChannel
    $JQ_FILE '. -= [.[]|select(.pid=='"$chnl_pid"')]' "$CHANNELS_FILE" > channels.tmp
    mv channels.tmp "$CHANNELS_FILE"
    echo -e "$info 频道删除成功 !" && echo
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
        if [ -z "$($JQ_FILE '.channels[] | select(.outputDirName=='"$output_dir_name"')' $CHANNELS_FILE)" ]
        then
            echo "$output_dir_name"
            break
        fi
    done
}

RandPlaylistName()
{
    while :;do
        playlist_name=$(RandStr)
        if [ -z "$($JQ_FILE '.channels[] | select(.playListName=='"$playlist_name"')' $CHANNELS_FILE)" ]
        then
            echo "$playlist_name"
            break
        fi
    done
}

RandSegDirName()
{
    while :;do
        seg_dir_name=$(RandStr)
        if [ -z "$($JQ_FILE '.channels[] | select(.segDirName=='"$seg_dir_name"')' $CHANNELS_FILE)" ]
        then
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

使用方法: tv -i [直播源] -s [段时长(秒)] -o [输出目录名称] -c [m3u8包含的段数目] -b [比特率]  [-p m3u8文件名称]

    -i  直播源(仅支持mpegts)
    -s  段时长(秒)(默认：6)
    -o  输出目录名称(默认：随机)

    -c  m3u8里包含的段数目(默认：5)
    -a  音频编码(默认：aac)
    -v  视频编码(默认：libx264)
    -b  输出视频的比特率 (多种比特率用逗号分隔)(默认：256,384)
        同时可以指定输出的分辨率(比如：-b 256-600x400,384-1280x720)
    -p  m3u8名称(前缀)(默认：随机)
    -z  频道名称(默认：跟m3u8名称相同)
    -S  段所在子目录名称(默认：不使用子目录)
    -t  段名称(前缀)(默认：跟m3u8名称相同)
    -C  固定码率(CBR 而不是 AVB)(默认：是)
    -q  质量(改变 CRF)(默认：22)
    -e  加密段(默认：不加密)
    -K  Key名称(默认：跟m3u8名称相同)

    -m  ffmpeg 额外的 INPUT FLAGS
        (默认："-reconnect 1 -reconnect_at_eof 1 
        -reconnect_streamed 1 -reconnect_delay_max 2000 
        -timeout 2000000000 -y -thread_queue_size 55120 
        -nostats -nostdin -hide_banner -loglevel 
        fatal -probesize 65536")
    -n  ffmpeg 额外的 OUTPUT FLAGS
        (默认："-preset superfast -pix_fmt yuv420p -profile:v main")

举例:
    tv -i http://xxx.com/xxx.ts -s 5 -o hbo -c 10 -b 256,384 -p hbo1 -z 'hbo直播'

EOM

exit

}

use_menu=1

while getopts "i:s:o:c:a:v:b:p:z:S:t:q:K:h:H:m:n:Ce" flag
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
        z) channel_name="$OPTARG";;
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
  ${green}7.$plain 开关频道
  ${green}8.$plain 重启频道
  ${green}9.$plain 删除频道

 $tip 输入: tv 打开此面板" && echo
    echo && read -p "请输入数字 [1-9]：" menu_num
    case "$menu_num" in
        1) Install
        ;;
        2) Uninstall
        ;;
        3) Update
        ;;
        4) ViewChannelMenu
        ;;
        5) AddChannel
        ;;
        6) EditChannel
        ;;
        7) ToggleChannel
        ;;
        8) RestartChannel
        ;;
        9) DelChannel
        ;;
        *)
        echo -e "$error 请输入正确的数字 [1-9]"
        ;;
    esac
else
    stream_link=${stream_link:-""}
    if [ "$stream_link" == "" ]
    then
        Usage
    else
        CheckRelease
        FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
        FFMPEG="$FFMPEG_ROOT/ffmpeg"
        if [ ! -e "$FFMPEG" ]
        then
            echo && read -p "尚未安装,是否现在安装？[y/N] (默认: N): " install_yn
            [ -z "$install_yn" ] && install_yn="n"
            if [[ "$install_yn" == [Yy] ]]
            then
                Install
            else
                echo "已取消..." && exit 1
            fi
        else
            GetDefault
            export FFMPEG
            export FFMPEG_INPUT_FLAGS=${input_flags:-"$d_input_flags"}
            seg_length=${seg_length:-"$d_seg_length"}
            output_dir_name=${output_dir_name:-"$(RandOutputDirName)"}
            output_dir_root="$LIVE_ROOT/$output_dir_name"
            seg_count=${seg_count:-"$d_seg_count"}
            bitrates=${bitrates:-"$d_bitrates"}
            export AUDIO_CODEC=${audio_codec:-"$d_audio_codec"}
            export VIDEO_CODEC=${video_codec:-"$d_video_codec"}
            playlist_name=${playlist_name:-"$(RandPlaylistName)"}
            channel_name=${channel_name:-"$playlist_name"}
            export SEGMENT_DIRECTORY=${seg_dir_name:-""}
            seg_name=${seg_name:-"$playlist_name"}
            const=${const:-"$d_const"}
            quality=${quality:-"$d_quality"}
            encrypt=${encrypt:-""}
            key_name=${key_name:-"$playlist_name"}
            export FFMPEG_FLAGS=${output_flags:-"$d_output_flags"}

            exec "$CREATOR_FILE" -l -i "$stream_link" -s "$seg_length" \
                -o "$output_dir_root" -c "$seg_count" -b "$bitrates" \
                -p "$playlist_name" -t "$seg_name" -K "$key_name" -q "$quality" \
                "$const" "$encrypt" &
            pid=$!

            $JQ_FILE '.channels += [
                {
                    "pid":'"$pid"',
                    "status":"on",
                    "channel_name":"'"$channel_name"'",
                    "stream_link":"'"$stream_link"'",
                    "seg_length":'"$seg_length"',
                    "output_dir_name":"'"$output_dir_name"'",
                    "seg_count":'"$seg_count"',
                    "bitrates":"'"$bitrates"'",
                    "playlist_name":"'"$playlist_name"'",
                    "seg_name":"'"$seg_name"'",
                    "key_name":"'"$key_name"'",
                    "quality":'"$quality"',
                    "const":"'"$const"'",
                    "encrypt":"'"$encrypt"'",
                    "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                    "audio_codec":"'"$AUDIO_CODEC"'",
                    "video_codec":"'"$VIDEO_CODEC"'",
                    "seg_dir_name":"'"$SEGMENT_DIRECTORY"'",
                    "output_flags":"'"$FFMPEG_FLAGS"'"
                }
            ]' "$CHANNELS_FILE" > channels.tmp

            mv channels.tmp "$CHANNELS_FILE"

            echo -e "$info 添加频道成功..." && echo
        fi
    fi
fi