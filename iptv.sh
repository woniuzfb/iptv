#!/bin/bash

set -euo pipefail

sh_ver="1.5.0"
SH_LINK="https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh"
SH_LINK_BACKUP="http://hbo.epub.fun/iptv.sh"
SH_FILE="/usr/local/bin/tv"
V2_FILE="/usr/local/bin/v2"
IPTV_ROOT="/usr/local/iptv"
IP_DENY="$IPTV_ROOT/ip.deny"
IP_PID="$IPTV_ROOT/ip.pid"
IP_LOG="$IPTV_ROOT/ip.log"
FFMPEG_MIRROR_LINK="http://47.241.6.233/ffmpeg"
FFMPEG_MIRROR_ROOT="$IPTV_ROOT/ffmpeg"
LIVE_ROOT="$IPTV_ROOT/live"
CREATOR_LINK="https://raw.githubusercontent.com/bentasker/HLS-Stream-Creator/master/HLS-Stream-Creator.sh"
CREATOR_LINK_BACKUP="http://hbo.epub.fun/HLS-Stream-Creator.sh"
CREATOR_FILE="$IPTV_ROOT/HLS-Stream-Creator.sh"
JQ_FILE="$IPTV_ROOT/jq"
CHANNELS_FILE="$IPTV_ROOT/channels.json"
CHANNELS_TMP="$IPTV_ROOT/channels.tmp"
DEFAULT_DEMOS="http://hbo.epub.fun/default.json"
DEFAULT_CHANNELS_LINK="http://hbo.epub.fun/channels.json"
LOCK_FILE="$IPTV_ROOT/lock"
MONITOR_PID="$IPTV_ROOT/monitor.pid"
MONITOR_LOG="$IPTV_ROOT/monitor.log"
LOGROTATE_CONFIG="$IPTV_ROOT/logrotate"
green="\033[32m"
red="\033[31m"
plain="\033[0m"
info="${green}[信息]$plain"
error="${red}[错误]$plain"
tip="${green}[注意]$plain"

[ $EUID -ne 0 ] && echo -e "[$error] 当前账号非ROOT(或没有ROOT权限),无法继续操作,请使用$green sudo su $plain来获取临时ROOT权限（执行后会提示输入当前账号的密码）." && exit 1

default='
{
    "playlist_name":"",
    "seg_dir_name":"",
    "seg_name":"",
    "seg_length":6,
    "seg_count":5,
    "video_codec":"h264",
    "audio_codec":"aac",
    "video_audio_shift":"",
    "quality":"",
    "bitrates":"900-1280x720",
    "const":"no",
    "encrypt":"no",
    "key_name":"",
    "input_flags":"-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -timeout 2000000000 -y -nostats -nostdin -hide_banner -loglevel fatal",
    "output_flags":"-g 25 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main",
    "sync_file":"",
    "sync_index":"data:0:channels",
    "sync_pairs":"chnl_name:channel_name,chnl_id:output_dir_name,chnl_pid:pid,chnl_cat=港澳台,url=http://xxx.com/live",
    "schedule_file":"",
    "flv_delay_seconds":20,
    "flv_restart_nums":20,
    "hls_delay_seconds":120,
    "hls_min_bitrates":500,
    "hls_restart_nums":20,
    "anti_ddos_port":80,
    "anti_ddos_seconds":120,
    "anti_ddos_level":6,
    "version":"'"$sh_ver"'"
}'

SyncFile()
{
    case $action in
        "skip")
            action=""
            return
        ;;      
        "start"|"stop")
            GetDefault
        ;;
        "add")
            chnl_pid=$pid
            if [[ -n $($JQ_FILE '.channels[] | select(.pid=='"$chnl_pid"')' "$CHANNELS_FILE") ]]
            then
                GetChannelInfo
            fi
        ;;
        *)
            echo -e "$error $action ???" && exit 1
        ;;
    esac

    d_sync_file=${d_sync_file:-}
    d_sync_index=${d_sync_index:-}
    d_sync_pairs=${d_sync_pairs:-}
    if [ -n "$d_sync_file" ] && [ -n "$d_sync_index" ] && [ -n "$d_sync_pairs" ]
    then
        chnl_sync_pairs=${chnl_sync_pairs:-$d_sync_pairs}
        jq_index=""
        while IFS=':' read -ra index_arr
        do
            for a in "${index_arr[@]}"
            do
                case $a in
                    '') 
                        echo -e "$error sync设置错误..." && exit 1
                    ;;
                    *[!0-9]*)
                        jq_index="$jq_index.$a"
                    ;;
                    *) 
                        jq_index="${jq_index}[$a]"
                    ;;
                esac
            done
        done <<< "$d_sync_index"

        if [ "$action" == "stop" ]
        then
            if [[ -n $($JQ_FILE "$jq_index"'[]|select(.chnl_pid=="'"$chnl_pid"'")' "$d_sync_file") ]] 
            then
                $JQ_FILE "$jq_index"' -= ['"$jq_index"'[]|select(.chnl_pid=="'"$chnl_pid"'")]' "$d_sync_file" > "${d_sync_file}_tmp"
                mv "${d_sync_file}_tmp" "$d_sync_file"
            fi
        else
            jq_channel_add="[{"
            jq_channel_edit=""
            while IFS=',' read -ra index_arr
            do
                for b in "${index_arr[@]}"
                do
                    case $b in
                        '') 
                            echo -e "$error sync设置错误..." && exit 1
                        ;;
                        *) 
                            if [[ $b == *"="* ]] 
                            then
                                key=${b%=*}
                                value=${b#*=}
                                if [[ $value == *"http"* ]]  
                                then
                                    if [ -n "${kind:-}" ] 
                                    then
                                        if [ "$kind" == "flv" ] 
                                        then
                                            value=$chnl_flv_pull_link
                                        else
                                            value=""
                                        fi
                                    elif [ -z "${master:-}" ] || [ "$master" == 1 ]
                                    then
                                        value="$value/$chnl_output_dir_name/${chnl_playlist_name}_master.m3u8"
                                    else
                                        value="$value/$chnl_output_dir_name/${chnl_playlist_name}.m3u8"
                                    fi
                                fi
                                if [ -z "$jq_channel_edit" ] 
                                then
                                    jq_channel_edit="$jq_channel_edit(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key)=\"${value}\""
                                else
                                    jq_channel_edit="$jq_channel_edit|(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key)=\"${value}\""
                                fi
                            else
                                key=${b%:*}
                                value=${b#*:}
                                value="chnl_$value"

                                if [ "$value" == "chnl_pid" ] 
                                then
                                    if [ -n "${new_pid:-}" ] 
                                    then
                                        value=$new_pid
                                    else
                                        value=${!value}
                                    fi
                                    key_last=$key
                                    value_last=$value
                                else 
                                    value=${!value}
                                    if [ -z "$jq_channel_edit" ] 
                                    then
                                        jq_channel_edit="$jq_channel_edit(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key)=\"${value}\""
                                    else
                                        jq_channel_edit="$jq_channel_edit|(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key)=\"${value}\""
                                    fi
                                fi
                            fi

                            if [ "$jq_channel_add" == "[{" ] 
                            then
                                jq_channel_add="$jq_channel_add\"$key\":\"${value}\""
                            else
                                jq_channel_add="$jq_channel_add,\"$key\":\"${value}\""
                            fi

                        ;;
                    esac
                done
            done <<< "$chnl_sync_pairs"
            [ -s "$d_sync_file" ] || printf '{"%s":0}' "ret" > "$d_sync_file"
            if [ "$action" == "add" ] || [[ -z $($JQ_FILE "$jq_index"'[]|select(.chnl_pid=="'"$chnl_pid"'")' "$d_sync_file") ]]
            then
                jq_channel_add="${jq_channel_add}}]"
                $JQ_FILE "$jq_index"' += '"$jq_channel_add"'' "$d_sync_file" > "${d_sync_file}_tmp"
                mv "${d_sync_file}_tmp" "$d_sync_file"
            else
                jq_channel_edit="$jq_channel_edit|(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key_last)=\"${value_last}\""
                $JQ_FILE "${jq_channel_edit}" "$d_sync_file" > "${d_sync_file}_tmp"
                mv "${d_sync_file}_tmp" "$d_sync_file"
            fi
        fi
        echo -e "$info sync 执行成功..."
    fi
    action=""
}

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

    if [ "$(uname -m | grep -c 64)" -gt 0 ]
    then
        release_bit="64"
    else
        release_bit="32"
    fi

    case $release in
        "rpm") 
            yum -y update >/dev/null 2>&1
            depends=(unzip vim curl crond)
            for depend in "${depends[@]}"
            do
                if [[ ! -x $(command -v "$depend") ]] 
                then
                    if yum -y install "$depend" >/dev/null 2>&1
                    then
                        echo && echo -e "$info 依赖 $depend 安装成功..."
                    else
                        echo && echo -e "$error 依赖 $depend 安装失败..." && exit 1
                    fi
                fi
            done
        ;;
        "ubu") 
            apt-get -y update >/dev/null 2>&1
            depends=(unzip vim curl cron)
            for depend in "${depends[@]}"
            do
                if [[ ! -x $(command -v "$depend") ]] 
                then
                    if apt-get -y install "$depend" >/dev/null 2>&1
                    then
                        echo && echo -e "$info 依赖 $depend 安装成功..."
                    else
                        echo && echo -e "$error 依赖 $depend 安装失败..." && exit 1
                    fi
                fi
            done
        ;;
        "deb") 
            if [ -e "/etc/apt/sources.list.d/sources-aliyun-0.list" ] 
            then
                deb_list=$(< "/etc/apt/sources.list.d/sources-aliyun-0.list")
                rm -rf "/etc/apt/sources.list.d/sources-aliyun-0.list"
                rm -rf /var/lib/apt/lists/*
            else
                deb_list=$(< "/etc/apt/sources.list")
            fi

            if grep -q "jessie" <<< "$deb_list"
            then
                deb_list="
deb http://archive.debian.org/debian/ jessie main
deb-src http://archive.debian.org/debian/ jessie main

deb http://security.debian.org jessie/updates main
deb-src http://security.debian.org jessie/updates main
"
                printf '%s' "$deb_list" > "/etc/apt/sources.list"
            elif grep -q "wheezy" <<< "$deb_list" 
            then
                deb_list="
deb http://archive.debian.org/debian/ wheezy main
deb-src http://archive.debian.org/debian/ wheezy main

deb http://security.debian.org wheezy/updates main
deb-src http://security.debian.org wheezy/updates main
"
                printf '%s' "$deb_list" > "/etc/apt/sources.list"
            fi
            apt-get clean >/dev/null 2>&1
            apt-get -y update >/dev/null 2>&1
            depends=(unzip vim curl cron ufw)
            for depend in "${depends[@]}"
            do
                if [[ ! -x $(command -v "$depend") ]] 
                then
                    if apt-get -y install "$depend" >/dev/null 2>&1
                    then
                        echo && echo -e "$info 依赖 $depend 安装成功..."
                    else
                        echo && echo -e "$error 依赖 $depend 安装失败..." && exit 1
                    fi
                fi
            done
        ;;
        *) echo && echo -e "系统不支持!" && exit 1
        ;;
    esac
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
        wget --no-check-certificate "$FFMPEG_MIRROR_LINK/builds/$ffmpeg_package" $_PROGRESS_OPT -qO "$FFMPEG_PACKAGE_FILE"
        [ ! -e "$FFMPEG_PACKAGE_FILE" ] && echo -e "$error ffmpeg压缩包 下载失败 !" && exit 1
        tar -xJf "$FFMPEG_PACKAGE_FILE" -C "$IPTV_ROOT" && rm -rf "${FFMPEG_PACKAGE_FILE:-'notfound'}"
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
            wget --no-check-certificate "$FFMPEG_MIRROR_LINK/$jq_ver/jq-linux$release_bit" $_PROGRESS_OPT -qO "$JQ_FILE"
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
    echo -e "$info 检查依赖，耗时可能会很长..."
    Progress &
    progress_pid=$!
    CheckRelease
    kill $progress_pid
    if [ -e "$IPTV_ROOT" ]
    then
        echo -e "$error 目录已存在，请先卸载..." && exit 1
    else
        if grep -q '\--show-progress' < <(wget --help)
        then
            _PROGRESS_OPT="--show-progress"
        else
            _PROGRESS_OPT=""
        fi
        mkdir -p "$IPTV_ROOT"
        echo -e "$info 下载脚本..."
        wget --no-check-certificate "$CREATOR_LINK" -qO "$CREATOR_FILE" && chmod +x "$CREATOR_FILE"
        if [ ! -s "$CREATOR_FILE" ] 
        then
            echo -e "$error 无法连接到 Github ! 尝试备用链接..."
            wget --no-check-certificate "$CREATOR_LINK_BACKUP" -qO "$CREATOR_FILE" && chmod +x "$CREATOR_FILE"
            if [ ! -s "$CREATOR_FILE" ] 
            then
                echo -e "$error 无法连接备用链接!"
                rm -rf "${IPTV_ROOT:-'notfound'}"
                exit 1
            fi
        fi
        echo -e "$info 脚本就绪..."
        InstallFfmpeg
        InstallJq
        printf "[]" > "$CHANNELS_FILE"
        default='
{
    "default":'"$default"',
    "channels":[]
}'
        $JQ_FILE '(.)='"$default"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        echo -e "$info 安装完成..."
        ln -sf "$IPTV_ROOT"/ffmpeg-git-*/ff* /usr/local/bin/
    fi
}

Uninstall()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    CheckRelease
    echo "确定要 卸载此脚本以及产生的全部文件？[y/N]" && echo
    read -p "(默认: N):" uninstall_yn
    uninstall_yn=${uninstall_yn:-"N"}
    if [[ "$uninstall_yn" == [Yy] ]]
    then
        MonitorStop
        while IFS= read -r chnl_pid
        do
            GetChannelInfo
            if [ "${kind:-}" == "flv" ] 
            then
                if [ "$chnl_flv_status" == "on" ] 
                then
                    StopChannel
                fi
            elif [ "$chnl_status" == "on" ]
            then
                StopChannel
            fi
        done < <($JQ_FILE '.channels[].pid' $CHANNELS_FILE)
        rm -rf "${IPTV_ROOT:-'notfound'}"
        echo && echo -e "$info 卸载完成 !" && echo
    else
        echo && echo -e "$info 卸载已取消..." && echo
    fi
}

Update()
{
    CheckRelease
    if grep -q '\--show-progress' < <(wget --help)
    then
        _PROGRESS_OPT="--show-progress"
    else
        _PROGRESS_OPT=""
    fi
    rm -rf "$IPTV_ROOT"/ffmpeg-git-*/
    echo -e "$info 更新 FFmpeg..."
    InstallFfmpeg
    rm -rf "${JQ_FILE:-'notfound'}"
    echo -e "$info 更新 JQ..."
    InstallJq
    echo -e "$info 更新 iptv 脚本..."
    sh_new_ver=$(wget --no-check-certificate -qO- -t1 -T3 "$SH_LINK"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1 || true)
    if [ -z "$sh_new_ver" ] 
    then
        echo -e "$error 无法连接到 Github ! 尝试备用链接..."
        sh_new_ver=$(wget --no-check-certificate -qO- -t1 -T3 "$SH_LINK_BACKUP"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1 || true)
        [ -z "$sh_new_ver" ] && echo -e "$error 无法连接备用链接!" && exit 1
    fi

    if [ "$sh_new_ver" != "$sh_ver" ] 
    then
        rm -rf "${LOCK_FILE:-'notfound'}"
    fi
    wget --no-check-certificate "$SH_LINK" -qO "$SH_FILE" && chmod +x "$SH_FILE"
    if [ ! -s "$SH_FILE" ] 
    then
        wget --no-check-certificate "$SH_LINK_BACKUP" -qO "$SH_FILE"
        if [ ! -s "$SH_FILE" ] 
        then
            echo -e "$error 无法连接备用链接!"
            exit 1
        fi
    fi

    rm -rf ${CREATOR_FILE:-'notfound'}
    echo -e "$info 更新 Hls Stream Creator 脚本..."
    wget --no-check-certificate "$CREATOR_LINK" -qO "$CREATOR_FILE" && chmod +x "$CREATOR_FILE"
    if [ ! -s "$CREATOR_FILE" ] 
    then
        echo -e "$error 无法连接到 Github ! 尝试备用链接..."
        wget --no-check-certificate "$CREATOR_LINK_BACKUP" -qO "$CREATOR_FILE" && chmod +x "$CREATOR_FILE"
        if [ ! -s "$CREATOR_FILE" ] 
        then
            echo -e "$error 无法连接备用链接!"
            exit 1
        fi
    fi

    ln -sf "$IPTV_ROOT"/ffmpeg-git-*/ff* /usr/local/bin/
    echo -e "脚本已更新为最新版本[ $sh_new_ver ] !(输入: tv 使用)" && exit 0
}

UpdateSelf()
{
    GetDefault
    if [ "$d_version" != "$sh_ver" ] 
    then
        echo -e "$info 更新中，请稍等..." && echo
        printf -v update_date "%(%m-%d)T"
        cp -f "$CHANNELS_FILE" "${CHANNELS_FILE}_$update_date"
        
        default=$($JQ_FILE '(.playlist_name)="'"$d_playlist_name"'"|(.seg_dir_name)="'"$d_seg_dir_name"'"|(.seg_name)="'"$d_seg_name"'"|(.seg_length)='"$d_seg_length"'|(.seg_count)='"$d_seg_count"'|(.video_codec)="'"$d_video_codec"'"|(.audio_codec)="'"$d_audio_codec"'"|(.video_audio_shift)="'"$d_video_audio_shift"'"|(.quality)="'"$d_quality"'"|(.bitrates)="'"$d_bitrates"'"|(.const)="'"$d_const_yn"'"|(.encrypt)="'"$d_encrypt_yn"'"|(.key_name)="'"$d_key_name"'"|(.input_flags)="'"$d_input_flags"'"|(.output_flags)="'"$d_output_flags"'"|(.sync_file)="'"$d_sync_file"'"|(.sync_index)="'"$d_sync_index"'"|(.sync_pairs)="'"$d_sync_pairs"'"|(.schedule_file)="'"$d_schedule_file"'"|(.flv_delay_seconds)='"$d_flv_delay_seconds"'|(.flv_restart_nums)='"$d_flv_restart_nums"'|(.hls_delay_seconds)='"$d_hls_delay_seconds"'|(.hls_min_bitrates)='"$d_hls_min_bitrates"'|(.hls_restart_nums)='"$d_hls_restart_nums"'|(.anti_ddos_port)='"$d_anti_ddos_port"'|(.anti_ddos_seconds)='"$d_anti_ddos_seconds"'|(.anti_ddos_level)='"$d_anti_ddos_level"'' <<< "$default")

        $JQ_FILE '. + {default: '"$default"'}' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"

        GetChannelsInfo

        new_channels=""

        for((i=0;i<chnls_count;i++));
        do
            seg_dir_name=${chnls_seg_dir_name[i]%\'}
            seg_dir_name=${seg_dir_name#\'}
            seg_name=${chnls_seg_name[i]%\'}
            seg_name=${seg_name#\'}
            video_audio_shift=${chnls_video_audio_shift[i]%\'}
            video_audio_shift=${video_audio_shift#\'}
            quality=${chnls_quality[i]%\'}
            quality=${quality#\'}
            bitrates=${chnls_bitrates[i]%\'}
            bitrates=${bitrates#\'}
            const=${chnls_const[i]%\'}
            const=${const#\'}
            encrypt=${chnls_encrypt[i]%\'}
            encrypt=${encrypt#\'}
            key_name=${chnls_key_name[i]%\'}
            key_name=${key_name#\'}
            input_flags=${chnls_input_flags[i]%\'}
            input_flags=${input_flags#\'}
            output_flags=${chnls_output_flags[i]%\'}
            output_flags=${output_flags#\'}
            channel_name=${chnls_channel_name[i]%\'}
            channel_name=${channel_name#\'}
            sync_pairs=${chnls_sync_pairs[i]%\'}
            sync_pairs=${sync_pairs#\'}
            flv_push_link=${chnls_flv_push_link[i]%\'}
            flv_push_link=${flv_push_link#\'}
            flv_pull_link=${chnls_flv_pull_link[i]%\'}
            flv_pull_link=${flv_pull_link#\'}

            [ -n "$new_channels" ] && new_channels="$new_channels,"
            new_channels=$new_channels'{
                "pid":'"${chnls_pid[i]}"',
                "status":"'"${chnls_status[i]}"'",
                "stream_link":"'"${chnls_stream_link[i]}"'",
                "output_dir_name":"'"${chnls_output_dir_name[i]}"'",
                "playlist_name":"'"${chnls_playlist_name[i]}"'",
                "seg_dir_name":"'"$seg_dir_name"'",
                "seg_name":"'"$seg_name"'",
                "seg_length":'"${chnls_seg_length[i]}"',
                "seg_count":'"${chnls_seg_count[i]}"',
                "video_codec":"'"${chnls_video_codec[i]}"'",
                "audio_codec":"'"${chnls_audio_codec[i]}"'",
                "video_audio_shift":"'"$video_audio_shift"'",
                "quality":"'"$quality"'",
                "bitrates":"'"$bitrates"'",
                "const":"'"$const"'",
                "encrypt":"'"$encrypt"'",
                "key_name":"'"$key_name"'",
                "input_flags":"'"$input_flags"'",
                "output_flags":"'"$output_flags"'",
                "channel_name":"'"$channel_name"'",
                "sync_pairs":"'"$sync_pairs"'",
                "flv_status":"'"${chnls_flv_status[i]:-off}"'",
                "flv_push_link":"'"$flv_push_link"'",
                "flv_pull_link":"'"$flv_pull_link"'"
            }'
        done
        new_channels="[$new_channels]"
        $JQ_FILE --argjson channels "$new_channels" '.channels = $channels' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    fi
    printf "" > ${LOCK_FILE}
}

GetDefault()
{
    while IFS= read -r d
    do
        if [[ "$d" == *"playlist_name: "* ]] 
        then
            d_playlist_name=${d#*playlist_name: }
            d_playlist_name=${d_playlist_name%, seg_dir_name:*}
        else
            d_playlist_name=""
        fi
        d_playlist_name_text=${d_playlist_name:-"随机名称"}
        d_seg_dir_name=${d#*seg_dir_name: }
        if [[ "$d" == *"seg_name: "* ]] 
        then
            d_seg_dir_name=${d_seg_dir_name%, seg_name:*}
            d_seg_name=${d#*seg_name: }
            d_seg_name=${d_seg_name%, seg_length:*}
        else
            d_seg_dir_name=${d_seg_dir_name%, seg_length:*}
            d_seg_name=""
        fi
        d_seg_dir_name_text=${d_seg_dir_name:-"不使用"}
        d_seg_name_text=${d_seg_name:-"跟m3u8名称相同"}
        d_seg_length=${d#*seg_length: }
        d_seg_length=${d_seg_length%, seg_count:*}
        d_seg_count=${d#*seg_count: }
        d_seg_count=${d_seg_count%, video_codec:*}
        d_video_codec=${d#*video_codec: }
        d_video_codec=${d_video_codec%, audio_codec:*}
        d_audio_codec=${d#*audio_codec: }
        d_audio_codec=${d_audio_codec%, video_audio_shift:*}
        d_video_audio_shift=${d#*video_audio_shift: }
        d_video_audio_shift=${d_video_audio_shift%, quality:*}
        v_or_a=${d_video_audio_shift%_*}
        if [ "$v_or_a" == "v" ] 
        then
            d_video_shift=${d_video_audio_shift#*_}
            d_video_audio_shift_text="画面延迟 $d_video_shift 秒"
        elif [ "$v_or_a" == "a" ] 
        then
            d_audio_shift=${d_video_audio_shift#*_}
            d_video_audio_shift_text="声音延迟 $d_audio_shift 秒"
        else
            d_video_audio_shift_text="不设置"
        fi
        d_quality=${d#*quality: }
        d_quality=${d_quality%, bitrates:*}
        d_quality_text=${d_quality:-"不设置"}
        d_bitrates=${d#*bitrates: }
        d_bitrates=${d_bitrates%, const:*}
        d_const_yn=${d#*const: }
        d_const_yn=${d_const_yn%, encrypt:*}
        if [ "$d_const_yn" == "no" ] 
        then
            d_const_text="N"
        else
            d_const_text="Y"
        fi
        d_encrypt_yn=${d#*encrypt: }
        d_encrypt_yn=${d_encrypt_yn%, key_name:*}
        if [[ "$d" == *"key_name: "* ]] 
        then
            d_encrypt_yn=${d_encrypt_yn%, key_name:*}
            d_key_name=${d#*key_name: }
            d_key_name=${d_key_name%, input_flags:*}
        else
            d_encrypt_yn=${d_encrypt_yn%, input_flags:*}
            d_key_name=""
        fi
        if [ "$d_encrypt_yn" == "no" ] 
        then
            d_encrypt_text="N"
        else
            d_encrypt_text="Y"
        fi
        d_key_name_text=${d_key_name:-"跟m3u8名称相同"}
        d_input_flags=${d#*input_flags: }
        d_input_flags=${d_input_flags%, output_flags:*}
        d_output_flags=${d#*output_flags: }
        d_output_flags=${d_output_flags%, sync_file:*}
        d_sync_file=${d#*sync_file: }
        d_sync_file=${d_sync_file%, sync_index:*}
        d_sync_index=${d#*sync_index: }
        d_sync_index=${d_sync_index%, sync_pairs:*}
        d_sync_pairs=${d#*sync_pairs: }
        d_sync_pairs=${d_sync_pairs%, schedule_file:*}
        d_sync_pairs_text=${d_sync_pairs:-"不设置"}
        d_schedule_file=${d#*schedule_file: }
        if [[ "$d" == *"flv_delay_seconds: "* ]] 
        then
            d_schedule_file=${d_schedule_file%, flv_delay_seconds:*}
            d_flv_delay_seconds=${d#*flv_delay_seconds: }
            d_flv_delay_seconds=${d_flv_delay_seconds%, flv_restart_nums:*}
            d_flv_delay_seconds=${d_flv_delay_seconds:-20}
            d_flv_restart_nums=${d#*flv_restart_nums: }
            d_flv_restart_nums=${d_flv_restart_nums%, hls_delay_seconds:*}
            d_flv_restart_nums=${d_flv_restart_nums:-20}
            d_hls_delay_seconds=${d#*hls_delay_seconds: }
            d_hls_delay_seconds=${d_hls_delay_seconds%, hls_min_bitrates:*}
            d_hls_delay_seconds=${d_hls_delay_seconds:-120}
            d_hls_min_bitrates=${d#*hls_min_bitrates: }
            d_hls_min_bitrates=${d_hls_min_bitrates%, hls_restart_nums:*}
            d_hls_min_bitrates=${d_hls_min_bitrates:-500}
            d_hls_restart_nums=${d#*hls_restart_nums: }
            d_hls_restart_nums=${d_hls_restart_nums%, anti_ddos_port:*}
            d_hls_restart_nums=${d_hls_restart_nums:-20}
            d_anti_ddos_port=${d#*anti_ddos_port: }
            d_anti_ddos_port=${d_anti_ddos_port%, anti_ddos_seconds:*}
            d_anti_ddos_port=${d_anti_ddos_port:-80}
            d_anti_ddos_seconds=${d#*anti_ddos_seconds: }
            d_anti_ddos_seconds=${d_anti_ddos_seconds%, anti_ddos_level:*}
            d_anti_ddos_seconds=${d_anti_ddos_seconds:-120}
            d_anti_ddos_level=${d#*anti_ddos_level: }
            d_anti_ddos_level=${d_anti_ddos_level%, version:*}
            d_anti_ddos_level=${d_anti_ddos_level:-6}
        elif [[ "$d" == *"anti_ddos_port: "* ]] 
        then
            d_schedule_file=${d_schedule_file%, anti_ddos_port:*}
            d_anti_ddos_port=${d#*anti_ddos_port: }
            d_anti_ddos_port=${d_anti_ddos_port%, anti_ddos_seconds:*}
            d_anti_ddos_port=${d_anti_ddos_port:-80}
            d_anti_ddos_seconds=${d#*anti_ddos_seconds: }
            d_anti_ddos_seconds=${d_anti_ddos_seconds%, anti_ddos_level:*}
            d_anti_ddos_seconds=${d_anti_ddos_seconds:-120}
            d_anti_ddos_level=${d#*anti_ddos_level: }
            d_anti_ddos_level=${d_anti_ddos_level%, version:*}
            d_anti_ddos_level=${d_anti_ddos_level:-6}
            d_flv_delay_seconds=20
            d_flv_restart_nums=20
            d_hls_delay_seconds=120
            d_hls_min_bitrates=500
            d_hls_restart_nums=20
        else
            d_schedule_file=${d_schedule_file%, version:*}
            d_flv_delay_seconds=20
            d_flv_restart_nums=20
            d_hls_delay_seconds=120
            d_hls_min_bitrates=500
            d_hls_restart_nums=20
            d_anti_ddos_port=80
            d_anti_ddos_seconds=120
            d_anti_ddos_level=6
        fi
        d_version=${d#*version: }
    done < <($JQ_FILE -r '.default | to_entries | map([.key,.value]|join(": ")) | join(", ")' "$CHANNELS_FILE")
}

GetChannelsInfo()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1

    chnls_count=0
    chnls_pid=()
    chnls_status=()
    chnls_stream_link=()
    chnls_output_dir_name=()
    chnls_playlist_name=()
    chnls_seg_dir_name=()
    chnls_seg_name=()
    chnls_seg_length=()
    chnls_seg_count=()
    chnls_video_codec=()
    chnls_audio_codec=()
    chnls_video_audio_shift=()
    chnls_quality=()
    chnls_bitrates=()
    chnls_const=()
    chnls_encrypt=()
    chnls_key_name=()
    chnls_input_flags=()
    chnls_output_flags=()
    chnls_channel_name=()
    chnls_sync_pairs=()
    chnls_flv_status=()
    chnls_flv_push_link=()
    chnls_flv_pull_link=()
    
    while IFS= read -r channel
    do
        chnls_count=$((chnls_count+1))
        map_pid=${channel#*pid: }
        map_pid=${map_pid%, status:*}
        map_status=${channel#*status: }
        map_status=${map_status%, stream_link:*}
        map_stream_link=${channel#*stream_link: }
        map_stream_link=${map_stream_link%, output_dir_name:*}
        map_output_dir_name=${channel#*output_dir_name: }
        map_output_dir_name=${map_output_dir_name%, playlist_name:*}
        map_playlist_name=${channel#*playlist_name: }
        map_playlist_name=${map_playlist_name%, seg_dir_name:*}
        map_seg_dir_name=${channel#*seg_dir_name: }
        map_seg_dir_name=${map_seg_dir_name%, seg_name:*}
        map_seg_name=${channel#*seg_name: }
        map_seg_name=${map_seg_name%, seg_length:*}
        map_seg_length=${channel#*seg_length: }
        map_seg_length=${map_seg_length%, seg_count:*}
        map_seg_count=${channel#*seg_count: }
        map_seg_count=${map_seg_count%, video_codec:*}
        map_video_codec=${channel#*video_codec: }
        map_video_codec=${map_video_codec%, audio_codec:*}
        map_audio_codec=${channel#*audio_codec: }
        map_audio_codec=${map_audio_codec%, video_audio_shift:*}
        map_video_audio_shift=${channel#*video_audio_shift: }
        map_video_audio_shift=${map_video_audio_shift%, quality:*}
        map_video_audio_shift=${map_video_audio_shift//null/}
        map_quality=${channel#*quality: }
        map_quality=${map_quality%, bitrates:*}
        map_bitrates=${channel#*bitrates: }
        map_bitrates=${map_bitrates%, const:*}
        map_const=${channel#*const: }
        map_const=${map_const%, encrypt:*}
        map_encrypt=${channel#*encrypt: }
        map_encrypt=${map_encrypt%, key_name:*}
        map_key_name=${channel#*key_name: }
        map_key_name=${map_key_name%, input_flags:*}
        map_input_flags=${channel#*input_flags: }
        map_input_flags=${map_input_flags%, output_flags:*}
        map_output_flags=${channel#*output_flags: }
        map_output_flags=${map_output_flags%, channel_name:*}
        map_channel_name=${channel#*channel_name: }
        map_channel_name=${map_channel_name%, sync_pairs:*}
        map_sync_pairs=${channel#*sync_pairs: }
        map_sync_pairs=${map_sync_pairs%, flv_status:*}
        map_sync_pairs=${map_sync_pairs//null/}
        map_flv_status=${channel#*flv_status: }
        map_flv_status=${map_flv_status%, flv_push_link:*}
        map_flv_status=${map_flv_status//null/off}
        map_flv_push_link=${channel#*flv_push_link: }
        map_flv_push_link=${map_flv_push_link%, flv_pull_link:*}
        [ "$map_flv_push_link" == null ] && map_flv_push_link=""
        map_flv_pull_link=${channel#*flv_pull_link: }
        [ "$map_flv_pull_link" == null ] && map_flv_pull_link=""

        chnls_pid+=("$map_pid")
        chnls_status+=("$map_status")
        chnls_stream_link+=("$map_stream_link")
        chnls_output_dir_name+=("$map_output_dir_name")
        chnls_playlist_name+=("$map_playlist_name")
        chnls_seg_dir_name+=("${map_seg_dir_name:-''}")
        chnls_seg_name+=("$map_seg_name")
        chnls_seg_length+=("$map_seg_length")
        chnls_seg_count+=("$map_seg_count")
        chnls_video_codec+=("$map_video_codec")
        chnls_audio_codec+=("$map_audio_codec")
        chnls_video_audio_shift+=("${map_video_audio_shift:-''}")
        chnls_quality+=("${map_quality:-''}")
        chnls_bitrates+=("${map_bitrates:-''}")
        chnls_const+=("${map_const:-''}")
        chnls_encrypt+=("${map_encrypt:-''}")
        chnls_key_name+=("${map_key_name:-''}")
        chnls_input_flags+=("${map_input_flags:-''}")
        chnls_output_flags+=("${map_output_flags:-''}")
        chnls_channel_name+=("$map_channel_name")
        chnls_sync_pairs+=("${map_sync_pairs:-''}")
        chnls_flv_status+=("$map_flv_status")
        chnls_flv_push_link+=("${map_flv_push_link:-''}")
        chnls_flv_pull_link+=("${map_flv_pull_link:-''}")
        
    done < <($JQ_FILE -r '.channels | to_entries | map("pid: \(.value.pid), status: \(.value.status), stream_link: \(.value.stream_link), output_dir_name: \(.value.output_dir_name), playlist_name: \(.value.playlist_name), seg_dir_name: \(.value.seg_dir_name), seg_name: \(.value.seg_name), seg_length: \(.value.seg_length), seg_count: \(.value.seg_count), video_codec: \(.value.video_codec), audio_codec: \(.value.audio_codec), video_audio_shift: \(.value.video_audio_shift), quality: \(.value.quality), bitrates: \(.value.bitrates), const: \(.value.const), encrypt: \(.value.encrypt), key_name: \(.value.key_name), input_flags: \(.value.input_flags), output_flags: \(.value.output_flags), channel_name: \(.value.channel_name), sync_pairs: \(.value.sync_pairs), flv_status: \(.value.flv_status), flv_push_link: \(.value.flv_push_link), flv_pull_link: \(.value.flv_pull_link)") | .[]' "$CHANNELS_FILE")

    return 0
}

ListChannels()
{
    GetChannelsInfo
    if [ "$chnls_count" == 0 ]
    then
        echo -e "$error 没有发现 频道，请检查 !" && exit 1
    fi
    chnls_list=""
    for((index = 0; index < chnls_count; index++)); do
        chnls_status_index=${chnls_status[index]}
        chnls_pid_index=${chnls_pid[index]}
        chnls_output_dir_name_index=${chnls_output_dir_name[index]}
        chnls_output_dir_root="$LIVE_ROOT/$chnls_output_dir_name_index"
        chnls_video_codec_index=${chnls_video_codec[index]}
        chnls_audio_codec_index=${chnls_audio_codec[index]}
        chnls_video_audio_shift_index=${chnls_video_audio_shift[index]%\'}
        chnls_video_audio_shift_index=${chnls_video_audio_shift_index#\'}

        v_or_a=${chnls_video_audio_shift_index%_*}
        if [ "$v_or_a" == "v" ] 
        then
            chnls_video_shift=${chnls_video_audio_shift_index#*_}
            chnls_video_audio_shift_text="画面延迟 $chnls_video_shift 秒"
        elif [ "$v_or_a" == "a" ] 
        then
            chnls_audio_shift=${chnls_video_audio_shift_index#*_}
            chnls_video_audio_shift_text="声音延迟 $chnls_audio_shift 秒"
        else
            chnls_video_audio_shift_text="不设置"
        fi

        chnls_quality_index=${chnls_quality[index]%\'}
        chnls_quality_index=${chnls_quality_index#\'}
        chnls_playlist_name_index=${chnls_playlist_name[index]}
        chnls_const_index=${chnls_const[index]%\'}
        chnls_const_index=${chnls_const_index#\'}
        if [ "$chnls_const_index" == "no" ] 
        then
            chnls_const_index_text=" 固定频率:否"
        else
            chnls_const_index_text=" 固定频率:是"
        fi
        chnls_bitrates_index=${chnls_bitrates[index]%\'}
        chnls_bitrates_index=${chnls_bitrates_index#\'}
        chnls_quality_text=""
        chnls_bitrates_text=""
        chnls_playlist_file_text=""

        if [ -n "$chnls_bitrates_index" ] 
        then
            while IFS= read -r chnls_br
            do
                if [[ "$chnls_br" == *"-"* ]]
                then
                    chnls_br_a=${chnls_br%-*}
                    chnls_br_b=" 分辨率: ${chnls_br#*-}"
                    chnls_quality_text="${chnls_quality_text}[ -maxrate ${chnls_br_a}k -bufsize ${chnls_br_a}k${chnls_br_b} ] "
                    chnls_bitrates_text="${chnls_bitrates_text}[ 比特率 ${chnls_br_a}k${chnls_br_b}${chnls_const_index_text} ] "
                    chnls_playlist_file_text="$chnls_playlist_file_text$green$chnls_output_dir_root/${chnls_playlist_name_index}_$chnls_br_a.m3u8$plain "
                else
                    chnls_quality_text="${chnls_quality_text}[ -maxrate ${chnls_br}k -bufsize ${chnls_br}k ] "
                    chnls_bitrates_text="${chnls_bitrates_text}[ 比特率 ${chnls_br}k${chnls_const_index_text} ] "
                    chnls_playlist_file_text="$chnls_playlist_file_text$green$chnls_output_dir_root/${chnls_playlist_name_index}_$chnls_br.m3u8$plain "
                fi
            done <<< ${chnls_bitrates_index//,/$'\n'}
        else
            chnls_playlist_file_text="$chnls_playlist_file_text$green$chnls_output_dir_root/${chnls_playlist_name_index}.m3u8$plain "
        fi
        
        chnls_channel_name_index=${chnls_channel_name[index]%\'}
        chnls_channel_name_index=${chnls_channel_name_index#\'}
        chnls_sync_pairs_index=${chnls_sync_pairs[index]%\'}
        chnls_sync_pairs_index=${chnls_sync_pairs_index#\'}
        chnls_flv_status_index=${chnls_flv_status[index]}
        chnls_flv_push_link_index=${chnls_flv_push_link[index]%\'}
        chnls_flv_push_link_index=${chnls_flv_push_link_index#\'}
        chnls_flv_pull_link_index=${chnls_flv_pull_link[index]%\'}
        chnls_flv_pull_link_index=${chnls_flv_pull_link_index#\'}

        if [ -z "${kind:-}" ] 
        then
            if [ "$chnls_status_index" == "on" ]
            then
                if kill -0 "$chnls_pid_index" 2> /dev/null 
                then
                    working=0
                    while IFS= read -r ffmpeg_pid 
                    do
                        if [ -z "$ffmpeg_pid" ] 
                        then
                            working=1
                        else
                            while IFS= read -r real_ffmpeg_pid 
                            do
                                if [ -z "$real_ffmpeg_pid" ] 
                                then
                                    if kill -0 "$ffmpeg_pid" 2> /dev/null 
                                    then
                                        working=1
                                    fi
                                else
                                    if kill -0 "$real_ffmpeg_pid" 2> /dev/null 
                                    then
                                        working=1
                                    fi
                                fi
                            done <<< $(pgrep -P "$ffmpeg_pid")
                        fi
                    done <<< $(pgrep -P "$chnls_pid_index")

                    if [ "$working" == 1 ] 
                    then
                        chnls_status_text=$green"开启"$plain
                    else
                        chnls_status_text=$red"关闭"$plain
                        $JQ_FILE '(.channels[]|select(.pid=='"$chnls_pid_index"')|.status)="off"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
                        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
                        chnl_pid=$chnls_pid_index
                        GetChannelInfo
                        StopChannel
                    fi
                else
                    chnls_status_text=$red"关闭"$plain
                    $JQ_FILE '(.channels[]|select(.pid=='"$chnls_pid_index"')|.status)="off"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
                    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
                    chnl_pid=$chnls_pid_index
                    GetChannelInfo
                    StopChannel
                fi
            else
                chnls_status_text=$red"关闭"$plain
            fi
        fi

        if [ -n "$chnls_quality_index" ] 
        then
            chnls_video_quality_text="crf值$chnls_quality_index ${chnls_quality_text:-"不设置"}"
        else
            chnls_video_quality_text="比特率值 ${chnls_bitrates_text:-"不设置"}"
        fi

        if [ -z "${kind:-}" ] && [ "$chnls_video_codec_index" == "copy" ] && [ "$chnls_audio_codec_index" == "copy" ]  
        then
            chnls_video_quality_text="原画"
        fi

        if [ -z "${kind:-}" ] 
        then
            chnls_list=$chnls_list"# $green$((index+1))$plain 进程ID: $green${chnls_pid_index}$plain 状态: $chnls_status_text 频道名称: $green${chnls_channel_name_index}$plain 编码: $green$chnls_video_codec_index:$chnls_audio_codec_index$plain 延迟: $green$chnls_video_audio_shift_text$plain 视频质量: $green$chnls_video_quality_text$plain m3u8位置: $chnls_playlist_file_text\n\n"
        elif [ "$kind" == "flv" ] 
        then
            if [ "$chnls_flv_status_index" == "on" ] 
            then
                chnls_flv_status_text=$green"开启"$plain
            else
                chnls_flv_status_text=$red"关闭"$plain
            fi
            chnls_list=$chnls_list"# $green$((index+1))$plain 进程ID: $green${chnls_pid_index}$plain 状态: $chnls_flv_status_text 频道名称: $green${chnls_channel_name_index}$plain 编码: $green$chnls_video_codec_index:$chnls_audio_codec_index$plain 延迟: $green$chnls_video_audio_shift_text$plain 视频质量: $green$chnls_video_quality_text$plain flv推流地址: $green${chnls_flv_push_link_index:-"无"}$plain flv拉流地址: $green${chnls_flv_pull_link_index:-"无"}$plain\n\n"
        fi
        
    done
    echo && echo -e "=== 频道总数 $green $chnls_count $plain" && echo
    echo -e "$chnls_list"
}

GetChannelInfo(){
    if [ -z "${d_sync_file:-}" ] 
    then
        GetDefault
    fi
    
    if [ -z "${monitor:-}" ] 
    then
        select=".value.pid==$chnl_pid"
    elif [ "${kind:-}" == "flv" ] 
    then
        select=".value.flv_push_link==\"$chnl_flv_push_link\""
    else
        select=".value.output_dir_name==\"$output_dir_name\""
    fi

    found=0
    while IFS= read -r channel
    do
        found=1
        chnl_pid=${channel#*pid: }
        chnl_pid=${chnl_pid%, status:*}
        chnl_status=${channel#*status: }
        chnl_status=${chnl_status%, stream_link:*}
        chnl_stream_link=${channel#*stream_link: }
        chnl_stream_link=${chnl_stream_link%, output_dir_name:*}
        chnl_output_dir_name=${channel#*output_dir_name: }
        chnl_output_dir_name=${chnl_output_dir_name%, playlist_name:*}
        chnl_output_dir_root="$LIVE_ROOT/$chnl_output_dir_name"
        chnl_playlist_name=${channel#*playlist_name: }
        chnl_playlist_name=${chnl_playlist_name%, seg_dir_name:*}
        chnl_seg_dir_name=${channel#*seg_dir_name: }
        chnl_seg_dir_name=${chnl_seg_dir_name%, seg_name:*}
        chnl_seg_name=${channel#*seg_name: }
        chnl_seg_name=${chnl_seg_name%, seg_length:*}
        chnl_seg_length=${channel#*seg_length: }
        chnl_seg_length=${chnl_seg_length%, seg_count:*}
        chnl_seg_count=${channel#*seg_count: }
        chnl_seg_count=${chnl_seg_count%, video_codec:*}
        chnl_video_codec=${channel#*video_codec: }
        chnl_video_codec=${chnl_video_codec%, audio_codec:*}
        chnl_audio_codec=${channel#*audio_codec: }
        chnl_audio_codec=${chnl_audio_codec%, video_audio_shift:*}
        chnl_video_audio_shift=${channel#*video_audio_shift: }
        chnl_video_audio_shift=${chnl_video_audio_shift%, quality:*}
        v_or_a=${chnl_video_audio_shift%_*}
        if [ "$v_or_a" == "v" ] 
        then
            chnl_video_shift=${chnl_video_audio_shift#*_}
            chnl_video_audio_shift_text="画面延迟 $chnl_video_shift 秒"
        elif [ "$v_or_a" == "a" ] 
        then
            chnl_audio_shift=${chnl_video_audio_shift#*_}
            chnl_video_audio_shift_text="声音延迟 $chnl_audio_shift 秒"
        else
            chnl_video_audio_shift_text="不设置"
        fi
        chnl_quality=${channel#*quality: }
        chnl_quality=${chnl_quality%, bitrates:*}
        chnl_bitrates=${channel#*bitrates: }
        chnl_bitrates=${chnl_bitrates%, const:*}
        chnl_const_yn=${channel#*const: }
        chnl_const_yn=${chnl_const_yn%, encrypt:*}
        if [ "$chnl_const_yn" == "no" ]
        then
            chnl_const=""
            chnl_const_text=" 固定频率:否"
        else
            chnl_const="-C"
            chnl_const_text=" 固定频率:是"
        fi
        chnl_encrypt=${channel#*encrypt: }
        chnl_encrypt=${chnl_encrypt%, key_name:*}
        chnl_key_name=${channel#*key_name: }
        chnl_key_name=${chnl_key_name%, input_flags:*}
        if [ "$chnl_encrypt" == "no" ]
        then
            chnl_encrypt=""
            chnl_encrypt_text=$red"否"$plain
            chnl_key_name_text=$red$chnl_key_name$plain
        else
            chnl_encrypt="-e"
            chnl_encrypt_text=$green"是"$plain
            chnl_key_name_text=$green$chnl_key_name$plain
        fi
        chnl_input_flags=${channel#*input_flags: }
        chnl_input_flags=${chnl_input_flags%, output_flags:*}
        chnl_output_flags=${channel#*output_flags: }
        chnl_output_flags=${chnl_output_flags%, channel_name:*}
        chnl_channel_name=${channel#*channel_name: }
        chnl_channel_name=${chnl_channel_name%, sync_pairs:*}
        chnl_sync_pairs=${channel#*sync_pairs: }
        chnl_sync_pairs=${chnl_sync_pairs%, flv_status:*}
        chnl_flv_status=${channel#*flv_status: }
        chnl_flv_status=${chnl_flv_status%, flv_push_link:*}
        chnl_flv_push_link=${channel#*flv_push_link: }
        chnl_flv_push_link=${chnl_flv_push_link%, flv_pull_link:*}
        chnl_flv_pull_link=${channel#*flv_pull_link: }
        
        if [ -z "${monitor:-}" ] 
        then
            if [ "$chnl_status" == "on" ]
            then
                chnl_status_text=$green"开启"$plain
            else
                chnl_status_text=$red"关闭"$plain
            fi

            chnl_seg_dir_name_text=${chnl_seg_dir_name:-"不使用"}
            chnl_seg_length_text=$chnl_seg_length"s"

            chnl_crf_text=""
            chnl_nocrf_text=""
            chnl_playlist_file_text=""

            if [ -n "$chnl_bitrates" ] 
            then
                while IFS= read -r chnl_br
                do
                    if [[ "$chnl_br" == *"-"* ]]
                    then
                        chnl_br_a=${chnl_br%-*}
                        chnl_br_b=" 分辨率: ${chnl_br#*-}"
                        chnl_crf_text="${chnl_crf_text}[ -maxrate ${chnl_br_a}k -bufsize ${chnl_br_a}k${chnl_br_b} ] "
                        chnl_nocrf_text="${chnl_nocrf_text}[ 比特率 ${chnl_br_a}k${chnl_br_b}${chnl_const_text} ] "
                        chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}_$chnl_br_a.m3u8$plain "
                    else
                        chnl_crf_text="${chnl_crf_text}[ -maxrate ${chnl_br}k -bufsize ${chnl_br}k ] "
                        chnl_nocrf_text="${chnl_nocrf_text}[ 比特率 ${chnl_br}k${chnl_const_text} ] "
                        chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}_$chnl_br.m3u8$plain "
                    fi
                done <<< ${chnl_bitrates//,/$'\n'}
            else
                chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}.m3u8$plain "
            fi

            if [ -n "$d_sync_file" ] && [ -n "$d_sync_index" ] && [ -n "$d_sync_pairs" ] && [[ $d_sync_pairs == *"=http"* ]] 
            then
                chnl_playlist_link=${d_sync_pairs#*=http}
                chnl_playlist_link=${chnl_playlist_link%%,*}
                chnl_playlist_link="http$chnl_playlist_link/$chnl_output_dir_name/${chnl_playlist_name}_master.m3u8"
                chnl_playlist_link_text="$green$chnl_playlist_link$plain"
            else
                chnl_playlist_link_text="$red请先设置 sync$plain"
            fi

            if [ -n "$chnl_quality" ] 
            then
                chnl_video_quality_text="crf值$chnl_quality ${chnl_crf_text:-"不设置"}"
            else
                chnl_video_quality_text="比特率值 ${chnl_nocrf_text:-"不设置"}"
            fi

            if [ "$chnl_flv_status" == "on" ]
            then
                chnl_flv_status_text=$green"开启"$plain
            else
                chnl_flv_status_text=$red"关闭"$plain
            fi

            if [ -z "${kind:-}" ] && [ "$chnl_video_codec" == "copy" ] && [ "$chnl_audio_codec" == "copy" ]  
            then
                chnl_video_quality_text="原画"
                chnl_playlist_link=${chnl_playlist_link:-}
                chnl_playlist_link=${chnl_playlist_link//_master.m3u8/.m3u8}
                chnl_playlist_link_text=${chnl_playlist_link_text//_master.m3u8/.m3u8}
            elif [ -z "$chnl_bitrates" ] 
            then
                chnl_playlist_link=${chnl_playlist_link:-}
                chnl_playlist_link=${chnl_playlist_link//_master.m3u8/.m3u8}
                chnl_playlist_link_text=${chnl_playlist_link_text//_master.m3u8/.m3u8}
            fi
        fi
    done < <($JQ_FILE -r '.channels | to_entries | map(select('"$select"')) | map("pid: \(.value.pid), status: \(.value.status), stream_link: \(.value.stream_link), output_dir_name: \(.value.output_dir_name), playlist_name: \(.value.playlist_name), seg_dir_name: \(.value.seg_dir_name), seg_name: \(.value.seg_name), seg_length: \(.value.seg_length), seg_count: \(.value.seg_count), video_codec: \(.value.video_codec), audio_codec: \(.value.audio_codec), video_audio_shift: \(.value.video_audio_shift), quality: \(.value.quality), bitrates: \(.value.bitrates), const: \(.value.const), encrypt: \(.value.encrypt), key_name: \(.value.key_name), input_flags: \(.value.input_flags), output_flags: \(.value.output_flags), channel_name: \(.value.channel_name), sync_pairs: \(.value.sync_pairs), flv_status: \(.value.flv_status), flv_push_link: \(.value.flv_push_link), flv_pull_link: \(.value.flv_pull_link)") | .[]' "$CHANNELS_FILE")

    if [ "$found" == 0 ] && [ -z "${monitor:-}" ]
    then
        echo && echo -e "$error 频道发生变化，请重试 !" && echo && exit 1
    fi
}

ViewChannelInfo()
{
    echo "===================================================" && echo
    echo -e " 频道 [$chnl_channel_name] 的配置信息：" && echo
    echo -e " 进程ID\t    : $green$chnl_pid$plain"

    if [ -z "${kind:-}" ] 
    then
        echo -e " 状态\t    : $chnl_status_text"
        echo -e " m3u8名称   : $green$chnl_playlist_name$plain"
        echo -e " m3u8位置   : $chnl_playlist_file_text"
        echo -e " m3u8链接   : $chnl_playlist_link_text"
        echo -e " 段子目录   : $green$chnl_seg_dir_name_text$plain"
        echo -e " 段名称\t    : $green$chnl_seg_name$plain"
        echo -e " 段时长\t    : $green$chnl_seg_length_text$plain"
        echo -e " m3u8包含段数目 : $green$chnl_seg_count$plain"
        echo -e " 加密\t    : $chnl_encrypt_text"
        if [ -n "$chnl_encrypt" ] 
        then
            echo -e " key名称    : $chnl_key_name_text"
        fi
    elif [ "$kind" == "flv" ] 
    then
        echo -e " 状态\t    : $chnl_flv_status_text"
        echo -e " 推流地址   : $green${chnl_flv_push_link:-"无"}$plain"
        echo -e " 拉流地址   : $green${chnl_flv_pull_link:-"无"}$plain"
    fi
    
    echo -e " 直播源\t    : $green$chnl_stream_link$plain"
    echo -e " 视频编码   : $green$chnl_video_codec$plain"
    echo -e " 音频编码   : $green$chnl_audio_codec$plain"
    echo -e " 视频质量   : $green$chnl_video_quality_text$plain"
    echo -e " 延迟\t    : $green$chnl_video_audio_shift_text$plain"

    echo -e " input flags    : $green${chnl_input_flags:-"不设置"}$plain"
    echo -e " output flags   : $green${chnl_output_flags:-"不设置"}$plain"
    if [ -n "$chnl_sync_pairs" ] 
    then
        echo -e " sync_pairs     : $green${chnl_sync_pairs}$plain"
    fi
    echo
}

InputChannelsIndex()
{
    echo -e "请输入频道的序号 "
    echo -e "$tip 多个序号用空格分隔 比如: 5 7 9-11 " && echo
    while read -p "(默认: 取消):" chnls_index_input
    do
        chnls_pid_chosen=()
        IFS=" " read -ra chnls_index <<< "$chnls_index_input"
        [ -z "$chnls_index_input" ] && echo "已取消..." && exit 1

        for chnl_index in "${chnls_index[@]}"
        do
            if [[ $chnl_index == *"-"* ]] 
            then
                chnl_index_start=${chnl_index%-*}
                chnl_index_end=${chnl_index#*-}

                if [[ $chnl_index_start == *[!0-9]* ]] || [[ $chnl_index_end == *[!0-9]* ]] 
                then
                    echo -e "$error 多选输入错误！" && echo
                    continue 2
                elif [[ $chnl_index_start -gt 0 ]] && [[ ! $chnl_index_end -gt $chnls_count ]] && [[ $chnl_index_end -gt $chnl_index_start ]] 
                then
                    ((chnl_index_start--))
                    for((i=chnl_index_start;i<chnl_index_end;i++));
                    do
                        chnls_pid_chosen+=("${chnls_pid[i]}")
                    done
                else
                    echo -e "$error 多选输入错误！" && echo
                    continue 2
                fi
            elif [[ $chnl_index == *[!0-9]* ]] || [[ $chnl_index -eq 0 ]] || [[ $chnl_index -gt $chnls_count ]] 
            then
                echo -e "$error 请输入正确的序号！" && echo
                continue 2
            else
                ((chnl_index--))
                chnls_pid_chosen+=("${chnls_pid[chnl_index]}")
            fi
        done
        break
    done
}

ViewChannelMenu(){
    ListChannels
    InputChannelsIndex
    for chnl_pid in "${chnls_pid_chosen[@]}"
    do
        GetChannelInfo
        ViewChannelInfo
    done
}

SetStreamLink()
{
    echo && echo "请输入直播源( mpegts / hls / flv ...)"
    echo -e "$tip hls 链接需包含 .m3u8 标识" && echo
    read -p "(默认: 取消):" stream_link
    [ -z "$stream_link" ] && echo "已取消..." && exit 1
    echo && echo -e "	直播源: $green $stream_link $plain" && echo
}

SetOutputDirName()
{
    echo "请输入频道输出目录名称"
    echo -e "$tip 是名称不是路径" && echo
    while read -p "(默认: 随机名称):" output_dir_name
    do
        if [ -z "$output_dir_name" ] 
        then
            while :;do
                output_dir_name=$(RandOutputDirName)
                if [[ -z $($JQ_FILE '.channels[] | select(.output_dir_name=="'"$output_dir_name"'")' "$CHANNELS_FILE") ]] 
                then
                    break 2
                fi
            done
        elif [[ -z $($JQ_FILE '.channels[] | select(.output_dir_name=="'"$output_dir_name"'")' "$CHANNELS_FILE") ]]  
        then
            break
        else
            echo && echo -e "$error 目录已存在！" && echo
        fi
    done
    output_dir_root="$LIVE_ROOT/$output_dir_name"
    echo && echo -e "	目录名称: $green $output_dir_name $plain" && echo
}

SetPlaylistName()
{
    echo "请输入m3u8名称(前缀)"
    read -p "(默认: $d_playlist_name_text):" playlist_name
    if [ -z "$playlist_name" ] 
    then
        playlist_name=${d_playlist_name:-$(RandPlaylistName)}
    fi
    echo && echo -e "	m3u8名称: $green $playlist_name $plain" && echo
}

SetSegDirName()
{
    echo "请输入段所在子目录名称"
    read -p "(默认: $d_seg_dir_name_text):" seg_dir_name
    if [ -z "$seg_dir_name" ] 
    then
        seg_dir_name=$d_seg_dir_name
    fi
    echo && echo -e "	段子目录名: $green ${seg_dir_name:-"不使用"} $plain" && echo
}

SetSegName()
{
    echo "请输入段名称"
    read -p "(默认: $d_seg_name_text):" seg_name
    if [ -z "$seg_name" ] 
    then
        if [ -z "$d_seg_name" ] 
        then
            if [ -z "${playlist_name:-}" ] 
            then
                playlist_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').playlist_name' "$CHANNELS_FILE")
            fi
            seg_name=$playlist_name
        else
            seg_name=$d_seg_name
        fi
    fi
    echo && echo -e "	段名称: $green $seg_name $plain" && echo 
}

SetSegLength()
{
    echo -e "请输入段的时长(单位：s)"
    while read -p "(默认: $d_seg_length):" seg_length
    do
        case "$seg_length" in
            "")
                seg_length=$d_seg_length
                break
            ;;
            *[!0-9]*)
                echo -e "$error 请输入正确的数字(大于0) "
            ;;
            *)
                if [ "$seg_length" -ge 1 ]; then
                    break
                else
                    echo -e "$error 请输入正确的数字(大于0)"
                fi
            ;;
        esac
    done
    echo && echo -e "	段时长: $green ${seg_length}s $plain" && echo
}

SetSegCount()
{
    echo "请输入m3u8文件包含的段数目，ffmpeg分割的数目是其2倍"
    echo -e "$tip 如果填0就是无限"
    while read -p "(默认: $d_seg_count):" seg_count
    do
        case "$seg_count" in
            "")
                seg_count=$d_seg_count
                break
            ;;
            *[!0-9]*)
                echo -e "$error 请输入正确的数字(大于等于0) "
            ;;
            *)
                if [ "$seg_count" -ge 0 ]; then
                    break
                else
                    echo -e "$error 请输入正确的数字(大于等于0)"
                fi
            ;;
        esac
    done
    echo && echo -e "	段数目: $green $seg_count $plain" && echo
}

SetVideoCodec()
{
    echo "请输入视频编码(不需要转码时输入 copy)"
    read -p "(默认: $d_video_codec):" video_codec
    video_codec=${video_codec:-$d_video_codec}
    echo && echo -e "	视频编码: $green $video_codec $plain" && echo
}

SetAudioCodec()
{
    echo "请输入音频编码(不需要转码时输入 copy)"
    read -p "(默认: $d_audio_codec):" audio_codec
    audio_codec=${audio_codec:-$d_audio_codec}
    echo && echo -e "	音频编码: $green $audio_codec $plain" && echo
}

SetQuality()
{
    echo -e "请输入输出视频质量"
    echo -e "$tip 改变CRF，数字越大越视频质量越差，如果设置CRF则无法用比特率控制视频质量"
    while read -p "(默认: $d_quality_text):" quality
    do
        case "$quality" in
            "")
                quality=$d_quality
                break
            ;;
            *[!0-9]*)
                echo -e "$error 请输入正确的数字(大于0,小于等于63)或直接回车 "
            ;;
            *)
                if [ "$quality" -gt 0 ] && [ "$quality" -lt 63 ]
                then
                    break
                else
                    echo -e "$error 请输入正确的数字(大于0,小于等于63)或直接回车 "
                fi
            ;;
        esac
    done
    echo && echo -e "	crf视频质量: $green ${quality:-"不设置"} $plain" && echo
}

SetBitrates()
{
    echo "请输入比特率(kb/s), 可以输入 omit 省略此选项"

    if [ -z "$quality" ] 
    then
        echo -e "$tip 用于指定输出视频比特率"
    else
        echo -e "$tip 用于 -maxrate 和 -bufsize"
    fi
    
    if [ -z "${kind:-}" ] 
    then
        echo -e "$tip 多个比特率用逗号分隔(生成自适应码流)
    同时可以指定输出的分辨率(比如：600-600x400,900-1280x720)"
    fi

    read -p "(默认: ${d_bitrates:-"不设置"}):" bitrates
    bitrates=${bitrates:-$d_bitrates}
    if [ "$bitrates" == "omit" ] 
    then
        bitrates=""
    fi
    echo && echo -e "	比特率: $green ${bitrates:-"不设置"} $plain" && echo
}

SetConst()
{
    echo "是否使用固定码率[y/N]"
    read -p "(默认: $d_const_text):" const_yn
    const_yn=${const_yn:-$d_const_text}
    if [[ "$const_yn" == [Yy] ]]
    then
        const="-C"
        const_yn="yes"
        const_text="是"
    else
        const=""
        const_yn="no"
        const_text="否"
    fi
    echo && echo -e "	固定码率: $green $const_text $plain" && echo 
}

SetEncrypt()
{
    echo "是否加密段[y/N]"
    read -p "(默认: $d_encrypt_text):" encrypt_yn
    encrypt_yn=${encrypt_yn:-$d_encrypt_text}
    if [[ "$encrypt_yn" == [Yy] ]]
    then
        encrypt="-e"
        encrypt_yn="yes"
        encrypt_text="是"
    else
        encrypt=""
        encrypt_yn="no"
        encrypt_text="否"
    fi
    echo && echo -e "	加密段: $green $encrypt_text $plain" && echo 
}

SetKeyName()
{
    echo "请输入key名称"
    read -p "(默认: $d_key_name_text):" key_name
    if [ -z "$key_name" ] 
    then
        if [ -z "$d_key_name" ] 
        then
            if [ -z "${playlist_name:-}" ] 
            then
                playlist_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').playlist_name' "$CHANNELS_FILE")
            fi
            key_name=$playlist_name
        else
            key_name=$d_key_name
        fi
    fi
    echo && echo -e "	key名称: $green $key_name $plain" && echo 
}

SetInputFlags()
{
    if [[ ${stream_link:-} == *".m3u8"* ]] 
    then
        d_input_flags=${d_input_flags//-reconnect_at_eof 1/}
    elif [ "${stream_link:0:4}" == "rtmp" ] 
    then
        d_input_flags=${d_input_flags//-timeout 2000000000/}
        d_input_flags=${d_input_flags//-reconnect 1/}
        d_input_flags=${d_input_flags//-reconnect_at_eof 1/}
        d_input_flags=${d_input_flags//-reconnect_streamed 1/}
        d_input_flags=${d_input_flags//-reconnect_delay_max 2000/}
        lead=${d_input_flags%%[^[:blank:]]*}
        d_input_flags=${d_input_flags#${lead}}
    fi
    echo "请输入input flags"
    read -p "(默认: $d_input_flags):" input_flags
    input_flags=${input_flags:-$d_input_flags}
    echo && echo -e "	input flags: $green $input_flags $plain" && echo 
}

SetOutputFlags()
{
    if [ -n "${kind:-}" ] 
    then
        d_output_flags=${d_output_flags//-sc_threshold 0/}
    fi
    echo "请输入output flags, 可以输入 omit 省略此选项"
    read -p "(默认: ${d_output_flags:-"不设置"}):" output_flags
    output_flags=${output_flags:-$d_output_flags}
    if [ "$output_flags" == "omit" ] 
    then
        output_flags=""
    fi
    echo && echo -e "	output flags: $green ${output_flags:-"不设置"} $plain" && echo 
}

SetVideoAudioShift()
{
    echo && echo -e "画面或声音延迟？
    ${green}1.$plain 设置 画面延迟
    ${green}2.$plain 设置 声音延迟
    ${green}3.$plain 不设置
    " && echo
    while read -p "(默认: $d_video_audio_shift_text):" video_audio_shift_num
    do
        case $video_audio_shift_num in
            "") 
                if [ -n "${d_video_shift:-}" ] 
                then
                    video_shift=$d_video_shift
                elif [ -n "${d_audio_shift:-}" ] 
                then
                    audio_shift=$d_audio_shift
                fi

                video_audio_shift=""
                video_audio_shift_text=$d_video_audio_shift_text
                break
            ;;
            1) 
                echo && echo "请输入延迟时间（比如 0.5）"
                read -p "(默认: 返回上级选项): " video_shift
                if [ -n "$video_shift" ] 
                then
                    video_audio_shift="v_$video_shift"
                    video_audio_shift_text="画面延迟 $video_shift 秒"
                    break
                else
                    echo
                fi
            ;;
            2) 
                echo && echo "请输入延迟时间（比如 0.5）"
                read -p "(默认: 返回上级选项): " audio_shift
                if [ -n "$audio_shift" ] 
                then
                    video_audio_shift="a_$audio_shift"
                    video_audio_shift_text="声音延迟 $audio_shift 秒"
                    break
                else
                    echo
                fi
            ;;
            3) 
                video_audio_shift_text="不设置"
                break
            ;;
            *) echo && echo -e "$error 请输入正确序号(1、2、3)或直接回车 " && echo
            ;;
        esac
    done

    echo && echo -e "	延迟: $green $video_audio_shift_text $plain" && echo 
}

SetChannelName()
{
    echo "请输入频道名称(可以是中文)"
    read -p "(默认: 跟m3u8名称相同):" channel_name
    if [ -z "${playlist_name:-}" ] 
    then
        playlist_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').playlist_name' "$CHANNELS_FILE")
    fi
    channel_name=${channel_name:-$playlist_name}
    echo && echo -e "	频道名称: $green $channel_name $plain" && echo
}

SetSyncPairs()
{
    echo "设置单独的 sync_pairs"
    read -p "(默认: $d_sync_pairs_text):" sync_pairs
    echo && echo -e "	单独的 sync_pairs: $green ${sync_pairs:-$d_sync_pairs_text} $plain" && echo
}

SetFlvPush()
{
    echo && echo "请输入推流地址(比如 rtmp://127.0.0.1/live/xxx )" && echo
    while read -p "(默认: 取消):" flv_push_link
    do
        [ -z "$flv_push_link" ] && echo "已取消..." && exit 1
        if [[ -z $($JQ_FILE '.channels[] | select(.flv_push_link=="'"$flv_push_link"'")' "$CHANNELS_FILE") ]]
        then
            break
        else
            echo -e "$error 推流地址已存在！请重新输入" && echo
        fi
    done
    echo && echo -e "	推流地址: $green $flv_push_link $plain" && echo
}

SetFlvPull()
{
    echo && echo "请输入拉流(播放)地址"
    echo -e "$tip 监控会验证此链接来确定是否重启频道，如果不确定可以先留空" && echo
    read -p "(默认: 不设置):" flv_pull_link
    echo && echo -e "	拉流地址: $green ${flv_pull_link:-"不设置"} $plain" && echo
}

FlvStreamCreatorWithShift()
{
    trap '' HUP INT QUIT TERM
    trap 'MonitorError $LINENO' ERR
    pid="$BASHPID"
    rand_pid=$pid
    while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$rand_pid"')' "$CHANNELS_FILE") ]] 
    do
        true &
        rand_pid=$!
        $JQ_FILE '(.channels[]|select(.pid=='"$pid"')|.pid)='"$rand_pid"'' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
        mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"
    done
    case $from in
        "AddChannel") 
            $JQ_FILE '.channels += [
                {
                    "pid":'"$pid"',
                    "status":"off",
                    "stream_link":"'"$stream_link"'",
                    "output_dir_name":"'"$output_dir_name"'",
                    "playlist_name":"'"$playlist_name"'",
                    "seg_dir_name":"'"$SEGMENT_DIRECTORY"'",
                    "seg_name":"'"$seg_name"'",
                    "seg_length":'"$seg_length"',
                    "seg_count":'"$seg_count"',
                    "video_codec":"'"$VIDEO_CODEC"'",
                    "audio_codec":"'"$AUDIO_CODEC"'",
                    "video_audio_shift":"'"$video_audio_shift"'",
                    "quality":"'"$quality"'",
                    "bitrates":"'"$bitrates"'",
                    "const":"'"$const_yn"'",
                    "encrypt":"'"$encrypt_yn"'",
                    "key_name":"'"$key_name"'",
                    "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                    "output_flags":"'"$FFMPEG_FLAGS"'",
                    "channel_name":"'"$channel_name"'",
                    "sync_pairs":"'"$sync_pairs"'",
                    "flv_status":"on",
                    "flv_push_link":"'"$flv_push_link"'",
                    "flv_pull_link":"'"$flv_pull_link"'"
                }
            ]' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
            mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"
            action="add"
            SyncFile

            if [ -n "$bitrates" ] 
            then
                bitrates=${bitrates%%,*}
                bitrates=${bitrates%%-*}
                bitrates_command="-b:v ${bitrates}k"
            else
                bitrates_command=""
            fi

            if [ -n "${video_shift:-}" ] 
            then
                map_command="-itsoffset $video_shift -i $stream_link -map 0:v -map 1:a"
            elif [ -n "${audio_shift:-}" ] 
            then
                map_command="-itsoffset $audio_shift -i $stream_link -map 0:a -map 1:v"
            else
                map_command=""
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command \
            -y -vcodec "$video_codec" -acodec "$audio_codec" $bitrates_command \
            $FFMPEG_FLAGS -f flv "$flv_push_link" || true

            $JQ_FILE '(.channels[]|select(.pid=='"$pid"')|.flv_status)="off"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
            mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"

            printf -v date_now "%(%m-%d %H:%M:%S)T"
            printf '%s\n' "$date_now $channel_name flv 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            kill -9 "$chnl_pid"
        ;;
        "StartChannel") 
            new_pid=$pid
            $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'|(.channels[]|select(.pid=='"$new_pid"')|.flv_status)="on"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
            mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"
            action="start"
            SyncFile

            if [ -n "$chnl_bitrates" ] 
            then
                bitrates=${chnl_bitrates%%,*}
                bitrates=${chnl_bitrates%%-*}
                bitrates_command="-b:v ${chnl_bitrates}k"
            else
                bitrates_command=""
            fi

            if [ -n "${chnl_video_shift:-}" ] 
            then
                map_command="-itsoffset $chnl_video_shift -i $chnl_stream_link -map 0:v -map 1:a"
            elif [ -n "${chnl_audio_shift:-}" ] 
            then
                map_command="-itsoffset $chnl_audio_shift -i $chnl_stream_link -map 0:a -map 1:v"
            else
                map_command=""
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$chnl_stream_link" $map_command \
            -y -vcodec "$chnl_video_codec" -acodec "$chnl_audio_codec" $bitrates_command \
            $FFMPEG_FLAGS -f flv "$chnl_flv_push_link" || true

            $JQ_FILE '(.channels[]|select(.pid=='"$new_pid"')|.flv_status)="off"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
            mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"

            printf -v date_now "%(%m-%d %H:%M:%S)T"
            printf '%s\n' "$date_now $chnl_channel_name flv 关闭" >> "$MONITOR_LOG"
            chnl_pid=$new_pid
            action="stop"
            SyncFile
            kill -9 "$chnl_pid"
        ;;
        "command") 
            $JQ_FILE '.channels += [
                {
                    "pid":'"$pid"',
                    "status":"off",
                    "stream_link":"'"$stream_link"'",
                    "output_dir_name":"'"$output_dir_name"'",
                    "playlist_name":"'"$playlist_name"'",
                    "seg_dir_name":"'"$SEGMENT_DIRECTORY"'",
                    "seg_name":"'"$seg_name"'",
                    "seg_length":'"$seg_length"',
                    "seg_count":'"$seg_count"',
                    "video_codec":"'"$VIDEO_CODEC"'",
                    "audio_codec":"'"$AUDIO_CODEC"'",
                    "video_audio_shift":"'"$video_audio_shift"'",
                    "quality":"'"$quality"'",
                    "bitrates":"'"$bitrates"'",
                    "const":"'"$const_yn"'",
                    "encrypt":"'"$encrypt_yn"'",
                    "key_name":"'"$key_name"'",
                    "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                    "output_flags":"'"$FFMPEG_FLAGS"'",
                    "channel_name":"'"$channel_name"'",
                    "sync_pairs":"",
                    "flv_status":"on",
                    "flv_push_link":"'"$flv_push_link"'",
                    "flv_pull_link":"'"$flv_pull_link"'"
                }
            ]' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
            mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"
            action="add"
            SyncFile

            if [ -n "${bitrates:-}" ] 
            then
                bitrates=${bitrates%%,*}
                bitrates=${bitrates%%-*}
                bitrates_command="-b:v ${bitrates}k"
            else
                bitrates_command=""
            fi

            if [ -n "${video_shift:-}" ] 
            then
                map_command="-itsoffset $video_shift -i $stream_link -map 0:v -map 1:a"
            elif [ -n "${audio_shift:-}" ] 
            then
                map_command="-itsoffset $audio_shift -i $stream_link -map 0:a -map 1:v"
            else
                map_command=""
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
            -vcodec "$video_codec" -acodec "$audio_codec" $bitrates_command \
            $FFMPEG_FLAGS -f flv "$flv_push_link" || true

            $JQ_FILE '(.channels[]|select(.pid=='"$pid"')|.flv_status)="off"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
            mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"

            printf -v date_now "%(%m-%d %H:%M:%S)T"
            printf '%s\n' "$date_now $channel_name flv 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            kill -9 "$chnl_pid"
        ;;
    esac
}

HlsStreamCreatorWithShift()
{
    trap '' HUP INT QUIT TERM
    trap 'MonitorError $LINENO' ERR
    pid="$BASHPID"
    rand_pid=$pid
    while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$rand_pid"')' "$CHANNELS_FILE") ]] 
    do
        true &
        rand_pid=$!
        $JQ_FILE '(.channels[]|select(.pid=='"$pid"')|.pid)='"$rand_pid"'' "$CHANNELS_FILE" > "${CHANNELS_TMP}_flv_shift"
        mv "${CHANNELS_TMP}_flv_shift" "$CHANNELS_FILE"
    done
    case $from in
        "AddChannel") 
            mkdir -p "$output_dir_root"
            $JQ_FILE '.channels += [
                {
                    "pid":'"$pid"',
                    "status":"on",
                    "stream_link":"'"$stream_link"'",
                    "output_dir_name":"'"$output_dir_name"'",
                    "playlist_name":"'"$playlist_name"'",
                    "seg_dir_name":"'"$SEGMENT_DIRECTORY"'",
                    "seg_name":"'"$seg_name"'",
                    "seg_length":'"$seg_length"',
                    "seg_count":'"$seg_count"',
                    "video_codec":"'"$VIDEO_CODEC"'",
                    "audio_codec":"'"$AUDIO_CODEC"'",
                    "video_audio_shift":"'"$video_audio_shift"'",
                    "quality":"'"$quality"'",
                    "bitrates":"'"$bitrates"'",
                    "const":"'"$const_yn"'",
                    "encrypt":"'"$encrypt_yn"'",
                    "key_name":"'"$key_name"'",
                    "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                    "output_flags":"'"$FFMPEG_FLAGS"'",
                    "channel_name":"'"$channel_name"'",
                    "sync_pairs":"'"$sync_pairs"'",
                    "flv_status":"off",
                    "flv_push_link":"",
                    "flv_pull_link":""
                }
            ]' "$CHANNELS_FILE" > "${CHANNELS_TMP}_shift"
            mv "${CHANNELS_TMP}_shift" "$CHANNELS_FILE"
            action="add"
            SyncFile

            if [ -n "$bitrates" ] 
            then
                bitrates=${bitrates%%,*}
                bitrates=${bitrates%%-*}
                bitrates_command="-b:v ${bitrates}k"
                output_name="${playlist_name}_${bitrates}_%05d.ts"
            else
                bitrates_command=""
                output_name="${playlist_name}_%05d.ts"
            fi

            if [ -n "${video_shift:-}" ] 
            then
                map_command="-itsoffset $video_shift -i $stream_link -map 0:v -map 1:a"
            elif [ -n "${audio_shift:-}" ] 
            then
                map_command="-itsoffset $audio_shift -i $stream_link -map 0:a -map 1:v"
            else
                map_command=""
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
            -vcodec "$video_codec" -acodec "$audio_codec" $bitrates_command \
            -threads 0 -flags -global_header -f segment -segment_list "$output_dir_root/$playlist_name.m3u8" \
            -segment_time "$seg_length" -segment_format mpeg_ts -segment_list_flags +live \
            -segment_list_size "$seg_count" -segment_wrap $((seg_count * 2)) $FFMPEG_FLAGS "$output_dir_root/$output_name" || true

            $JQ_FILE '(.channels[]|select(.pid=='"$pid"')|.status)="off"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_shift"
            mv "${CHANNELS_TMP}_shift" "$CHANNELS_FILE"
            rm -rf "$LIVE_ROOT/${output_dir_name:-'notfound'}"

            printf -v date_now "%(%m-%d %H:%M:%S)T"
            printf '%s\n' "$date_now $channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            kill -9 "$pid"
        ;;
        "StartChannel") 
            mkdir -p "$chnl_output_dir_root"
            new_pid=$pid
            $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'|(.channels[]|select(.pid=='"$new_pid"')|.status)="on"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_shift"
            mv "${CHANNELS_TMP}_shift" "$CHANNELS_FILE"
            action="start"
            SyncFile

            if [ -n "$chnl_bitrates" ] 
            then
                chnl_bitrates=${chnl_bitrates%%,*}
                chnl_bitrates=${chnl_bitrates%%-*}
                bitrates_command="-b:v ${chnl_bitrates}k"
                output_name="${chnl_playlist_name}_${chnl_bitrates}_%05d.ts"
            else
                bitrates_command=""
                output_name="${chnl_playlist_name}_%05d.ts"
            fi

            if [ -n "${chnl_video_shift:-}" ] 
            then
                map_command="-itsoffset $chnl_video_shift -i $chnl_stream_link -map 0:v -map 1:a"
            elif [ -n "${chnl_audio_shift:-}" ] 
            then
                map_command="-itsoffset $chnl_audio_shift -i $chnl_stream_link -map 0:a -map 1:v"
            else
                map_command=""
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$chnl_stream_link" $map_command -y \
            -vcodec "$chnl_video_codec" -acodec "$chnl_audio_codec" $bitrates_command \
            -threads 0 -flags -global_header -f segment -segment_list "$chnl_output_dir_root/$chnl_playlist_name.m3u8" \
            -segment_time "$chnl_seg_length" -segment_format mpeg_ts -segment_list_flags +live \
            -segment_list_size "$chnl_seg_count" -segment_wrap $((chnl_seg_count * 2)) $FFMPEG_FLAGS "$chnl_output_dir_root/$output_name" || true

            $JQ_FILE '(.channels[]|select(.pid=='"$new_pid"')|.status)="off"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_shift"
            mv "${CHANNELS_TMP}_shift" "$CHANNELS_FILE"
            rm -rf "$LIVE_ROOT/${chnl_output_dir_name:-'notfound'}"

            printf -v date_now "%(%m-%d %H:%M:%S)T"
            printf '%s\n' "$date_now $chnl_channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$new_pid
            action="stop"
            SyncFile
            kill -9 "$new_pid"
        ;;
        "command") 
            mkdir -p "$output_dir_root"
            $JQ_FILE '.channels += [
                {
                    "pid":'"$pid"',
                    "status":"on",
                    "stream_link":"'"$stream_link"'",
                    "output_dir_name":"'"$output_dir_name"'",
                    "playlist_name":"'"$playlist_name"'",
                    "seg_dir_name":"'"$SEGMENT_DIRECTORY"'",
                    "seg_name":"'"$seg_name"'",
                    "seg_length":'"$seg_length"',
                    "seg_count":'"$seg_count"',
                    "video_codec":"'"$VIDEO_CODEC"'",
                    "audio_codec":"'"$AUDIO_CODEC"'",
                    "video_audio_shift":"'"$video_audio_shift"'",
                    "quality":"'"$quality"'",
                    "bitrates":"'"$bitrates"'",
                    "const":"'"$const_yn"'",
                    "encrypt":"'"$encrypt_yn"'",
                    "key_name":"'"$key_name"'",
                    "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                    "output_flags":"'"$FFMPEG_FLAGS"'",
                    "channel_name":"'"$channel_name"'",
                    "sync_pairs":"",
                    "flv_status":"off",
                    "flv_push_link":"",
                    "flv_pull_link":""
                }
            ]' "$CHANNELS_FILE" > "${CHANNELS_TMP}_shift"
            mv "${CHANNELS_TMP}_shift" "$CHANNELS_FILE"
            action="add"
            SyncFile

            if [ -n "${bitrates:-}" ] 
            then
                bitrates=${bitrates%%,*}
                bitrates=${bitrates%%-*}
                bitrates_command="-b:v ${bitrates}k"
                output_name="${playlist_name}_${bitrates}_%05d.ts"
            else
                bitrates_command=""
                output_name="${playlist_name}_%05d.ts"
            fi
            
            if [ -n "${video_shift:-}" ] 
            then
                map_command="-itsoffset $video_shift -i $stream_link -map 0:v -map 1:a"
            elif [ -n "${audio_shift:-}" ] 
            then
                map_command="-itsoffset $audio_shift -i $stream_link -map 0:a -map 1:v"
            else
                map_command=""
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
            -vcodec "$video_codec" -acodec "$audio_codec" $bitrates_command \
            -threads 0 -flags -global_header -f segment -segment_list "$output_dir_root/$playlist_name.m3u8" \
            -segment_time "$seg_length" -segment_format mpeg_ts -segment_list_flags +live \
            -segment_list_size "$seg_count" -segment_wrap $((seg_count * 2)) $FFMPEG_FLAGS "$output_dir_root/$output_name" || true

            $JQ_FILE '(.channels[]|select(.pid=='"$pid"')|.status)="off"' "$CHANNELS_FILE" > "${CHANNELS_TMP}_shift"
            mv "${CHANNELS_TMP}_shift" "$CHANNELS_FILE"
            rm -rf "$LIVE_ROOT/${output_dir_name:-'notfound'}"

            printf -v date_now "%(%m-%d %H:%M:%S)T"
            printf '%s\n' "$date_now $channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            kill -9 "$pid"
        ;;
    esac
}

AddChannel()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    GetDefault
    SetStreamLink
    SetVideoCodec
    SetAudioCodec
    SetVideoAudioShift

    quality_command=""
    bitrates_command=""

    if [ -z "${kind:-}" ] && [ "$video_codec" == "copy" ] && [ "$video_codec" == "copy" ]
    then
        quality=""
        bitrates=""
        const=""
        const_yn="no"
        master=0
    else
        SetQuality
        
        if [ -n "$quality" ] 
        then
            quality_command="-q $quality"
        fi

        SetBitrates

        if [ -n "$bitrates" ] 
        then
            bitrates_command="-b $bitrates"
            master=1
        else
            master=0
        fi

        if [ -z "$quality" ] && [ -n "$bitrates" ] 
        then
            SetConst
        else
            const=""
            const_yn="no"
        fi
    fi

    if [ "${kind:-}" == "flv" ] 
    then
        SetFlvPush
        SetFlvPull
        output_dir_name=$(RandOutputDirName)
        playlist_name=$(RandPlaylistName)
        seg_dir_name=$d_seg_dir_name
        seg_name=$playlist_name
        seg_length=$d_seg_length
        seg_count=$d_seg_count
        encrypt=""
        encrypt_yn="no"
        key_name=$playlist_name
    else
        SetOutputDirName
        SetPlaylistName
        SetSegDirName
        SetSegName
        SetSegLength
        SetSegCount
        SetEncrypt
        if [ -n "$encrypt" ] 
        then
            SetKeyName
        else
            key_name=$playlist_name
        fi
    fi

    SetInputFlags
    SetOutputFlags
    SetChannelName
    if [ -n "$d_sync_file" ] && [ -n "$d_sync_index" ] && [ -n "$d_sync_pairs" ]
    then
        SetSyncPairs
    else
        sync_pairs=""
    fi

    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFMPEG="$FFMPEG_ROOT/ffmpeg"
    export FFMPEG
    AUDIO_CODEC=$audio_codec
    VIDEO_CODEC=$video_codec
    SEGMENT_DIRECTORY=$seg_dir_name
    if [[ ${input_flags:0:1} == "'" ]] 
    then
        input_flags=${input_flags%\'}
        input_flags=${input_flags#\'}
    fi
    if [[ ${output_flags:0:1} == "'" ]] 
    then
        output_flags=${output_flags%\'}
        output_flags=${output_flags#\'}
    fi
    export AUDIO_CODEC
    export VIDEO_CODEC
    export SEGMENT_DIRECTORY
    export FFMPEG_INPUT_FLAGS=$input_flags
    export FFMPEG_FLAGS=$output_flags

    if [ -n "${kind:-}" ] 
    then
        if [ "$kind" == "flv" ] 
        then
            from="AddChannel"
            ( FlvStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null & 
        else
            echo && echo -e "$error 暂不支持输出 $kind ..." && echo && exit 1
        fi
    elif [ -n "${video_audio_shift:-}" ] 
    then
        from="AddChannel"
        ( HlsStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null &
    else
        exec "$CREATOR_FILE" -l -i "$stream_link" -s "$seg_length" \
            -o "$output_dir_root" -c "$seg_count" $bitrates_command \
            -p "$playlist_name" -t "$seg_name" -K "$key_name" $quality_command \
            "$const" "$encrypt" &
        pid=$!

        while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$pid"')' "$CHANNELS_FILE") ]] 
        do
            kill -9 "$pid" >/dev/null 2>&1
            exec "$CREATOR_FILE" -l -i "$stream_link" -s "$seg_length" \
            -o "$output_dir_root" -c "$seg_count" $bitrates_command \
            -p "$playlist_name" -t "$seg_name" -K "$key_name" $quality_command \
            "$const" "$encrypt" &
            pid=$!
        done

        $JQ_FILE '.channels += [
            {
                "pid":'"$pid"',
                "status":"on",
                "stream_link":"'"$stream_link"'",
                "output_dir_name":"'"$output_dir_name"'",
                "playlist_name":"'"$playlist_name"'",
                "seg_dir_name":"'"$SEGMENT_DIRECTORY"'",
                "seg_name":"'"$seg_name"'",
                "seg_length":'"$seg_length"',
                "seg_count":'"$seg_count"',
                "video_codec":"'"$VIDEO_CODEC"'",
                "audio_codec":"'"$AUDIO_CODEC"'",
                "video_audio_shift":"",
                "quality":"'"$quality"'",
                "bitrates":"'"$bitrates"'",
                "const":"'"$const_yn"'",
                "encrypt":"'"$encrypt_yn"'",
                "key_name":"'"$key_name"'",
                "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                "output_flags":"'"$FFMPEG_FLAGS"'",
                "channel_name":"'"$channel_name"'",
                "sync_pairs":"'"$sync_pairs"'",
                "flv_status":"off",
                "flv_push_link":"",
                "flv_pull_link":""
            }
        ]' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        action="add"
        SyncFile
    fi

    echo && echo -e "$info 频道添加成功 !" && echo
}

EditStreamLink()
{
    SetStreamLink
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.stream_link)="'"$stream_link"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 直播源修改成功 !" && echo
}

EditOutputDirName()
{
    if [ "$chnl_status" == "on" ]
    then
        echo && echo -e "$error 检测到频道正在运行，是否现在关闭？[y/N]" && echo
        read -p "(默认: N):" stop_channel_yn
        stop_channel_yn=${stop_channel_yn:-'n'}
        if [[ "$stop_channel_yn" == [Yy] ]]
        then
            StopChannel
            echo && echo
        else
            echo "已取消..." && exit 1
        fi
    fi
    SetOutputDirName
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.output_dir_name)="'"$output_dir_name"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 输出目录名称修改成功 !" && echo
}

EditPlaylistName()
{
    SetPlaylistName
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.playlist_name)="'"$playlist_name"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info m3u8名称修改成功 !" && echo
}

EditSegDirName()
{
    SetSegDirName
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_dir_name)="'"$seg_dir_name"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 段所在子目录名称修改成功 !" && echo
}

EditSegName()
{
    SetSegName
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_name)="'"$seg_name"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 段名称修改成功 !" && echo
}

EditSegLength()
{
    SetSegLength
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_length)='"$seg_length"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 段时长修改成功 !" && echo
}

EditSegCount()
{
    SetSegCount
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_count)='"$seg_count"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 段数目修改成功 !" && echo
}

EditVideoCodec()
{
    SetVideoCodec
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.video_codec)="'"$video_codec"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 视频编码修改成功 !" && echo
}

EditAudioCodec()
{
    SetAudioCodec
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.audio_codec)="'"$audio_codec"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 音频编码修改成功 !" && echo
}

EditQuality()
{
    SetQuality
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.quality)="'"$quality"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info crf质量值修改成功 !" && echo
}

EditBitrates()
{
    SetBitrates
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.bitrates)="'"$bitrates"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 比特率修改成功 !" && echo
}

EditConst()
{
    SetConst
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.const)="'"$const"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 是否固定码率修改成功 !" && echo
}

EditEncrypt()
{
    SetEncrypt
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.encrypt)="'"$encrypt"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 是否加密修改成功 !" && echo
}

EditKeyName()
{
    SetKeyName
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.key_name)="'"$key_name"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info key名称修改成功 !" && echo
}

EditInputFlags()
{
    SetInputFlags
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.input_flags)="'"$input_flags"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info input flags修改成功 !" && echo
}

EditOutputFlags()
{
    SetOutputFlags
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.output_flags)="'"$output_flags"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info output flags修改成功 !" && echo
}

EditChannelName()
{
    SetChannelName
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.channel_name)="'"$channel_name"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 频道名称修改成功 !" && echo
}

EditSyncPairs()
{
    SetSyncPairs
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.sync_pairs)="'"$sync_pairs"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info sync_pairs 修改成功 !" && echo
}

EditChannelAll()
{
    if [ "$chnl_flv_status" == "on" ] 
    then
        kind="flv"
        echo && echo -e "$error 检测到频道正在运行，是否现在关闭？[y/N]" && echo
        read -p "(默认: N):" stop_channel_yn
        stop_channel_yn=${stop_channel_yn:-'n'}
        if [[ "$stop_channel_yn" == [Yy] ]]
        then
            StopChannel
            echo && echo
        else
            echo "已取消..." && exit 1
        fi
    elif [ "$chnl_status" == "on" ]
    then
        kind=""
        echo && echo -e "$error 检测到频道正在运行，是否现在关闭？[y/N]" && echo
        read -p "(默认: N):" stop_channel_yn
        stop_channel_yn=${stop_channel_yn:-'n'}
        if [[ "$stop_channel_yn" == [Yy] ]]
        then
            StopChannel
            echo && echo
        else
            echo "已取消..." && exit 1
        fi
    fi
    SetStreamLink
    SetOutputDirName
    SetPlaylistName
    SetSegDirName
    SetSegName
    SetSegLength
    SetSegCount
    SetVideoCodec
    SetAudioCodec
    SetVideoAudioShift
    if [ -z "${kind:-}" ] && [ "$video_codec" == "copy" ] && [ "$audio_codec" == "copy" ] 
    then
        quality=""
        bitrates=""
        const=""
        const_yn="no"
    else
        SetQuality
        SetBitrates

        if [ -z "$quality" ] && [ -n "$bitrates" ]
        then
            SetConst
        else
            const=""
            const_yn="no"
        fi
    fi

    SetEncrypt
    if [ -n "$encrypt" ] 
    then
        SetKeyName
    else
        key_name=$playlist_name
    fi
    SetInputFlags
    SetOutputFlags
    SetChannelName
    if [ -n "$d_sync_file" ] && [ -n "$d_sync_index" ] && [ -n "$d_sync_pairs" ]
    then
        SetSyncPairs
    else
        sync_pairs=""
    fi
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.stream_link)="'"$stream_link"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.seg_length)='"$seg_length"'|(.channels[]|select(.pid=='"$chnl_pid"')|.output_dir_name)="'"$output_dir_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.seg_count)='"$seg_count"'|(.channels[]|select(.pid=='"$chnl_pid"')|.video_codec)="'"$video_codec"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.audio_codec)="'"$audio_codec"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.bitrates)="'"$bitrates"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.playlist_name)="'"$playlist_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.channel_name)="'"$channel_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.seg_dir_name)="'"$seg_dir_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.seg_name)="'"$seg_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.const)="'"$const"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.quality)="'"$quality"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.encrypt)="'"$encrypt_yn"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.key_name)="'"$key_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.input_flags)="'"$input_flags"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.output_flags)="'"$output_flags"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 频道修改成功 !" && echo
}

EditForSecurity()
{
    SetPlaylistName
    SetSegName
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.playlist_name)="'"$playlist_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.seg_name)="'"$seg_name"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 段名称、m3u8名称 修改成功 !" && echo
}

EditChannelMenu()
{
    ListChannels
    InputChannelsIndex
    for chnl_pid in "${chnls_pid_chosen[@]}"
    do
        GetChannelInfo
        ViewChannelInfo
        echo && echo -e "你要修改什么？
    ${green}1.$plain 修改 直播源
    ${green}2.$plain 修改 输出目录名称
    ${green}3.$plain 修改 m3u8名称
    ${green}4.$plain 修改 段所在子目录名称
    ${green}5.$plain 修改 段名称
    ${green}6.$plain 修改 段时长
    ${green}7.$plain 修改 段数目
    ${green}8.$plain 修改 视频编码
    ${green}9.$plain 修改 音频编码
    ${green}10.$plain 修改 crf质量值
    ${green}11.$plain 修改 比特率
    ${green}12.$plain 修改 是否固定码率
    ${green}13.$plain 修改 是否加密
    ${green}14.$plain 修改 key名称
    ${green}15.$plain 修改 input flags
    ${green}16.$plain 修改 output flags
    ${green}17.$plain 修改 频道名称
    ${green}18.$plain 修改 sync pairs
    ${green}19.$plain 修改 全部配置
    ————— 组合[常用] —————
    ${green}20.$plain 修改 段名称、m3u8名称 (防盗链/DDoS)
    " && echo
        read -p "(默认: 取消):" edit_channel_num
        [ -z "$edit_channel_num" ] && echo "已取消..." && exit 1
        case $edit_channel_num in
            1)
                EditStreamLink
            ;;
            2)
                EditOutputDirName
            ;;
            3)
                EditPlaylistName
            ;;
            4)
                EditSegDirName
            ;;
            5)
                EditSegName
            ;;
            6)
                EditSegLength
            ;;
            7)
                EditSegCount
            ;;
            8)
                EditVideoCodec
            ;;
            9)
                EditAudioCodec
            ;;
            10)
                EditQuality
            ;;
            11)
                EditBitrates
            ;;
            12)
                EditConst
            ;;
            13)
                EditEncrypt
            ;;
            14)
                EditKeyName
            ;;
            15)
                EditInputFlags
            ;;
            16)
                EditOutputFlags
            ;;
            17)
                EditChannelName
            ;;
            18)
                EditSyncPairs
            ;;
            19)
                EditChannelAll
            ;;
            20)
                EditForSecurity
            ;;
            *)
                echo "请输入正确序号..." && exit 1
            ;;
        esac

        if [ "$chnl_status" == "on" ] || [ "$chnl_flv_status" == "on" ]
        then
            echo "是否重启此频道？[Y/n]"
            read -p "(默认: Y):" restart_yn
            restart_yn=${restart_yn:-"Y"}
            if [[ "$restart_yn" == [Yy] ]] 
            then
                StopChannel
                sleep 3
                GetChannelInfo
                StartChannel
                echo && echo -e "$info 频道重启成功 !" && echo
            else
                echo "不重启..."
            fi
        else
            echo "是否启动此频道？[y/N]"
            read -p "(默认: N):" start_yn
            start_yn=${start_yn:-"N"}
            if [[ "$start_yn" == [Yy] ]] 
            then
                GetChannelInfo
                StartChannel
                echo && echo -e "$info 频道启动成功 !" && echo
            else
                echo "不启动..."
            fi
        fi
    done
}

ToggleChannel()
{
    ListChannels
    InputChannelsIndex
    for chnl_pid in "${chnls_pid_chosen[@]}"
    do
        GetChannelInfo

        if [ "${kind:-}" == "flv" ] 
        then
            if [ "$chnl_flv_status" == "on" ] 
            then
                StopChannel
            else
                StartChannel
            fi
        elif [ "$chnl_status" == "on" ] 
        then
            StopChannel
        else
            StartChannel
        fi
    done
}

StartChannel()
{
    trap 'MonitorError $LINENO' ERR
    if [[ ${chnl_stream_link:-} == *".m3u8"* ]] 
    then
        chnl_input_flags=${chnl_input_flags//-reconnect_at_eof 1/}
    elif [ "${chnl_stream_link:0:4}" == "rtmp" ] 
    then
        chnl_input_flags=${chnl_input_flags//-timeout 2000000000/}
        chnl_input_flags=${chnl_input_flags//-reconnect 1/}
        chnl_input_flags=${chnl_input_flags//-reconnect_at_eof 1/}
        chnl_input_flags=${chnl_input_flags//-reconnect_streamed 1/}
        chnl_input_flags=${chnl_input_flags//-reconnect_delay_max 2000/}
        lead=${chnl_input_flags%%[^[:blank:]]*}
        chnl_input_flags=${chnl_input_flags#${lead}}
    fi
    chnl_quality_command=""
    chnl_bitrates_command=""

    if [ -z "${kind:-}" ] && [ "$chnl_video_codec" == "copy" ] && [ "$chnl_audio_codec" == "copy" ]
    then
        chnl_quality=""
        chnl_bitrates=""
        chnl_const=""
        master=0
    else
        if [ -n "$chnl_quality" ] 
        then
            chnl_const=""
            chnl_quality_command="-q $chnl_quality"
        fi

        if [ -n "$chnl_bitrates" ] 
        then
            chnl_bitrates_command="-b $chnl_bitrates"
            master=1
        else
            master=0
        fi
    fi

    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFMPEG="$FFMPEG_ROOT/ffmpeg"
    export FFMPEG
    AUDIO_CODEC=$chnl_audio_codec
    VIDEO_CODEC=$chnl_video_codec
    SEGMENT_DIRECTORY=$chnl_seg_dir_name
    if [[ ${chnl_input_flags:0:1} == "'" ]] 
    then
        chnl_input_flags=${chnl_input_flags%\'}
        chnl_input_flags=${chnl_input_flags#\'}
    fi
    if [[ ${chnl_output_flags:0:1} == "'" ]] 
    then
        chnl_output_flags=${chnl_output_flags%\'}
        chnl_output_flags=${chnl_output_flags#\'}
    fi
    export AUDIO_CODEC
    export VIDEO_CODEC
    export SEGMENT_DIRECTORY
    export FFMPEG_INPUT_FLAGS=$chnl_input_flags
    export FFMPEG_FLAGS=$chnl_output_flags

    if [ -n "${kind:-}" ] 
    then
        if [ "$chnl_status" == "on" ] 
        then
            echo && echo -e "$error HLS 频道正开启，走错片场了？" && echo && exit 1
        fi
        FFMPEG_FLAGS=${FFMPEG_FLAGS//-sc_threshold 0/}
        if [ "$kind" == "flv" ] 
        then
            from="StartChannel"
            ( FlvStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null &
        else
            echo && echo -e "$error 暂不支持输出 $kind ..." && echo && exit 1
        fi
    else
        if [ "$chnl_flv_status" == "on" ] 
        then
            echo && echo -e "$error FLV 频道正开启，走错片场了？" && echo && exit 1
        fi
        if [ -n "${chnl_video_audio_shift:-}" ] 
        then
            from="StartChannel"
            ( HlsStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null &
        elif [ -n "${monitor:-}" ] 
        then
            ( 
                trap '' HUP INT QUIT TERM
                exec "$CREATOR_FILE" -l -i "$chnl_stream_link" -s "$chnl_seg_length" \
                -o "$chnl_output_dir_root" -c "$chnl_seg_count" $chnl_bitrates_command \
                -p "$chnl_playlist_name" -t "$chnl_seg_name" -K "$chnl_key_name" $chnl_quality_command \
                "$chnl_const" "$chnl_encrypt" &
                new_pid=$!

                while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$new_pid"')' "$CHANNELS_FILE") ]] 
                do
                    kill -9 "$new_pid" >/dev/null 2>&1
                    exec "$CREATOR_FILE" -l -i "$chnl_stream_link" -s "$chnl_seg_length" \
                    -o "$chnl_output_dir_root" -c "$chnl_seg_count" $chnl_bitrates_command \
                    -p "$chnl_playlist_name" -t "$chnl_seg_name" -K "$chnl_key_name" $chnl_quality_command \
                    "$chnl_const" "$chnl_encrypt" &
                    new_pid=$!
                done

                $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'|(.channels[]|select(.pid=='"$new_pid"')|.status)="on"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
                mv "$CHANNELS_TMP" "$CHANNELS_FILE"
                action="start"
                SyncFile
            ) > /dev/null 2>/dev/null </dev/null
        else
            exec "$CREATOR_FILE" -l -i "$chnl_stream_link" -s "$chnl_seg_length" \
            -o "$chnl_output_dir_root" -c "$chnl_seg_count" $chnl_bitrates_command \
            -p "$chnl_playlist_name" -t "$chnl_seg_name" -K "$chnl_key_name" $chnl_quality_command \
            "$chnl_const" "$chnl_encrypt" &
            new_pid=$!

            while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$new_pid"')' "$CHANNELS_FILE") ]] 
            do
                kill -9 "$new_pid" >/dev/null 2>&1
                exec "$CREATOR_FILE" -l -i "$chnl_stream_link" -s "$chnl_seg_length" \
                -o "$chnl_output_dir_root" -c "$chnl_seg_count" $chnl_bitrates_command \
                -p "$chnl_playlist_name" -t "$chnl_seg_name" -K "$chnl_key_name" $chnl_quality_command \
                "$chnl_const" "$chnl_encrypt" &
                new_pid=$!
            done

            $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'|(.channels[]|select(.pid=='"$new_pid"')|.status)="on"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
            mv "$CHANNELS_TMP" "$CHANNELS_FILE"
            action="start"
            SyncFile
        fi
    fi

    echo && echo -e "$info 频道[ $chnl_channel_name ]已开启 !" && echo
}

StopChannel()
{
    trap 'MonitorError $LINENO' ERR
    if [ -n "${kind:-}" ]
    then
        if [ "$kind" != "flv" ] 
        then
            echo -e "$error 暂不支持 $kind ..." && echo && exit 1
        elif [ "$chnl_status" == "on" ]
        then
            echo -e "$error HLS 频道正开启，走错片场了？" && echo && exit 1
        fi
    elif [ "$chnl_flv_status" == "on" ]
    then
        echo -e "$error FLV 频道正开启，走错片场了？" && echo && exit 1
    fi

    stopped=0

    if kill -0 "$chnl_pid" 2> /dev/null 
    then
        while IFS= read -r ffmpeg_pid 
        do
            if [ -z "$ffmpeg_pid" ] 
            then
                if kill -9 "$chnl_pid" 2> /dev/null 
                then
                    echo && echo -e "$info 频道进程 $chnl_pid 已停止 !" && echo
                    stopped=1
                    break
                fi
            else
                while IFS= read -r real_ffmpeg_pid 
                do
                    if [ -z "$real_ffmpeg_pid" ] 
                    then
                        if kill -9 "$ffmpeg_pid" 2> /dev/null 
                        then
                            echo && echo -e "$info 频道进程 $chnl_pid 已停止 !" && echo
                            stopped=1
                            break 2
                        fi
                    elif kill -9 "$real_ffmpeg_pid" 2> /dev/null 
                    then
                        echo && echo -e "$info 频道进程 $chnl_pid 已停止 !" && echo
                        stopped=1
                        break 2
                    fi
                done <<< $(pgrep -P "$ffmpeg_pid")
            fi
        done <<< $(pgrep -P "$chnl_pid")
    else
        stopped=1
    fi

    if [ "$stopped" == 0 ] 
    then
        if [ -n "${monitor:-}" ]
        then
            return 0
        fi
        echo -e "$error 关闭频道进程 $chnl_pid 遇到错误，请重试 !" && echo && exit 1
    fi


    if [ "${kind:-}" == "flv" ] 
    then
        #$JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.flv_status)="off"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        #mv "$CHANNELS_TMP" "$CHANNELS_FILE" 2>/dev/null || true
        chnl_flv_status="off"
        echo && echo -e "$info 频道[ $chnl_channel_name ]已关闭 !" && echo
    elif [ -z "$chnl_video_audio_shift" ] 
    then
        chnl_status="off"
        $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.status)="off"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE" 2>/dev/null || true
        action=${action:-"stop"}
        SyncFile
        if [ ! -e "$LIVE_ROOT/${chnl_output_dir_name:-'notfound'}" ]
        then
            echo && echo -e "$error 频道[ $chnl_channel_name ]找不到应该删除的目录，请手动删除 !" && echo
        else
            rm -rf "$LIVE_ROOT/${chnl_output_dir_name:-'notfound'}"
            echo && echo -e "$info 频道[ $chnl_channel_name ]目录删除成功 !" && echo
        fi
    else
        chnl_status="off"
        echo && echo -e "$info 频道[ $chnl_channel_name ]已关闭 !" && echo
    fi
}

RestartChannel()
{
    ListChannels
    InputChannelsIndex
    for chnl_pid in "${chnls_pid_chosen[@]}"
    do
        GetChannelInfo
        if [ "${kind:-}" == "flv" ] 
        then
            if [ "$chnl_flv_status" == "on" ] 
            then
                action="skip"
                StopChannel
                sleep 3
            fi
        elif [ "$chnl_status" == "on" ] 
        then
            action="skip"
            StopChannel
            sleep 3
        fi
        StartChannel
        echo && echo -e "$info 频道重启成功 !" && echo
    done
}

DelChannel()
{
    ListChannels
    InputChannelsIndex
    for chnl_pid in "${chnls_pid_chosen[@]}"
    do
        GetChannelInfo
        if [ "${kind:-}" == "flv" ] 
        then
            if [ "$chnl_flv_status" == "on" ] 
            then
                StopChannel
            fi
        elif [ "$chnl_status" == "on" ] 
        then
            StopChannel
        fi
        $JQ_FILE '.channels -= [.channels[]|select(.pid=='"$chnl_pid"')]' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        echo -e "$info 频道删除成功 !" && echo
    done
}

RandStr()
{
    if [ -z ${1+x} ] 
    then
        str_size=8
    else
        str_size=$1
    fi
    str_array=(
        q w e r t y u i o p a s d f g h j k l z x c v b n m Q W E R T Y U I O P A S D
F G H J K L Z X C V B N M
    )
    str_array_size=${#str_array[*]}
    str_len=0
    rand_str=""
    while [[ $str_len -lt $str_size ]]
    do
        str_index=$((RANDOM%str_array_size))
        rand_str="$rand_str${str_array[str_index]}"
        str_len=$((str_len+1))
    done
    echo "$rand_str"
}

RandOutputDirName()
{
    while :;do
        output_dir_name=$(RandStr)
        if [[ -z $($JQ_FILE '.channels[] | select(.outputDirName=="'"$output_dir_name"'")' "$CHANNELS_FILE") ]]
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
        if [[ -z $($JQ_FILE '.channels[] | select(.playListName=="'"$playlist_name"'")' "$CHANNELS_FILE") ]]
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
        if [[ -z $($JQ_FILE '.channels[] | select(.segDirName=="'"$seg_dir_name"'")' "$CHANNELS_FILE") ]]
        then
            echo "$seg_dir_name"
            break
        fi
    done
}

# printf %s "$1" | jq -s -R -r @uri
urlencode() {
    local LANG=C i c e=''
    for ((i=0;i<${#1};i++)); do
        c=${1:$i:1}
        [[ "$c" =~ [a-zA-Z0-9\.\~\_\-] ]] || printf -v c '%%%02X' "'$c"
        e+="$c"
    done
    echo "$e"
}

generateScheduleNowtv()
{
    SCHEDULE_TMP_NOWTV="${SCHEDULE_JSON}_tmp"

    SCHEDULE_LINK_NOWTV="https://nowplayer.now.com/tvguide/epglist?channelIdList%5B%5D=$1&day=1"

    nowtv_schedule=$(curl --cookie "LANG=zh" -s "$SCHEDULE_LINK_NOWTV" || true)

    if [ -z "${nowtv_schedule:-}" ]
    then
        echo -e "\nNowTV empty: $chnl_nowtv_id\n"
        return 0
    else
        if [[ -z $($JQ_FILE '.' "$SCHEDULE_JSON") ]] 
        then
            printf '{"%s":[]}' "$chnl_nowtv_id" > "$SCHEDULE_JSON"
        fi

        $JQ_FILE '.'"$chnl_nowtv_id"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP_NOWTV"
        mv "$SCHEDULE_TMP_NOWTV" "$SCHEDULE_JSON"

        schedule=""
        while IFS= read -r program
        do
            title=${program#*title: }
            title=${title%, time:*}
            time=${program#*time: }
            time=${time%, sys_time:*}
            sys_time=${program#*sys_time: }
            sys_time=${sys_time:0:10}
            [ -n "$schedule" ] && schedule="$schedule,"
            schedule=$schedule'{
                "title":"'"${title}"'",
                "time":"'"${time}"'",
                "sys_time":"'"${sys_time}"'"
            }'
        done < <($JQ_FILE -r '.[0] | to_entries | map("title: \(.value.name), time: \(.value.startTime), sys_time: \(.value.start)") | .[]' <<< "$nowtv_schedule")

        schedule="[$schedule]"

        if [ -z "$schedule" ] 
        then
            echo -e "$error\nNowTV not found\n"
        else
            $JQ_FILE --arg index "$chnl_nowtv_id" --argjson program "$schedule" '.[$index] += $program' "$SCHEDULE_JSON" > "$SCHEDULE_TMP_NOWTV"
            mv "$SCHEDULE_TMP_NOWTV" "$SCHEDULE_JSON"
        fi
    fi
}

generateScheduleNiotv()
{
    printf -v date_now_niotv "%(%Y-%m-%d)T"
    SCHEDULE_LINK_NIOTV="http://www.niotv.com/i_index.php?cont=day"
    SCHEDULE_FILE_NIOTV="$IPTV_ROOT/${chnl_niotv_id}_niotv_schedule_$date_now_niotv"
    SCHEDULE_TMP_NIOTV="${SCHEDULE_JSON}_tmp"

    wget --post-data "act=select&day=$date_now_niotv&sch_id=$1" "$SCHEDULE_LINK_NIOTV" -qO "$SCHEDULE_FILE_NIOTV" || true
    #curl -d "day=$date_now_niotv&sch_id=$1" -X POST "$SCHEDULE_LINK_NIOTV" -so "$SCHEDULE_FILE_NIOTV" || true
    
    if [[ -z $($JQ_FILE '.' "$SCHEDULE_JSON") ]] 
    then
        printf '{"%s":[]}' "$chnl_niotv_id" > "$SCHEDULE_JSON"
    fi

    $JQ_FILE '.'"$chnl_niotv_id"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP_NIOTV"
    mv "$SCHEDULE_TMP_NIOTV" "$SCHEDULE_JSON"

    empty=1
    check=1
    while IFS= read -r line
    do
        if [[ $line == *"<td class=epg_tab_tm>"* ]] 
        then
            empty=0
            line=${line#*<td class=epg_tab_tm>}
            start_time=${line%%~*}
            end_time=${line#*~}
            end_time=${end_time%%</td>*}
        fi

        if [[ $line == *"</a></td>"* ]] 
        then
            line=${line%% </a></td>*}
            line=${line%%</a></td>*}
            title=${line#*target=_blank>}
            title=${title//\"/}
            title=${title//\'/}
            title=${title//\\/\'}
            sys_time=$(date -d "$date_now_niotv $start_time" +%s)

            start_time_num=$(date -d "$date_now_niotv $start_time" +%s)
            end_time_num=$(date -d "$date_now_niotv $end_time" +%s)

            if [ "$check" == 1 ] && [ "$start_time_num" -gt "$end_time_num" ] 
            then
                continue
            fi

            check=0

            $JQ_FILE '.'"$chnl_niotv_id"' += [
                {
                    "title":"'"${title}"'",
                    "time":"'"$start_time"'",
                    "sys_time":"'"$sys_time"'"
                }
            ]' "$SCHEDULE_JSON" > "$SCHEDULE_TMP_NIOTV"

            mv "$SCHEDULE_TMP_NIOTV" "$SCHEDULE_JSON"
        fi
    done < "$SCHEDULE_FILE_NIOTV"

    rm -rf "${SCHEDULE_FILE_NIOTV:-'notfound'}"

    if [ "$empty" == 1 ] 
    then
        echo -e "\nNioTV empty: $chnl_niotv_id\ntrying NowTV...\n"
        match_nowtv=0
        for chnl_nowtv in "${chnls_nowtv[@]}" ; do
            chnl_nowtv_id=${chnl_nowtv%%:*}
            if [ "$chnl_nowtv_id" == "$chnl_niotv_id" ] 
            then
                match_nowtv=1
                chnl_nowtv_num=${chnl_nowtv#*:}
                generateScheduleNowtv "$chnl_nowtv_num"
                break
            fi
        done
        [ "$match_nowtv" == 0 ] && echo -e "\nNowTV not found\n"
        return 0
    fi
}

generateSchedule()
{
    chnl_id=${1%%:*}
    chnl_name=${chnl#*:}
    chnl_name=${chnl_name// /-}
    chnl_name_encode=$(urlencode "$chnl_name")

    printf -v date_now "%(%Y-%m-%d)T"

    SCHEDULE_LINK="https://xn--i0yt6h0rn.tw/channel/$chnl_name_encode/index.json"
    SCHEDULE_FILE="$IPTV_ROOT/${chnl_id}_schedule_$date_now"
    SCHEDULE_TMP="${SCHEDULE_JSON}_tmp"

    wget --no-check-certificate "$SCHEDULE_LINK" -qO "$SCHEDULE_FILE" || true
    programs_count=$($JQ_FILE -r '.list[] | select(.key=="'"$date_now"'").values | length' "$SCHEDULE_FILE")
    
    if [[ $programs_count -eq 0 ]]
    then
        date_now=${date_now//-/\/}
        programs_count=$($JQ_FILE -r '.list[] | select(.key=="'"$date_now"'").values | length' "$SCHEDULE_FILE")
        if [[ $programs_count -eq 0 ]] 
        then
            echo -e "\n\nempty: $1\ntrying NioTV...\n"
            rm -rf "${SCHEDULE_FILE:-'notfound'}"
            match=0
            for chnl_niotv in "${chnls_niotv[@]}" ; do
                chnl_niotv_id=${chnl_niotv%%:*}
                if [ "$chnl_niotv_id" == "$chnl_id" ] 
                then
                    match=1
                    chnl_niotv_num=${chnl_niotv#*:}
                    generateScheduleNiotv "$chnl_niotv_num"
                fi
            done

            if [ "$match" == 0 ] 
            then
                echo -e "\nNioTV not found\ntrying NowTV...\n"
                for chnl_nowtv in "${chnls_nowtv[@]}" ; do
                    chnl_nowtv_id=${chnl_nowtv%%:*}
                    if [ "$chnl_nowtv_id" == "$chnl_id" ] 
                    then
                        match=1
                        chnl_nowtv_num=${chnl_nowtv#*:}
                        generateScheduleNowtv "$chnl_nowtv_num"
                        break
                    fi
                done
            fi

            [ "$match" == 0 ] && echo -e "\nNowTV not found\n"
            return 0
        fi
    fi

    programs_title=()
    while IFS='' read -r program_title
    do
        programs_title+=("$program_title");
    done < <($JQ_FILE -r '.list[] | select(.key=="'"$date_now"'").values | .[].name | @sh' "$SCHEDULE_FILE")

    IFS=" " read -ra programs_time < <($JQ_FILE -r '[.list[] | select(.key=="'"$date_now"'").values | .[].time] | @sh' "$SCHEDULE_FILE")

    if [[ -z $($JQ_FILE '.' "$SCHEDULE_JSON") ]] 
    then
        printf '{"%s":[]}' "$chnl_id" > "$SCHEDULE_JSON"
    fi

    $JQ_FILE '.'"$chnl_id"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"
    mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"

    rm -rf "${SCHEDULE_FILE:-'notfound'}"

    for((index = 0; index < programs_count; index++)); do
        programs_title_index=${programs_title[index]//\"/}
        programs_title_index=${programs_title_index//\'/}
        programs_title_index=${programs_title_index//\\/\'}
        programs_time_index=${programs_time[index]//\'/}
        programs_sys_time_index=$(date -d "$date_now $programs_time_index" +%s)

        $JQ_FILE '.'"$chnl_id"' += [
            {
                "title":"'"${programs_title_index}"'",
                "time":"'"$programs_time_index"'",
                "sys_time":"'"$programs_sys_time_index"'"
            }
        ]' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"

        mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"
    done
}

Schedule()
{
    CheckRelease
    GetDefault

    if [ -n "$d_schedule_file" ] 
    then
        SCHEDULE_JSON=$d_schedule_file
    else
        echo "请先设置 schedule_file 位置！" && exit 1
    fi

    chnls=( 
#        "hbogq:HBO HD"
#        "hbohits:HBO Hits"
#        "hbosignature:HBO Signature"
#        "hbofamily:HBO Family"
#        "foxmovies:FOX MOVIES"
#        "disney:Disney"
        "tvbfc:TVB 翡翠台"
        "tvbpearl:TVB Pearl"
        "tvbj2:TVB J2"
        "tvbwxxw:TVB 互動新聞台"
        "fhwszx:凤凰卫视资讯台"
        "fhwsxg:凤凰卫视香港台"
        "fhwszw:凤凰卫视中文台"
        "xgws:香港衛視綜合台"
        "foxfamily:福斯家庭電影台"
        "hlwdy:好萊塢電影"
        "xwdy:星衛HD電影台"
        "mydy:美亞電影台"
        "mycinemaeurope:My Cinema Europe HD我的歐洲電影台"
        "ymjs:影迷數位紀實台"
        "ymdy:影迷數位電影台"
        "hyyj:華藝影劇台"
        "catchplaydy:CatchPlay電影台"
        "ccyj:采昌影劇台"
        "lxdy:LS龍祥電影"
        "cinemax:Cinemax"
        "cinemaworld:CinemaWorld"
        "axn:AXN HD"
        "channelv:Channel V國際娛樂台HD"
        "dreamworks:DREAMWORKS"
        "nickasia:Nickelodeon Asia(尼克兒童頻道)"
        "cbeebies:CBeebies"
        "babytv:Baby TV"
        "boomerang:Boomerang"
        "mykids:MY-KIDS TV"
        "dwxq:動物星球頻道"
        "eltvshyy:ELTV生活英語台"
        "ifundm:i-Fun動漫台"
        "momoqz:momo親子台"
        "cnkt:CN卡通台"
        "ffxw:非凡新聞"
        "hycj:寰宇財經台"
        "hyzh:寰宇HD綜合台"
        "hyxw:寰宇新聞台"
        "hyxw2:寰宇新聞二台"
        "aedzh:愛爾達綜合台"
        "aedyj:愛爾達影劇台"
        "jtzx:靖天資訊台"
        "jtzh:靖天綜合台"
        "jtyl:靖天育樂台"
        "jtxj:靖天戲劇台"
        "jthl:Nice TV 靖天歡樂台"
        "jtyh:靖天映畫"
        "jtgj:KLT-靖天國際台"
        "jtrb:靖天日本台"
        "jtdy:靖天電影台"
        "jtkt:靖天卡通台"
        "jyxj:靖洋戲劇台"
        "jykt:靖洋卡通台Nice Bingo"
        "lhxj:龍華戲劇"
        "lhox:龍華偶像"
        "lhyj:龍華影劇"
        "lhdy:龍華電影"
        "lhjd:龍華經典"
        "lhyp:龍華洋片"
        "lhdh:龍華動畫"
        "wszw:衛視中文台"
        "wsdy:衛視電影台"
        "gxws:國興衛視"
        "gs:公視"
        "gs2:公視2台"
        "gs3:公視3台"
        "ts:台視"
        "tszh:台視綜合台"
        "tscj:台視財經台"
        "hs:華視"
        "hsjywh:華視教育文化"
        "zs:中視"
        "zsxw:中視新聞台"
        "zsjd:中視經典台"
        "sltw:三立台灣台"
        "sldh:三立都會台"
        "slzh:三立綜合台"
        "slxj:三立戲劇台"
        "bdzh:八大綜合"
        "bddy:八大第一"
        "bdxj:八大戲劇"
        "bdyl:八大娛樂"
        "gdyl:高點育樂"
        "gdzh:高點綜合"
        "ydsdy:壹電視電影台"
        "ydszxzh:壹電視資訊綜合台"
        "wlty:緯來體育台"
        "wlxj:緯來戲劇台"
        "wlrb:緯來日本台"
        "wldy:緯來電影台"
        "wlzh:緯來綜合台"
        "wlyl:緯來育樂台"
        "wljc:緯來精采台"
        "dszh:東森綜合台"
        "dsxj:東森戲劇台"
        "dsyy:東森幼幼台"
        "dsdy:東森電影台"
        "dsyp:東森洋片台"
        "dsxw:東森新聞台"
        "dscjxw:東森財經新聞台"
        "dscs:超級電視台"
        "ztxw:中天新聞台"
        "ztyl:中天娛樂台"
        "ztzh:中天綜合台"
        "msxq:美食星球頻道"
        "yzms:亞洲美食頻道"
        "yzly:亞洲旅遊台"
        "yzzh:亞洲綜合台"
        "yzxw:亞洲新聞台"
        "pltw:霹靂台灣"
        "titvyjm:原住民"
        "history:歷史頻道"
        "history2:HISTORY 2"
        "gjdlyr:國家地理高畫質悠人頻道"
        "gjdlys:國家地理高畫質野生頻道"
        "gjdlgq:國家地理高畫質頻道"
        "bbcearth:BBC Earth"
        "bbcworldnews:BBC World News"
        "bbclifestyle:BBC Lifestyle Channel"
        "wakawakajapan:WAKUWAKU JAPAN"
        "luxe:LUXE TV Channel"
        "bswx:博斯無限台"
        "bsgq1:博斯高球一台"
        "bsgq2:博斯高球二台"
        "bsml:博斯魅力網"
        "bswq:博斯網球台"
        "bsyd1:博斯運動一台"
        "bsyd2:博斯運動二台"
        "zlty:智林體育台"
        "eurosport:EUROSPORT"
        "fox:FOX頻道"
        "foxsports:FOX SPORTS"
        "foxsports2:FOX SPORTS 2"
        "foxsports3:FOX SPORTS 3"
        "elevensportsplus:ELEVEN SPORTS PLUS"
        "elevensports2:ELEVEN SPORTS 2"
        "discoveryasia:Discovery Asia"
        "discovery:Discovery"
        "discoverykx:Discovery科學頻道"
        "tracesportstars:TRACE Sport Stars"
        "dw:DW(Deutsch)"
        "lifetime:Lifetime"
        "foxcrime:FOXCRIME"
        "foxnews:FOX News Channel"
        "animax:Animax"
        "mtv:MTV綜合電視台"
        "ndmuch:年代MUCH"
        "ndxw:年代新聞"
        "nhk:NHK"
        "euronews:Euronews"
        "cnn:CNN International"
        "skynews:SKY NEWS HD"
        "nhkxwzx:NHK新聞資訊台"
        "jetzh:JET綜合"
        "tlclysh:旅遊生活"
        "z:Z頻道"
        "itvchoice:ITV Choice"
        "mdrb:曼迪日本台"
        "smartzs:Smart知識台"
        "tv5monde:TV5MONDE"
        "outdoor:Outdoor"
        "eentertainment:E! Entertainment"
        "davinci:DaVinCi Learning達文西頻道"
        "my101zh:MY101綜合台"
        "blueantextreme:BLUE ANT EXTREME"
        "blueantentertainmet:BLUE ANT EXTREME"
        "eyetvxj:EYE TV戲劇台"
        "eyetvly:EYE TV旅遊台"
        "travel:Travel Channel"
        "dmax:DMAX頻道"
        "hitshd:HITS"
        "fx:FX"
        "tvbs:TVBS"
        "tvbshl:TVBS歡樂"
        "tvbsjc:TVBS精采台"
        "tvbxh:TVB星河頻道"
        "tvn:tvN"
        "hgyl:韓國娛樂台KMTV"
        "xfkjjj:幸福空間居家台"
        "xwyl:星衛娛樂台"
        "amc:AMC"
        "animaxhd:Animax HD"
        "diva:Diva"
        "bloomberg:Bloomberg TV"
        "fgss:時尚頻道"
        "warner:Warner TV"
        "ettodayzh:ETtoday綜合台" )

    chnls_niotv=( 
        "hbogq:629"
        "hbohits:501"
        "hbosignature:503"
        "hbofamily:502"
        "foxmovies:47"
        "foxfamily:540"
        "disney:63"
        "dreamworks:758"
        "nickasia:705"
        "cbeebies:771"
        "babytv:553"
        "boomerang:766"
        "dwxq:61"
        "momoqz:148"
        "cnkt:65"
        "hyxw:695"
        "jtzx:709"
        "jtzh:710"
        "jtyl:202"
        "jtxj:721"
        "jthl:708"
        "jtyh:727"
        "jtrb:711"
        "jtkt:707"
        "jyxj:203"
        "jykt:706"
        "wszw:19"
        "wsdy:55"
        "gxws:73"
        "gs:17"
        "gs2:759"
        "gs3:177"
        "ts:11"
        "tszh:632"
        "tscj:633"
        "hs:15"
        "hsjywh:138"
        "zs:13"
        "zsxw:668"
        "zsjd:714"
        "sltw:34"
        "sldh:35"
        "bdzh:21"
        "bddy:33"
        "bdxj:22"
        "bdyl:60"
        "gdyl:170"
        "gdzh:143"
        "ydsdy:187"
        "ydszxzh:681"
        "wlty:66"
        "wlxj:29"
        "wlrb:72"
        "wldy:57"
        "wlzh:24"
        "wlyl:53"
        "wljc:546"
        "dszh:23"
        "dsxj:36"
        "dsyy:64"
        "dsdy:56"
        "dsyp:48"
        "dsxw:42"
        "dscjxw:43"
        "dscs:18"
        "ztxw:668"
        "ztyl:14"
        "ztzh:27"
        "yzly:778"
        "yzms:733"
        "yzxw:554"
        "pltw:26"
        "titvyjm:133"
        "history:549"
        "history2:198"
        "gjdlyr:670"
        "gjdlys:161"
        "gjdlgq:519"
        "discoveryasia:563"
        "discovery:58"
        "discoverykx:520"
        "bbcearth:698"
        "bbcworldnews:144"
        "bbclifestyle:646"
        "bswx:587"
        "bsgq1:529"
        "bsgq2:526"
        "bsml:588"
        "bsyd2:635"
        "bsyd1:527"
        "eurosport:581"
        "fox:70"
        "foxsports:67"
        "foxsports2:68"
        "foxsports3:547"
        "elevensportsplus:787"
        "elevensports2:770"
        "lifetime:199"
        "foxcrime:543"
        "cinemax:49"
        "hlwdy:52"
        "animax:84"
        "mtv:69"
        "ndmuch:25"
        "ndxw:40"
        "nhk:74"
        "euronews:591"
        "ffxw:79"
        "jetzh:71"
        "tlclysh:62"
        "axn:50"
        "z:75"
        "luxe:590"
        "catchplaydy:582"
        "tv5monde:574"
        "channelv:584"
        "davinci:669"
        "blueantextreme:779"
        "blueantentertainmet:785"
        "travel:684"
        "cnn:107"
        "dmax:521"
        "hitshd:692"
        "lxdy:141"
        "fx:544"
        "tvn:757"
        "hgyl:568"
        "xfkjjj:672"
        "nhkxwzx:773"
        "zlty:676"
        "xwdy:558"
        "xwyl:539"
        "mycinemaeurope:775"
        "amc:682"
        "animaxhd:772"
        "wakawakajapan:765"
        "tvbs:20"
        "tvbshl:32"
        "tvbsjc:774"
        "cinemaworld:559"
        "warner:688" )

    chnls_nowtv=( 
        "hbohits:111"
        "hbofamily:112"
        "cinemax:113"
        "hbosignature:114"
        "hbogq:115"
        "foxmovies:117"
        "foxfamily:120"
        "foxaction:118"
        "wsdy:139"
        "animaxhd:150"
        "tvn:155"
        "wszw:160"
        "discoveryasia:208"
        "discovery:209"
        "dwxq:210"
        "discoverykx:211"
        "dmax:212"
        "tlclysh:213"
        "gjdl:215"
        "gjdlys:216"
        "gjdlyr:217"
        "gjdlgq:218"
        "bbcearth:220"
        "history:223"
        "cnn:316"
        "foxnews:318"
        "bbcworldnews:320"
        "bloomberg:321"
        "yzxw:322"
        "skynews:323"
        "dw:324"
        "euronews:326"
        "nhk:328"
        "fhwszx:366"
        "fhwsxg:367"
        "xgws:368"
        "disney:441"
        "boomerang:445"
        "cbeebies:447"
        "babytv:448"
        "bbclifestyle:502"
        "eentertainment:506"
        "diva:508"
        "warner:510"
        "AXN:512"
        "blueantextreme:516"
        "blueantentertainmet:517"
        "fox:518"
        "foxcrime:523"
        "fx:524"
        "lifetime:525"
        "yzms:527"
        "channelv:534"
        "fhwszw:548"
        "zgzwws:556"
        "foxsports:670"
        "foxsports2:671"
        "foxsports3:672" )

    if [ -z ${2+x} ] 
    then
        count=0

        for chnl in "${chnls[@]}" ; do
            generateSchedule "$chnl"
            count=$((count + 1))
            echo -n $count
        done

        return
    fi

    case $2 in
        "hbo")
            printf -v date_now "%(%Y-%m-%d)T"

            chnls=(
                "hbo"
                "hbotw"
                "hbored"
                "cinemax"
                "hbohd"
                "hits"
                "signature"
                "family" )

            for chnl in "${chnls[@]}" ; do

                if [ "$chnl" == "hbo" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$date_now&channel=$chnl&feed=cn"
                elif [ "$chnl" == "hbotw" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$date_now&channel=hbo&feed=satellite"
                elif [ "$chnl" == "hbored" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$date_now&channel=red&feed=satellite"
                elif [ "$chnl" == "cinemax" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$date_now&channel=$chnl&feed=satellite"
                else
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-tw/ajax/home_schedule?date=$date_now&channel=$chnl&feed=satellite"
                fi
                
                SCHEDULE_FILE="$IPTV_ROOT/${chnl}_schedule_$date_now"
                SCHEDULE_TMP="${SCHEDULE_JSON}_tmp"
                wget --no-check-certificate "$SCHEDULE_LINK" -qO "$SCHEDULE_FILE"
                programs_count=$($JQ_FILE -r '. | length' "$SCHEDULE_FILE")

                programs_title=()
                while IFS='' read -r program_title
                do
                    programs_title+=("$program_title");
                done < <($JQ_FILE -r '.[].title | @sh' "$SCHEDULE_FILE")

                programs_title_local=()
                while IFS='' read -r program_title_local
                do
                    programs_title_local+=("$program_title_local");
                done < <($JQ_FILE -r '.[].title_local | @sh' "$SCHEDULE_FILE")

                IFS=" " read -ra programs_id < <($JQ_FILE -r '[.[].id] | @sh' "$SCHEDULE_FILE")
                IFS=" " read -ra programs_time < <($JQ_FILE -r '[.[].time] | @sh' "$SCHEDULE_FILE")
                IFS=" " read -ra programs_sys_time < <($JQ_FILE -r '[.[].sys_time] | @sh' "$SCHEDULE_FILE")

                if [[ -z $($JQ_FILE '.' "$SCHEDULE_JSON") ]] 
                then
                    printf '{"%s":[]}' "$chnl" > "$SCHEDULE_JSON"
                fi

                $JQ_FILE '.'"$chnl"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"
                mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"

                rm -rf "${SCHEDULE_FILE:-'notfound'}"

                for((index = 0; index < programs_count; index++)); do
                    programs_id_index=${programs_id[index]//\'/}
                    programs_title_index=${programs_title[index]//\"/}
                    programs_title_index=${programs_title_index//\'/}
                    programs_title_index=${programs_title_index//\\/\'}
                    programs_title_local_index=${programs_title_local[index]//\"/}
                    programs_title_local_index=${programs_title_local_index//\'/}
                    programs_title_local_index=${programs_title_local_index//\\/\'}
                    if [ -n "$programs_title_local_index" ] 
                    then
                        programs_title_index="$programs_title_local_index $programs_title_index"
                    fi
                    programs_time_index=${programs_time[index]//\'/}
                    programs_sys_time_index=${programs_sys_time[index]//\'/}

                    $JQ_FILE '.'"$chnl"' += [
                        {
                            "id":"'"${programs_id_index}"'",
                            "title":"'"${programs_title_index}"'",
                            "time":"'"$programs_time_index"'",
                            "sys_time":"'"$programs_sys_time_index"'"
                        }
                    ]' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"

                    mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"
                done
            done
        ;;
        "disney")
            printf -v date_now "%(%Y%m%d)T"
            SCHEDULE_LINK="https://disney.com.tw/_schedule/full/$date_now/8/%2Fepg"

            SCHEDULE_FILE="$IPTV_ROOT/$2_schedule_$date_now"
            SCHEDULE_TMP="${SCHEDULE_JSON}_tmp"
            wget --no-check-certificate "$SCHEDULE_LINK" -qO "$SCHEDULE_FILE"

            programs_title=()
            while IFS='' read -r program_title
            do
                programs_title+=("$program_title");
            done < <($JQ_FILE -r '.schedule[].schedule_items[].show_title | @sh' "$SCHEDULE_FILE")

            programs_count=${#programs_title[@]}

            IFS=" " read -ra programs_time < <($JQ_FILE -r '[.schedule[].schedule_items[].time] | @sh' "$SCHEDULE_FILE")
            IFS=" " read -ra programs_sys_time < <($JQ_FILE -r '[.schedule[].schedule_items[].iso8601_utc_time] | @sh' "$SCHEDULE_FILE")

            if [[ -z $($JQ_FILE '.' "$SCHEDULE_JSON") ]] 
            then
                printf '{"%s":[]}' "$2" > "$SCHEDULE_JSON"
            fi

            $JQ_FILE '.'"$2"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"
            mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"

            rm -rf "${SCHEDULE_FILE:-'notfound'}"

            for((index = 0; index < programs_count; index++)); do
                programs_title_index=${programs_title[index]//\"/}
                programs_title_index=${programs_title_index//\'/}
                programs_title_index=${programs_title_index//\\/\'}
                programs_time_index=${programs_time[index]//\'/}
                programs_sys_time_index=${programs_sys_time[index]//\'/}
                programs_sys_time_index=$(date -d "$programs_sys_time_index" +%s)

                $JQ_FILE '.'"$2"' += [
                    {
                        "title":"'"${programs_title_index}"'",
                        "time":"'"$programs_time_index"'",
                        "sys_time":"'"$programs_sys_time_index"'"
                    }
                ]' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"

                mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"
            done
        ;;
        "foxmovies")
            printf -v date_now "%(%Y-%-m-%-d)T"
            SCHEDULE_LINK="https://www.fng.tw/foxmovies/program.php?go=$date_now"

            SCHEDULE_FILE="$IPTV_ROOT/$2_schedule_$date_now"
            SCHEDULE_TMP="${SCHEDULE_JSON}_tmp"
            wget --no-check-certificate "$SCHEDULE_LINK" -qO "$SCHEDULE_FILE"

            if [[ -z $($JQ_FILE '.' "$SCHEDULE_JSON") ]] 
            then
                printf '{"%s":[]}' "$2" > "$SCHEDULE_JSON"
            fi

            $JQ_FILE '.'"$2"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"
            mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"

            while IFS= read -r line
            do
                if [[ $line == *"<td>"* ]] 
                then
                    line=${line#*<td>}
                    line=${line%%<\/td>*}

                    if [[ $line == *"<br>"* ]]  
                    then
                        line=${line%% <br>*}
                        line=${line//\"/}
                        line=${line//\'/}
                        line=${line//\\/\'}
                        sys_time=$(date -d "$date_now $time" +%s)
                        $JQ_FILE '.'"$2"' += [
                            {
                                "title":"'"${line}"'",
                                "time":"'"$time"'",
                                "sys_time":"'"$sys_time"'"
                            }
                        ]' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"

                        mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"
                    else
                        time=${line#* }
                    fi
                fi
            done < "$SCHEDULE_FILE"

            rm -rf "${SCHEDULE_FILE:-'notfound'}"
        ;;
        *) 
            found=0
            for chnl in "${chnls[@]}" ; do
                chnl_id=${chnl%%:*}
                if [ "$chnl_id" == "$2" ] 
                then
                    found=1
                    generateSchedule "$2"
                fi
            done

            if [ "$found" == 0 ] 
            then
                echo -e "\nnot found: $2\ntrying NioTV...\n"
                for chnl_niotv in "${chnls_niotv[@]}" ; do
                    chnl_niotv_id=${chnl_niotv%%:*}
                    if [ "$chnl_niotv_id" == "$2" ] 
                    then
                        found=1
                        chnl_niotv_num=${chnl_niotv#*:}
                        generateScheduleNiotv "$chnl_niotv_num"
                    fi
                done
            fi

            if [ "$found" == 0 ] 
            then
                echo -e "\nNioTV not found: $2\ntrying NowTV...\n"
                for chnl_nowtv in "${chnls_nowtv[@]}" ; do
                    chnl_nowtv_id=${chnl_nowtv%%:*}
                    if [ "$chnl_nowtv_id" == "$2" ] 
                    then
                        found=1
                        chnl_nowtv_num=${chnl_nowtv#*:}
                        generateScheduleNowtv "$chnl_nowtv_num"
                        break
                    fi
                done
            fi

            [ "$found" == 0 ] && echo "no support yet ~"
        ;;
    esac
}

TsIsUnique()
{
    not_unique=$(wget --no-check-certificate "${ts_array[unique_url]}?accounttype=${ts_array[acc_type_reg]}&username=$account" -qO- | $JQ_FILE '.ret')
    if [ "$not_unique" != 0 ] 
    then
        echo && echo -e "$error 用户名已存在,请重新输入！"
    fi
}

TsImg()
{
    IMG_FILE="$IPTV_ROOT/ts_yzm.jpg"
    if [ -n "${ts_array[refresh_token_url]:-}" ] 
    then
        str1=$(RandStr)
        str2=$(RandStr 4)
        str3=$(RandStr 4)
        str4=$(RandStr 4)
        str5=$(RandStr 12)
        deviceno="$str1-$str2-$str3-$str4-$str5"
        str6=$(printf '%s' "$deviceno" | md5sum)
        str6=${str6%% *}
        str6=${str6:7:1}
        deviceno="$deviceno$str6"
        declare -A token_array
        while IFS="=" read -r key value
        do
            token_array[$key]="$value"
        done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(curl -X POST -s --data '{"role":"guest","deviceno":"'"$deviceno"'","deviceType":"yuj"}' "${ts_array[token_url]}"))

        if [ "${token_array[ret]}" == 0 ] 
        then
            declare -A refresh_token_array
            while IFS="=" read -r key value
            do
                refresh_token_array[$key]="$value"
            done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(curl -X POST -s --data '{"accessToken":"'"${token_array[accessToken]}"'","refreshToken":"'"${token_array[refreshToken]}"'"}' "${ts_array[refresh_token_url]}"))

            if [ "${refresh_token_array[ret]}" == 0 ] 
            then
                declare -A img_array
                while IFS="=" read -r key value
                do
                    img_array[$key]="$value"
                done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(wget --no-check-certificate "${ts_array[img_url]}?accesstoken=${refresh_token_array[accessToken]}" -qO-))

                if [ "${img_array[ret]}" == 0 ] 
                then
                    picid=${img_array[picid]}
                    image=${img_array[image]}
                    refresh_img=0
                    base64 -d <<< "${image#*,}" > "$IMG_FILE"
                    imgcat --half-height "$IMG_FILE"
                    rm -rf "${IMG_FILE:-notfound}"
                    echo && echo -e "$info 输入图片验证码："
                    read -p "(默认: 刷新验证码):" pincode
                    [ -z "$pincode" ] && refresh_img=1
                    return 0
                fi
            fi
        fi
    else
        declare -A token_array
        while IFS="=" read -r key value
        do
            token_array[$key]="$value"
        done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(curl -X POST -s --data '{"usagescen":1}' "${ts_array[token_url]}"))

        if [ "${token_array[ret]}" == 0 ] 
        then
            declare -A img_array
            while IFS="=" read -r key value
            do
                img_array[$key]="$value"
            done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(wget --no-check-certificate "${ts_array[img_url]}?accesstoken=${token_array[access_token]}" -qO-))

            if [ "${img_array[ret]}" == 0 ] 
            then
                picid=${img_array[picid]}
                image=${img_array[image]}
                refresh_img=0
                base64 -d <<< "${image#*,}" > "$IMG_FILE"
                imgcat --half-height "$IMG_FILE"
                rm -rf "${IMG_FILE:-notfound}"
                echo && echo -e "$info 输入图片验证码："
                read -p "(默认: 刷新验证码):" pincode
                [ -z "$pincode" ] && refresh_img=1
                return 0
            fi
        fi
    fi
}

TsRegister()
{
    if [ ! -e "/usr/local/bin/imgcat" ] &&  [ -n "${ts_array[img_url]:-}" ]
    then
        echo -e "$error 请先安装 imgcat (https://github.com/eddieantonio/imgcat#build)" && exit 1
    fi
    not_unique=1
    while [ "$not_unique" != 0 ] 
    do
        echo && echo -e "$info 输入账号："
        read -p "(默认: 取消):" account
        [ -z "$account" ] && echo "已取消..." && exit 1
        if [ -z "${ts_array[unique_url]:-}" ] 
        then
            not_unique=0
        else
            TsIsUnique
        fi
    done

    echo && echo -e "$info 输入密码："
    read -p "(默认: 取消):" password
    [ -z "$password" ] && echo "已取消..." && exit 1

    if [ -n "${ts_array[img_url]:-}" ] 
    then
        refresh_img=1
        while [ "$refresh_img" != 0 ] 
        do
            TsImg
            [ "$refresh_img" == 1 ] && continue

            if [ -n "${ts_array[sms_url]:-}" ] 
            then
                declare -A sms_array
                while IFS="=" read -r key value
                do
                    sms_array[$key]="$value"
                done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(wget --no-check-certificate "${ts_array[sms_url]}?pincode=$pincode&picid=$picid&verifytype=3&account=$account&accounttype=1" -qO-))

                if [ "${sms_array[ret]}" == 0 ] 
                then
                    echo && echo -e "$info 短信已发送！"
                    echo && echo -e "$info 输入短信验证码："
                    read -p "(默认: 取消):" smscode
                    [ -z "$smscode" ] && echo "已取消..." && exit 1

                    declare -A verify_array
                    while IFS="=" read -r key value
                    do
                        verify_array[$key]="$value"
                    done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(wget --no-check-certificate "${ts_array[verify_url]}?verifycode=$smscode&verifytype=3&username=$account&account=$account" -qO-))

                    if [ "${verify_array[ret]}" == 0 ] 
                    then
                        str1=$(RandStr)
                        str2=$(RandStr 4)
                        str3=$(RandStr 4)
                        str4=$(RandStr 4)
                        str5=$(RandStr 12)
                        deviceno="$str1-$str2-$str3-$str4-$str5"
                        str6=$(printf '%s' "$deviceno" | md5sum)
                        str6=${str6%% *}
                        str6=${str6:7:1}
                        deviceno="$deviceno$str6"
                        devicetype="yuj"
                        md5_password=$(printf '%s' "$password" | md5sum)
                        md5_password=${md5_password%% *}
                        printf -v timestamp "%(%s)T"
                        timestamp=$((timestamp * 1000))
                        signature="$account|$md5_password|$deviceno|$devicetype|$timestamp"
                        signature=$(printf '%s' "$signature" | md5sum)
                        signature=${signature%% *}
                        declare -A reg_array
                        while IFS="=" read -r key value
                        do
                            reg_array[$key]="$value"
                        done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(curl -X POST -s --data '{"account":"'"$account"'","deviceno":"'"$deviceno"'","devicetype":"'"$devicetype"'","code":"'"${verify_array[code]}"'","signature":"'"$signature"'","birthday":"1970-1-1","username":"'"$account"'","type":1,"timestamp":"'"$timestamp"'","pwd":"'"$md5_password"'","accounttype":"'"${ts_array[acc_type_reg]}"'"}' "${ts_array[reg_url]}"))

                        if [ "${reg_array[ret]}" == 0 ] 
                        then
                            echo && echo -e "$info 注册成功！"
                            echo && echo -e "$info 是否登录账号? [y/N]" && echo
                            read -p "(默认: N):" login_yn
                            login_yn=${login_yn:-"N"}
                            if [[ "$login_yn" == [Yy] ]]
                            then
                                TsLogin
                            else
                                echo "已取消..." && exit 1
                            fi
                        else
                            echo && echo -e "$error 注册失败！"
                            printf '%s\n' "${reg_array[@]}"
                        fi
                    fi

                else
                    if [ -z "${ts_array[unique_url]:-}" ] 
                    then
                        echo && echo -e "$error 验证码或其它错误！请重新尝试！"
                    else
                        echo && echo -e "$error 验证码错误！"
                    fi
                    #printf '%s\n' "${sms_array[@]}"
                    refresh_img=1
                fi
            fi
        done
    else
        md5_password=$(printf '%s' "$password" | md5sum)
        md5_password=${md5_password%% *}
        declare -A reg_array
        while IFS="=" read -r key value
        do
            reg_array[$key]="$value"
        done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(wget --no-check-certificate "${ts_array[reg_url]}?username=$account&iconid=1&pwd=$md5_password&birthday=1970-1-1&type=1&accounttype=${ts_array[acc_type_reg]}" -qO-))

        if [ "${reg_array[ret]}" == 0 ] 
        then
            echo && echo -e "$info 注册成功！"
            echo && echo -e "$info 是否登录账号? [y/N]" && echo
            read -p "(默认: N):" login_yn
            login_yn=${login_yn:-"N"}
            if [[ "$login_yn" == [Yy] ]]
            then
                TsLogin
            else
                echo "已取消..." && exit 1
            fi
        else
            echo && echo -e "$error 发生错误"
            printf '%s\n' "${sms_array[@]}"
        fi
    fi
    
}

TsLogin()
{
    if [ -z "${account:-}" ] 
    then
        echo && echo -e "$info 输入账号："
        read -p "(默认: 取消):" account
        [ -z "$account" ] && echo "已取消..." && exit 1
    fi

    if [ -z "${password:-}" ] 
    then
        echo && echo -e "$info 输入密码："
        read -p "(默认: 取消):" password
        [ -z "$password" ] && echo "已取消..." && exit 1
    fi

    str1=$(RandStr)
    str2=$(RandStr 4)
    str3=$(RandStr 4)
    str4=$(RandStr 4)
    str5=$(RandStr 12)
    deviceno="$str1-$str2-$str3-$str4-$str5"
    str6=$(printf '%s' "$deviceno" | md5sum)
    str6=${str6%% *}
    str6=${str6:7:1}
    deviceno="$deviceno$str6"
    md5_password=$(printf '%s' "$password" | md5sum)
    md5_password=${md5_password%% *}

    if [ -z "${ts_array[img_url]:-}" ] 
    then
        TOKEN_LINK="${ts_array[login_url]}?deviceno=$deviceno&devicetype=3&accounttype=${ts_array[acc_type_login]:-2}&accesstoken=(null)&account=$account&pwd=$md5_password&isforce=1&businessplatform=1"
        token=$(wget --no-check-certificate "$TOKEN_LINK" -qO-)
    else
        printf -v timestamp "%(%s)T"
        timestamp=$((timestamp * 1000))
        signature="$deviceno|yuj|${ts_array[acc_type_login]}|$account|$timestamp"
        signature=$(printf '%s' "$signature" | md5sum)
        signature=${signature%% *}
        if [[ ${ts_array[extend_info]} == "{"*"}" ]] 
        then
            token=$(curl -X POST -s --data '{"account":"'"$account"'","deviceno":"'"$deviceno"'","pwd":"'"$md5_password"'","devicetype":"yuj","businessplatform":1,"signature":"'"$signature"'","isforce":1,"extendinfo":'"${ts_array[extend_info]}"',"timestamp":"'"$timestamp"'","accounttype":'"${ts_array[acc_type_login]}"'}' "${ts_array[login_url]}")
        else
            token=$(curl -X POST -s --data '{"account":"'"$account"'","deviceno":"'"$deviceno"'","pwd":"'"$md5_password"'","devicetype":"yuj","businessplatform":1,"signature":"'"$signature"'","isforce":1,"extendinfo":"'"${ts_array[extend_info]}"'","timestamp":"'"$timestamp"'","accounttype":'"${ts_array[acc_type_login]}"'}' "${ts_array[login_url]}")
        fi
    fi

    declare -A login_array
    while IFS="=" read -r key value
    do
        login_array[$key]="$value"
    done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< "$token")

    if [ -z "${login_array[access_token]:-}" ] 
    then
        echo -e "$error 账号错误"
        printf '%s\n' "${login_array[@]}"
        echo && echo -e "$info 是否注册账号? [y/N]" && echo
        read -p "(默认: N):" register_yn
        register_yn=${register_yn:-"N"}
        if [[ "$register_yn" == [Yy] ]]
        then
            TsRegister
        else
            echo "已取消..." && exit 1
        fi
    else
        while :; do
            echo && echo -e "$info 输入需要转换的频道号码："
            read -p "(默认: 取消):" programid
            [ -z "$programid" ] && echo "已取消..." && exit 1
            [[ $programid =~ ^[0-9]{10}$ ]] || { echo -e "$error频道号码错误！"; continue; }
            break
        done

        if [ -n "${ts_array[auth_info_url]:-}" ] 
        then
            declare -A auth_info_array
            while IFS="=" read -r key value
            do
                auth_info_array[$key]="$value"
            done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(wget --no-check-certificate "${ts_array[auth_info_url]}?accesstoken=${login_array[access_token]}&programid=$programid&playtype=live&protocol=hls&verifycode=${login_array[device_id]}" -qO-))

            if [ "${auth_info_array[ret]}" == 0 ] 
            then
                authtoken="ipanel123#%#&*(&(*#*&^*@#&*%()#*()$)#@&%(*@#()*%321ipanel${auth_info_array[auth_random_sn]}"
                authtoken=$(printf '%s' "$authtoken" | md5sum)
                authtoken=${authtoken%% *}
                playtoken=${auth_info_array[play_token]}

                declare -A auth_verify_array
                while IFS="=" read -r key value
                do
                    auth_verify_array[$key]="$value"
                done < <($JQ_FILE -r 'to_entries | map("\(.key)=\(.value)") | .[]' <<< $(wget --no-check-certificate "${ts_array[auth_verify_url]}?programid=$programid&playtype=live&protocol=hls&accesstoken=${login_array[access_token]}&verifycode=${login_array[device_id]}&authtoken=$authtoken" -qO-))

                if [ "${auth_verify_array[ret]}" == 0 ] 
                then
                    TS_LINK="${ts_array[play_url]}?playtype=live&protocol=ts&accesstoken=${login_array[access_token]}&playtoken=$playtoken&verifycode=${login_array[device_id]}&rate=org&programid=$programid"
                else
                    echo && echo -e "$error 发生错误"
                    printf '%s\n' "${auth_verify_array[@]}"
                    exit 1
                fi
            else
                echo && echo -e "$error 发生错误"
                printf '%s\n' "${auth_info_array[@]}"
                exit 1
            fi
        else
            TS_LINK="${ts_array[play_url]}?playtype=live&protocol=ts&accesstoken=${login_array[access_token]}&playtoken=ABCDEFGH&verifycode=${login_array[device_id]}&rate=org&programid=$programid"
        fi

        echo && echo -e "$info ts链接：\n$TS_LINK"

        stream_link=$($JQ_FILE -r --arg a "programid=$programid" '[.channels[].stream_link] | map(select(test($a)))[0]' "$CHANNELS_FILE")
        if [ "${stream_link:-}" != null ]
        then
            echo && echo -e "$info 检测到此频道原有链接，是否替换成新的ts链接? [Y/n]"
            read -p "(默认: Y):" change_yn
            change_yn=${change_yn:-"Y"}
            if [[ "$change_yn" == [Yy] ]]
            then
                $JQ_FILE '(.channels[]|select(.stream_link=="'"$stream_link"'")|.stream_link)="'"$TS_LINK"'"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
                mv "$CHANNELS_TMP" "$CHANNELS_FILE"
                echo && echo -e "$info 修改成功 !" && echo
            else
                echo "已取消..." && exit 1
            fi
        fi
    fi
}

TsMenu()
{
    GetDefault

    if [ -n "$d_sync_file" ] 
    then
        local_channels=$($JQ_FILE -r '.data[] | select(.reg_url != null)' "$d_sync_file")
    fi

    echo && echo -e "$info 是否使用默认频道文件? 默认链接: $DEFAULT_CHANNELS_LINK [Y/n]" && echo
    read -p "(默认: Y):" use_default_channels_yn
    use_default_channels_yn=${use_default_channels_yn:-"Y"}
    if [[ "$use_default_channels_yn" == [Yy] ]]
    then
        TS_CHANNELS_LINK=$DEFAULT_CHANNELS_LINK
    else
        if [ -n "$local_channels" ] 
        then
            echo && echo -e "$info 是否使用本地频道文件? 本地路径: $d_sync_file [Y/n]" && echo
            read -p "(默认: Y):" use_local_channels_yn
            use_local_channels_yn=${use_local_channels_yn:-"Y"}
            if [[ "$use_local_channels_yn" == [Yy] ]] 
            then
                TS_CHANNELS_FILE=$d_sync_file
            fi
        fi
        if [ -z "${TS_CHANNELS_FILE:-}" ]
        then
            echo && echo -e "$info 请输入使用的频道文件链接或本地路径: " && echo
            read -p "(默认: 取消):" TS_CHANNELS_LINK_OR_FILE
            [ -z "$TS_CHANNELS_LINK_OR_FILE" ] && echo "已取消..." && exit 1
            if [ "${TS_CHANNELS_LINK_OR_FILE:0:4}" == "http" ] 
            then
                TS_CHANNELS_LINK=$TS_CHANNELS_LINK_OR_FILE
            else
                [ ! -e "$TS_CHANNELS_LINK_OR_FILE" ] && echo "文件不存在，已取消..." && exit 1
                TS_CHANNELS_FILE=$TS_CHANNELS_LINK_OR_FILE
            fi
        fi
    fi

    if [ -z "${TS_CHANNELS_LINK:-}" ] 
    then
        ts_channels=$(< "$TS_CHANNELS_FILE")
    else
        ts_channels=$(wget --no-check-certificate "$TS_CHANNELS_LINK" -qO-)

        [ -z "$ts_channels" ] && echo && echo -e "$error无法连接文件地址，已取消..." && exit 1
    fi

    ts_channels_desc=()
    while IFS='' read -r desc 
    do
        ts_channels_desc+=("$desc")
    done < <($JQ_FILE -r '.data[] | select(.reg_url != null) | .desc | @sh' <<< "$ts_channels")
    
    count=${#ts_channels_desc[@]}

    echo && echo -e "$info 选择需要操作的直播源"
    for((i=0;i<count;i++));
    do
        desc=${ts_channels_desc[i]//\"/}
        desc=${desc//\'/}
        desc=${desc//\\/\'}
        echo -e "${green}$((i+1)).$plain ${desc}"
    done
    
    while :; do
        read -p "(默认: 取消):" channel_id
        [ -z "$channel_id" ] && echo "已取消..." && exit 1
        [[ $channel_id =~ ^[0-9]+$ ]] || { echo -e "$error请输入序号！"; continue; }
        if ((channel_id >= 1 && channel_id <= count)); then
            ((channel_id--))
            declare -A ts_array
            while IFS="=" read -r key value
            do
                ts_array[$key]="$value"
            done < <($JQ_FILE -r '[.data[] | select(.reg_url != null)]['"$channel_id"'] | to_entries | map("\(.key)=\(.value)") | .[]' <<< "$ts_channels")

            if [ "${ts_array[name]}" == "jxtvnet" ] && ! nc -z "access.jxtvnet.tv" 81 2>/dev/null
            then
                echo && echo -e "$info 部分服务器无法连接此直播源，但可以将ip写入 /etc/hosts 来连接，请选择线路
  ${green}1.$plain 电信
  ${green}2.$plain 联通"
                read -p "(默认: 取消):" jxtvnet_lane
                case $jxtvnet_lane in
                    1) 
                        printf '%s\n' "59.63.205.33 access.jxtvnet.tv" >> "/etc/hosts"
                        printf '%s\n' "59.63.205.33 stream.slave.jxtvnet.tv" >> "/etc/hosts"
                        printf '%s\n' "59.63.205.33 slave.jxtvnet.tv" >> "/etc/hosts"
                    ;;
                    2) 
                        printf '%s\n' "110.52.240.146 access.jxtvnet.tv" >> "/etc/hosts"
                        printf '%s\n' "110.52.240.146 stream.slave.jxtvnet.tv" >> "/etc/hosts"
                        printf '%s\n' "110.52.240.146 slave.jxtvnet.tv" >> "/etc/hosts"
                    ;;
                    *) echo "已取消..." && exit 1
                    ;;
                esac
            fi

            echo && echo -e "$info 选择操作
  ${green}1.$plain 登录以获取ts链接
  ${green}2.$plain 注册账号"
            read -p "(默认: 取消):" channel_act
            [ -z "$channel_act" ] && echo "已取消..." && exit 1
            
            case $channel_act in
                1) TsLogin
                ;;
                2) TsRegister
                ;;
                *) echo "已取消..." && exit 1
                ;;
            esac
            
            break
        else
            echo -e "$error序号错误，请重新输入！"
        fi
    done
    
}

AntiDDoS()
{
    trap '' HUP INT TERM QUIT EXIT
    trap 'MonitorError $LINENO' ERR
    printf '%s' "$BASHPID" > "$IP_PID"

    ips=()
    jail_time=()

    if [ -s "$IP_DENY" ]  
    then
        while IFS= read -r line
        do
            if [[ "$line" == *:* ]] 
            then
                ip=${line%:*}
                jail=${line#*:}
                ips+=("$ip")
                jail_time+=("$jail")
            else
                ip=$line
                ufw delete deny from "$ip" to any port "$anti_ddos_port" > /dev/null 2>> "$IP_LOG"
            fi
        done < "$IP_DENY"

        if [ -n "${ips:-}" ] 
        then
            new_ips=()
            new_jail_time=()
            printf -v now "%(%s)T"

            update=0
            for((i=0;i<${#ips[@]};i++));
            do
                if [ "$now" -gt "${jail_time[i]}" ] 
                then
                    ufw delete deny from "${ips[i]}" to any port "$anti_ddos_port" > /dev/null 2>> "$IP_LOG"
                    update=1
                else
                    new_ips+=("${ips[i]}")
                    new_jail_time+=("${jail_time[i]}")
                fi
            done

            if [ "$update" == 1 ] 
            then
                ips=("${new_ips[@]}")
                jail_time=("${new_jail_time[@]}")

                printf "" > "$IP_DENY"

                for((i=0;i<${#ips[@]};i++));
                do
                    printf '%s\n' "${ips[i]}:${jail_time[i]}" >> "$IP_DENY"
                done
            fi
        else
            printf "" > "$IP_DENY"
        fi
    fi

    echo && echo -e "$info AntiDDoS 启动成功 !"
    printf '%s\n' "$date_now AntiDDoS 启动成功 PID $BASHPID !" >> "$MONITOR_LOG"
    
    while true; do
        chnls_count=0
        chnls_output_dir_name=()
        chnls_seg_length=()
        chnls_seg_count=()
        while IFS= read -r channel
        do
            chnls_count=$((chnls_count+1))
            map_output_dir_name=${channel#*output_dir_name: }
            map_output_dir_name=${map_output_dir_name%, seg_length:*}
            map_seg_length=${channel#*seg_length: }
            map_seg_length=${map_seg_length%, seg_count:*}
            map_seg_count=${channel#*seg_count: }

            chnls_output_dir_name+=("$map_output_dir_name");
            chnls_seg_length+=("$map_seg_length");
            chnls_seg_count+=("$map_seg_count");
        done < <($JQ_FILE -r '.channels | to_entries | map("output_dir_name: \(.value.output_dir_name), seg_length: \(.value.seg_length), seg_count: \(.value.seg_count)") | .[]' "$CHANNELS_FILE")

        output_dir_names=()
        triggers=()
        for output_dir_root in "$LIVE_ROOT"/*
        do
            output_dir_name=${output_dir_root#*$LIVE_ROOT/}

            for((i=0;i<chnls_count;i++));
            do
                if [ "$output_dir_name" == "${chnls_output_dir_name[i]}" ] 
                then
                    chnl_seg_count=${chnls_seg_count[i]}
                    if [ "$chnl_seg_count" != 0 ] 
                    then
                        chnl_seg_length=${chnls_seg_length[i]}
                        trigger=$(( 60 * anti_ddos_level / (chnl_seg_length * chnl_seg_count) ))
                        if [ "$trigger" == 0 ] 
                        then
                            trigger=1
                        fi
                        output_dir_names+=("$output_dir_name")
                        triggers+=("$trigger")
                    fi
                fi
            done
        done
        
        printf -v now "%(%s)T"
        jail=$((now + anti_ddos_seconds))

        while IFS=' ' read -r counts ip file
        do
            if [[ "$file" == *".ts" ]] 
            then
                seg_name=${file##*/}
                file=${file%/*}
                dir_name=${file##*/}
                file=${file%/*}
                to_ban=0

                if [ -e "$LIVE_ROOT/$dir_name/$seg_name" ] 
                then
                    output_dir_name=$dir_name
                    to_ban=1
                elif [ -e "$LIVE_ROOT/${file##*/}/$dir_name/$seg_name" ] 
                then
                    output_dir_name=${file##*/}
                    to_ban=1
                fi

                for banned_ip in "${ips[@]}"
                do
                    if [ "$banned_ip" == "$ip" ] 
                    then
                        to_ban=0
                    fi
                done

                if [ "$to_ban" == 1 ] 
                then
                    for((i=0;i<${#output_dir_names[@]};i++));
                    do
                        if [ "${output_dir_names[i]}" == "$output_dir_name" ] && [ "$counts" -gt "${triggers[i]}" ]
                        then
                            jail_time+=("$jail")
                            printf '%s\n' "$ip:$jail" >> "$IP_DENY"
                            ufw insert 1 deny from "$ip" to any port "$anti_ddos_port" > /dev/null 2>> "$IP_LOG"
                            printf -v date_now "%(%m-%d %H:%M:%S)T"
                            printf '%s\n' "$date_now $ip 已被禁" >> "$IP_LOG"
                            ips+=("$ip")
                            break 1
                        fi
                    done
                fi
            fi
        done< <(awk -v d1="$(printf '%(%d/%b/%Y:%H:%M:%S)T' $((now-60)))" '{gsub(/^[\[\t]+/, "", $4); if ( $4 > d1 ) print $1,$7;}' /usr/local/nginx/logs/access.log | sort | uniq -c | sort -k1 -nr)
        # date --date '-1 min' '+%d/%b/%Y:%T'
        # awk -v d1="$(printf '%(%d/%b/%Y:%H:%M:%S)T' $((now-60)))" '{gsub(/^[\[\t]+/, "", $4); if ($7 ~ "'"$link"'" && $4 > d1 ) print $1;}' /usr/local/nginx/logs/access.log | sort | uniq -c | sort -fr
        sleep 10

        if [ -n "${ips:-}" ] 
        then
            new_ips=()
            new_jail_time=()
            printf -v now "%(%s)T"

            update=0
            for((i=0;i<${#ips[@]};i++));
            do
                if [ "$now" -gt "${jail_time[i]}" ] 
                then
                    ufw delete deny from "${ips[i]}" to any port "$anti_ddos_port" > /dev/null 2>> "$IP_LOG"
                    update=1
                else
                    new_ips+=("${ips[i]}")
                    new_jail_time+=("${jail_time[i]}")
                fi
            done

            if [ "$update" == 1 ] 
            then
                ips=("${new_ips[@]}")
                jail_time=("${new_jail_time[@]}")

                printf "" > "$IP_DENY"

                for((i=0;i<${#ips[@]};i++));
                do
                    printf '%s\n' "${ips[i]}:${jail_time[i]}" >> "$IP_DENY"
                done
            fi
        fi
    done
}

AntiDDoSSet()
{
    if [ -x "$(command -v ufw)" ] && [ -s "/usr/local/nginx/logs/access.log" ] && ls -A $LIVE_ROOT/* > /dev/null 2>&1
    then
        sleep 1
        echo && echo "是否启动 AntiDDoS [Y/n]"
        read -p "(默认: Y):" anti_ddos
        anti_ddos=${anti_ddos:-"Y"}
        if [[ "$anti_ddos" == [Yy] ]] 
        then
            if ufw show added | grep -q "None" 
            then
                echo && echo -e "$info 添加常用 ufw 规则"
                ufw allow ssh > /dev/null 2>&1
                ufw allow http > /dev/null 2>&1
                ufw allow https > /dev/null 2>&1

                if ufw status | grep -q "inactive" 
                then
                    current_port=${SSH_CLIENT##* }
                    if [ "$current_port" != 22 ] 
                    then
                        ufw allow "$current_port" > /dev/null 2>&1
                    fi
                    echo && echo -e "$info 开启 ufw"
                    ufw --force enable > /dev/null 2>&1
                fi
            fi
            [ -z "${d_anti_ddos_port:-}" ] && GetDefault
            echo && echo "设置封禁端口"
            while read -p "(默认: $d_anti_ddos_port):" anti_ddos_port
            do
                case $anti_ddos_port in
                    "") anti_ddos_port=$d_anti_ddos_port && break
                    ;;
                    *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                    ;;
                    *) 
                        if [ "$anti_ddos_port" -gt 0 ]
                        then
                            break
                        else
                            echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                        fi
                    ;;
                esac
            done

            echo && echo "设置封禁ip多少秒"
            while read -p "(默认: $d_anti_ddos_seconds秒):" anti_ddos_seconds
            do
                case $anti_ddos_seconds in
                    "") anti_ddos_seconds=$d_anti_ddos_seconds && break
                    ;;
                    *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                    ;;
                    *) 
                        if [ "$anti_ddos_seconds" -gt 0 ]
                        then
                            break
                        else
                            echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                        fi
                    ;;
                esac
            done

            echo && echo "设置封禁等级(1-9)"
            echo -e "$tip 数值越低越严格，也越容易误伤，很多情况是网络问题导致重复请求并非 DDoS" && echo
            while read -p "(默认: $d_anti_ddos_level):" anti_ddos_level
            do
                case $anti_ddos_level in
                    "") 
                        anti_ddos_level=$d_anti_ddos_level
                        break
                    ;;
                    *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                    ;;
                    *) 
                        if [ "$anti_ddos_level" -gt 0 ] && [ "$anti_ddos_level" -lt 10 ]
                        then
                            break
                        else
                            echo && echo -e "$error 请输入正确的数字(1-9)" && echo
                        fi
                    ;;
                esac
            done

            $JQ_FILE '(.default|.anti_ddos_port)='"$anti_ddos_port"'|(.default|.anti_ddos_seconds)='"$anti_ddos_seconds"'|(.default|.anti_ddos_level)='"$anti_ddos_level"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
            mv "$CHANNELS_TMP" "$CHANNELS_FILE"

            ((anti_ddos_level++))

        else
            echo && echo "不启动 AntiDDoS ..." && echo && exit 0
        fi
    else
        exit 0
    fi
}

MonitorStop()
{
    printf -v date_now "%(%m-%d %H:%M:%S)T"
    if [ ! -s "$MONITOR_PID" ] 
    then
        echo -e "$error 监控未启动 !"
    else
        PID=$(< "$MONITOR_PID")
        if kill -0 "$PID" 2> /dev/null
        then
            if kill -9 "$PID" 2> /dev/null 
            then
                printf '%s\n' "$date_now 监控关闭成功 PID $PID !" >> "$MONITOR_LOG"
                echo -e "$info 监控关闭成功 !"
            else
                printf '%s\n' "$date_now 监控关闭失败 PID $PID !" >> "$MONITOR_LOG"
                echo -e "$error 监控关闭失败 !"
            fi
        else
            echo -e "$error 监控未启动 !"
        fi
    fi

    if [ -s "$IP_PID" ] 
    then
        PID=$(< "$IP_PID")
        if kill -0 "$PID" 2> /dev/null
        then
            if kill -9 "$PID" 2> /dev/null 
            then
                if [ -s "$IP_DENY" ] 
                then
                    ips=()
                    jail_time=()
                    GetDefault
                    while IFS= read -r line
                    do
                        if [[ "$line" == *:* ]] 
                        then
                            ip=${line%:*}
                            jail=${line#*:}
                            ips+=("$ip")
                            jail_time+=("$jail")
                        else
                            ip=$line
                            ufw delete deny from "$ip" to any port "$d_anti_ddos_port"
                        fi
                    done < "$IP_DENY"

                    if [ -n "${ips:-}" ] 
                    then
                        new_ips=()
                        new_jail_time=()
                        printf -v now "%(%s)T"

                        update=0
                        for((i=0;i<${#ips[@]};i++));
                        do
                            if [ "$now" -gt "${jail_time[i]}" ] 
                            then
                                ufw delete deny from "${ips[i]}" to any port "$d_anti_ddos_port"
                                update=1
                            else
                                new_ips+=("${ips[i]}")
                                new_jail_time+=("${jail_time[i]}")
                            fi
                        done

                        if [ "$update" == 1 ] 
                        then
                            ips=("${new_ips[@]}")
                            jail_time=("${new_jail_time[@]}")

                            printf "" > "$IP_DENY"

                            for((i=0;i<${#ips[@]};i++));
                            do
                                printf '%s\n' "${ips[i]}:${jail_time[i]}" >> "$IP_DENY"
                            done
                        fi
                    else
                        printf "" > "$IP_DENY"
                    fi
                fi
                printf '%s\n' "$date_now AntiDDoS 关闭成功 PID $PID !" >> "$MONITOR_LOG"
                echo -e "$info AntiDDoS 关闭成功 !"
            else
                printf '%s\n' "$date_now AntiDDoS 关闭失败 PID $PID !" >> "$MONITOR_LOG"
                echo -e "$error AntiDDoS 关闭失败 !"
            fi
        fi
    fi
}

MonitorError()
{
    printf -v date_now "%(%m-%d %H:%M:%S)T"
    printf '%s\n' "$date_now [LINE:$1] ERROR" >> "$MONITOR_LOG"
}

MonitorHlsRestartChannel()
{
    trap '' HUP INT TERM
    trap 'MonitorError $LINENO' ERR
    hls_restart_nums=${hls_restart_nums:-20}
    for((i=0;i<hls_restart_nums;i++))
    do
        action="skip"
        StopChannel > /dev/null 2>&1
        if [ "${stopped:-}" == 1 ] 
        then
            sleep 3
            StartChannel > /dev/null 2>&1
            sleep 15
            GetChannelInfo
            if ls -A "$LIVE_ROOT/$output_dir_name/"* > /dev/null 2>&1 
            then
                FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
                FFPROBE="$FFMPEG_ROOT/ffprobe"
                bit_rate=$($FFPROBE -v quiet -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*_00000.ts || true)
                bit_rate=${bit_rate//N\/A/0}
                audio_stream=$($FFPROBE -i "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*_00000.ts -show_streams -select_streams a -loglevel quiet || true)
                if [[ ${bit_rate:-0} -gt $hls_min_bitrates ]] && [ -n "$audio_stream" ]
                then
                    printf -v date_now "%(%m-%d %H:%M:%S)T"
                    printf '%s\n' "$date_now $chnl_channel_name 重启成功" >> "$MONITOR_LOG"
                    break
                fi
            elif [[ $i -eq $((hls_restart_nums - 1)) ]] 
            then
                StopChannel > /dev/null 2>&1
                printf -v date_now "%(%m-%d %H:%M:%S)T"
                printf '%s\n' "$date_now $chnl_channel_name 重启失败" >> "$MONITOR_LOG"
                declare -a new_array
                for element in "${monitor_dir_names_chosen[@]}"
                do
                    [ "$element" != "$output_dir_name" ] && new_array+=("$element")
                done
                monitor_dir_names_chosen=("${new_array[@]}")
                unset new_array
                break
            fi
        fi
    done
}

Monitor()
{
    trap '' HUP INT TERM QUIT EXIT
    trap 'MonitorError $LINENO' ERR
    printf '%s' "$BASHPID" > "$MONITOR_PID"
    mkdir -p "$LIVE_ROOT"
    printf '%s\n' "$date_now 监控启动成功 PID $BASHPID !" >> "$MONITOR_LOG"
    echo -e "$info 监控启动成功 !"
    while true; do
        if [ -n "${flv_nums:-}" ] 
        then
            kind="flv"
            if [ -n "${flv_all:-}" ] 
            then
                for((i=0;i<flv_count;i++));
                do
                    chnl_flv_pull_link=${monitor_flv_pull_links[i]%\'}
                    chnl_flv_pull_link=${chnl_flv_pull_link#\'}
                    chnl_flv_push_link=${monitor_flv_push_links[i]%\'}
                    chnl_flv_push_link=${chnl_flv_push_link#\'}
                    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
                    FFPROBE="$FFMPEG_ROOT/ffprobe"
                    audio_stream=$($FFPROBE -i "${chnl_flv_pull_link:-$chnl_flv_push_link}" -show_streams -select_streams a -loglevel quiet || true)
                    if [ -z "${audio_stream:-}" ] 
                    then
                        GetChannelInfo

                        if [ "${flv_restart_count:-1}" -gt "${flv_restart_nums:-20}" ] 
                        then
                            if [ "$chnl_flv_status" == "on" ] 
                            then
                                StopChannel > /dev/null 2>&1
                            fi

                            unset 'monitor_flv_push_links[0]'
                            declare -a new_array
                            for element in "${monitor_flv_push_links[@]}"
                            do
                                new_array[i]=$element
                                ((++i))
                            done
                            monitor_flv_push_links=("${new_array[@]}")
                            unset new_array

                            unset 'monitor_flv_pull_links[0]'
                            declare -a new_array
                            i=0
                            for element in "${monitor_flv_pull_links[@]}"
                            do
                                new_array[i]=$element
                                ((++i))
                            done
                            monitor_flv_pull_links=("${new_array[@]}")
                            unset new_array

                            flv_first_fail=""
                            flv_restart_count=1
                            ((flv_count--))

                            printf -v date_now "%(%m-%d %H:%M:%S)T"
                            printf '%s\n' "$date_now $chnl_channel_name flv 重启超过${flv_restart_nums:-20}次关闭" >> "$MONITOR_LOG"
                            break 1
                        fi

                        if [ -n "${flv_first_fail:-}" ]
                        then
                            printf -v flv_fail_date "%(%s)T"
                            if [ $((flv_fail_date - flv_first_fail)) -gt "$flv_delay_seconds" ] 
                            then
                                action="skip"
                                StopChannel > /dev/null 2>&1
                                if [ "${stopped:-}" == 1 ] 
                                then
                                    sleep 3
                                    StartChannel > /dev/null 2>&1
                                    flv_restart_count=${flv_restart_count:-1}
                                    ((flv_restart_count++))
                                    flv_first_fail=""
                                    printf -v date_now "%(%m-%d %H:%M:%S)T"
                                    printf '%s\n' "$date_now $chnl_channel_name flv 超时重启" >> "$MONITOR_LOG"
                                    sleep 10
                                fi
                            fi
                        else
                            if [ "$chnl_flv_status" == "off" ] 
                            then
                                StartChannel > /dev/null 2>&1
                                flv_restart_count=${flv_restart_count:-1}
                                ((flv_restart_count++))
                                flv_first_fail=""
                                printf -v date_now "%(%m-%d %H:%M:%S)T"
                                printf '%s\n' "$date_now $chnl_channel_name flv 恢复启动" >> "$MONITOR_LOG"
                                sleep 10
                            else
                                printf -v flv_first_fail "%(%s)T"
                            fi

                            new_array=("$chnl_flv_push_link")
                            for element in "${monitor_flv_push_links[@]}"
                            do
                                element=${element%\'}
                                element=${element#\'}
                                [ "$element" != "$chnl_flv_push_link" ] && new_array+=("$element")
                            done
                            monitor_flv_push_links=("${new_array[@]}")
                            unset new_array

                            new_array=("${monitor_flv_pull_links[i]}")
                            for((j=0;j<flv_count;j++));
                            do
                                [ "$j" != "$i" ] && new_array+=("${monitor_flv_pull_links[j]}")
                            done
                            monitor_flv_pull_links=("${new_array[@]}")
                            unset new_array
                        fi

                        break 1
                    else
                        flv_first_fail=""
                        flv_restart_count=1
                    fi
                done
            else
                for flv_num in "${flv_nums_arr[@]}"
                do
                    chnl_flv_pull_link=${monitor_flv_pull_links[$((flv_num-1))]%\'}
                    chnl_flv_pull_link=${chnl_flv_pull_link#\'}
                    chnl_flv_push_link=${monitor_flv_push_links[$((flv_num-1))]%\'}
                    chnl_flv_push_link=${chnl_flv_push_link#\'}
                    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
                    FFPROBE="$FFMPEG_ROOT/ffprobe"
                    audio_stream=$($FFPROBE -i "${chnl_flv_pull_link:-$chnl_flv_push_link}" -show_streams -select_streams a -loglevel quiet || true)
                    if [ -z "${audio_stream:-}" ] 
                    then
                        GetChannelInfo

                        if [ "${flv_restart_count:-1}" -gt "${flv_restart_nums:-20}" ] 
                        then
                            if [ "$chnl_flv_status" == "on" ] 
                            then
                                StopChannel > /dev/null 2>&1
                                printf -v date_now "%(%m-%d %H:%M:%S)T"
                                printf '%s\n' "$date_now $chnl_channel_name flv 重启超过${flv_restart_nums:-20}次关闭" >> "$MONITOR_LOG"
                            fi

                            declare -a new_array
                            for element in "${flv_nums_arr[@]}"
                            do
                                [ "$element" != "$flv_num" ] && new_array+=("$element")
                            done
                            flv_nums_arr=("${new_array[@]}")
                            unset new_array

                            flv_first_fail=""
                            flv_restart_count=1
                            break 1
                        fi

                        if [ -n "${flv_first_fail:-}" ] 
                        then
                            printf -v flv_fail_date "%(%s)T"
                            if [ $((flv_fail_date - flv_first_fail)) -gt "$flv_delay_seconds" ] 
                            then
                                action="skip"
                                StopChannel > /dev/null 2>&1
                                if [ "${stopped:-}" == 1 ] 
                                then
                                    sleep 3
                                    StartChannel > /dev/null 2>&1
                                    flv_restart_count=${flv_restart_count:-1}
                                    ((flv_restart_count++))
                                    flv_first_fail=""
                                    printf -v date_now "%(%m-%d %H:%M:%S)T"
                                    printf '%s\n' "$date_now $chnl_channel_name flv 超时重启" >> "$MONITOR_LOG"
                                    sleep 10
                                fi
                            fi
                        else
                            if [ "$chnl_flv_status" == "off" ] 
                            then
                                StartChannel > /dev/null 2>&1
                                flv_restart_count=${flv_restart_count:-1}
                                ((flv_restart_count++))
                                flv_first_fail=""
                                printf -v date_now "%(%m-%d %H:%M:%S)T"
                                printf '%s\n' "$date_now $chnl_channel_name flv 恢复启动" >> "$MONITOR_LOG"
                                sleep 10
                            else
                                printf -v flv_first_fail "%(%s)T"
                            fi

                            new_array=("$flv_num")
                            for element in "${flv_nums_arr[@]}"
                            do
                                [ "$element" != "$flv_num" ] && new_array+=("$element")
                            done
                            flv_nums_arr=("${new_array[@]}")
                            unset new_array
                        fi

                        break 1
                    else
                        flv_first_fail=""
                        flv_restart_count=1
                    fi
                done
            fi
        fi

        kind=""

        if ls -A $LIVE_ROOT/* > /dev/null 2>&1
        then
            largest_file=$(find "$LIVE_ROOT" -type f -printf "%s %p\n" | sort -n | tail -1 || true)
            if [ -n "${largest_file:-}" ] 
            then
                largest_file_size=${largest_file%% *}
                largest_file_path=${largest_file#* }
                output_dir_name=${largest_file_path#*$LIVE_ROOT/}
                output_dir_name=${output_dir_name%%/*}
                if [ "$largest_file_size" -gt $(( cmd * 1000000)) ]
                then
                    GetChannelInfo
                    printf '%s\n' "$chnl_channel_name 文件过大重启" >> "$MONITOR_LOG"
                    MonitorHlsRestartChannel
                fi
            fi

            if [ -n "$hls_nums" ] 
            then
                while IFS= read -r old_file_path
                do
                    if [[ "$old_file_path" == *"_master.m3u8" ]] 
                    then
                        continue
                    fi
                    output_dir_name=${old_file_path#*$LIVE_ROOT/}
                    output_dir_name=${output_dir_name%%/*}
                    if [ "${monitor_all}" == 1 ] 
                    then
                        GetChannelInfo
                        printf '%s\n' "$chnl_channel_name 超时重启" >> "$MONITOR_LOG"
                        MonitorHlsRestartChannel
                        break 1
                    else
                        for dir_name in "${monitor_dir_names_chosen[@]}"
                        do
                            if [ "$dir_name" == "$output_dir_name" ] 
                            then
                                GetChannelInfo
                                printf '%s\n' "$chnl_channel_name 超时重启" >> "$MONITOR_LOG"
                                MonitorHlsRestartChannel
                                break 2
                            fi
                        done  
                    fi
                done < <(find "$LIVE_ROOT/"* \! -newermt "-$hls_delay_seconds seconds" || true)

                for dir_name in "${monitor_dir_names_chosen[@]}"
                do
                    output_dir_name=$dir_name
                    chnl_status=""
                    GetChannelInfo
                    if [ -z "$chnl_status" ] 
                    then
                        declare -a new_array
                        for element in "${monitor_dir_names_chosen[@]}"
                        do
                            [ "$element" != "$output_dir_name" ] && new_array+=("$element")
                        done
                        monitor_dir_names_chosen=("${new_array[@]}")
                        unset new_array
                        break 1
                    fi
                    if [ "$chnl_status" == "off" ] 
                    then
                        sleep 5
                        chnl_status=""
                        GetChannelInfo
                        if [ -z "$chnl_status" ] 
                        then
                            declare -a new_array
                            for element in "${monitor_dir_names_chosen[@]}"
                            do
                                [ "$element" != "$output_dir_name" ] && new_array+=("$element")
                            done
                            monitor_dir_names_chosen=("${new_array[@]}")
                            unset new_array
                            break 1
                        fi
                        if [ "$chnl_status" == "off" ] 
                        then
                            printf '%s\n' "$chnl_channel_name 开启" >> "$MONITOR_LOG"
                            MonitorHlsRestartChannel
                            break 1
                        fi
                    fi
                    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
                    FFPROBE="$FFMPEG_ROOT/ffprobe"
                    bit_rate=$($FFPROBE -v quiet -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$LIVE_ROOT/$dir_name/$chnl_seg_dir_name/"*_00000.ts || true)
                    bit_rate=${bit_rate:-$hls_min_bitrates}
                    bit_rate=${bit_rate//N\/A/$hls_min_bitrates}
                    #audio_stream=$($FFPROBE -i "$LIVE_ROOT/$dir_name/$chnl_seg_dir_name/"*_00000.ts -show_streams -select_streams a -loglevel quiet || true)
                    if [[ $bit_rate -lt $hls_min_bitrates ]] # || [ -z "$audio_stream" ]
                    then
                        output_dir_name=$dir_name
                        fail_count=1
                        for f in "$LIVE_ROOT/$dir_name/$chnl_seg_dir_name/"*.ts
                        do
                            bit_rate=$($FFPROBE -v quiet -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$f" || true)
                            bit_rate=${bit_rate:-$hls_min_bitrates}
                            bit_rate=${bit_rate//N\/A/$hls_min_bitrates}
                            if [[ $bit_rate -lt $hls_min_bitrates ]] 
                            then
                                ((fail_count++))
                            fi
                            if [ "$fail_count" -gt 3 ] 
                            then
                                printf '%s\n' "$chnl_channel_name 比特率过低重启" >> "$MONITOR_LOG"
                                MonitorHlsRestartChannel
                                break 1
                            fi
                        done
                    fi
                done
            fi
        fi

        sleep 5
    done
}

MonitorSet()
{
    monitor=1
    flv_count=0
    monitor_channel_names=()
    monitor_flv_push_links=()
    monitor_flv_pull_links=()
    GetChannelsInfo
    for((i=0;i<chnls_count;i++));
    do
        if [ "${chnls_flv_status[i]}" == "on" ] 
        then
            flv_count=$((flv_count+1))
            monitor_channel_names+=("${chnls_channel_name[i]}");
            monitor_flv_push_links+=("${chnls_flv_push_link[i]}");
            monitor_flv_pull_links+=("${chnls_flv_pull_link[i]}");
        fi
    done
    
    if [ "$flv_count" -gt 0 ] 
    then
        GetDefault
        echo && echo "请选择需要监控的 FLV 推流频道(多个频道用空格分隔)" && echo

        for((i=0;i<flv_count;i++));
        do
            flv_pull_link=${monitor_flv_pull_links[i]%\'}
            flv_pull_link=${flv_pull_link#\'}
            echo -e "  ${green}$((i+1)).$plain ${monitor_channel_names[i]} ${flv_pull_link}"
        done

        echo && echo -e "  ${green}$((i+1)).$plain 全部"
        echo -e "  ${green}$((i+2)).$plain 不设置" && echo
        while read -p "(默认: 不设置):" flv_nums
        do
            if [ -z "$flv_nums" ] || [ "$flv_nums" == $((i+2)) ] 
            then
                flv_nums=""
                break
            fi
            IFS=" " read -ra flv_nums_arr <<< "$flv_nums"

            if [ "$flv_nums" == $((i+1)) ] 
            then
                flv_all=1
                echo && echo "设置超时多少秒自动重启频道"
                while read -p "(默认: $d_flv_delay_seconds秒):" flv_delay_seconds
                do
                    case $flv_delay_seconds in
                        "") flv_delay_seconds=$d_flv_delay_seconds && break
                        ;;
                        *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                        ;;
                        *) 
                            if [ "$flv_delay_seconds" -gt 0 ]
                            then
                                break
                            else
                                echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                            fi
                        ;;
                    esac
                done
                break
            fi

            error_no=0
            for flv_num in "${flv_nums_arr[@]}"
            do
                case "$flv_num" in
                    *[!0-9]*)
                        error_no=1
                    ;;
                    *)
                        if [ "$flv_num" -lt 1 ] || [ "$flv_num" -gt "$flv_count" ]
                        then
                            error_no=2
                        fi
                    ;;
                esac
            done

            case "$error_no" in
                1|2)
                    echo -e "$error 请输入正确的数字或直接回车 " && echo
                ;;
                *)
                    echo && echo "设置超时多少秒自动重启频道"
                    while read -p "(默认: $d_flv_delay_seconds秒):" flv_delay_seconds
                    do
                        case $flv_delay_seconds in
                            "") flv_delay_seconds=$d_flv_delay_seconds && break
                            ;;
                            *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                            ;;
                            *) 
                                if [ "$flv_delay_seconds" -gt 0 ]
                                then
                                    break
                                else
                                    echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                                fi
                            ;;
                        esac
                    done
                    break
                ;;
            esac
        done

        echo && echo "请输入尝试重启的次数"
        while read -p "(默认: $d_flv_restart_nums次):" flv_restart_nums
        do
            case $flv_restart_nums in
                "") flv_restart_nums=$d_flv_restart_nums && break
                ;;
                *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                ;;
                *) 
                    if [ "$flv_restart_nums" -gt 0 ]
                    then
                        break
                    else
                        echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                    fi
                ;;
            esac
        done
    fi

    if ! ls -A $LIVE_ROOT/* > /dev/null 2>&1
    then
        if [ "$flv_count" == 0 ] 
        then
            echo && echo -e "$error 没有开启的频道！" && echo && exit 1
        fi
        $JQ_FILE '(.default|.flv_delay_seconds)='"$flv_delay_seconds"'|(.default|.flv_restart_nums)='"$flv_restart_nums"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        return 0
    fi
    echo && echo "请选择需要监控超时重启的 HLS 频道(多个频道用空格分隔)"
    echo "一般不需要设置，只有在需要重启频道才能继续连接直播源的情况下启用" && echo
    monitor_count=0
    monitor_dir_names=()
    [ -z "${d_hls_delay_seconds:-}" ] && GetDefault
    for((i=0;i<chnls_count;i++));
    do
        if [ -e "$LIVE_ROOT/${chnls_output_dir_name[i]}" ] 
        then
            monitor_count=$((monitor_count + 1))
            monitor_dir_names+=("${chnls_output_dir_name[i]}")
            echo -e "  ${green}$monitor_count.$plain ${chnls_channel_name[i]}"
        fi
    done
    
    echo && echo -e "  ${green}$((monitor_count+1)).$plain 全部"
    echo -e "  ${green}$((monitor_count+2)).$plain 不设置" && echo
    
    while read -p "(默认: 不设置):" hls_nums
    do
        if [ -z "$hls_nums" ] || [ "$hls_nums" == $((monitor_count+2)) ] 
        then
            hls_nums=""
            break
        fi
        IFS=" " read -ra hls_nums_arr <<< "$hls_nums"

        monitor_dir_names_chosen=()
        if [ "$hls_nums" == $((monitor_count+1)) ] 
        then
            monitor_all=1
            monitor_dir_names_chosen=("${monitor_dir_names[@]}")

            echo && echo "设置超时多少秒自动重启频道"
            echo -e "$tip 必须大于 段时长*段数目" && echo
            while read -p "(默认: $d_hls_delay_seconds秒):" hls_delay_seconds
            do
                case $hls_delay_seconds in
                    "") hls_delay_seconds=$d_hls_delay_seconds && break
                    ;;
                    *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                    ;;
                    *) 
                        if [ "$hls_delay_seconds" -gt 60 ]
                        then
                            break
                        else
                            echo && echo -e "$error 请输入正确的数字(大于60)" && echo
                        fi
                    ;;
                esac
            done
            break
        else
            monitor_all=0
        fi

        error_no=0
        for hls_num in "${hls_nums_arr[@]}"
        do
            case "$hls_num" in
                *[!0-9]*)
                    error_no=1
                ;;
                *)
                    if [ "$hls_num" -lt 1 ] || [ "$hls_num" -gt "$monitor_count" ]
                    then
                        error_no=2
                    fi
                ;;
            esac
        done

        case "$error_no" in
            1|2)
                echo -e "$error 请输入正确的数字或直接回车 " && echo
            ;;
            *)
                for hls_num in "${hls_nums_arr[@]}"
                do
                    monitor_dir_names_chosen+=("${monitor_dir_names[((hls_num - 1))]}")
                done

                echo && echo "设置超时多少秒自动重启频道"
                echo -e "$tip 必须大于 段时长*段数目" && echo
                while read -p "(默认: $d_hls_delay_seconds秒):" hls_delay_seconds
                do
                    case $hls_delay_seconds in
                        "") hls_delay_seconds=$d_hls_delay_seconds && break
                        ;;
                        *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                        ;;
                        *) 
                            if [ "$hls_delay_seconds" -gt 60 ]
                            then
                                break
                            else
                                echo && echo -e "$error 请输入正确的数字(大于60)" && echo
                            fi
                        ;;
                    esac
                done

                break
            ;;
        esac
    done

    if [ -n "$hls_nums" ] 
    then
        echo && echo "请输入最低比特率(kb/s),低于此数值会重启频道"
        while read -p "(默认: $d_hls_min_bitrates):" hls_min_bitrates
        do
            case $hls_min_bitrates in
                "") hls_min_bitrates=$d_hls_min_bitrates && break
                ;;
                *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                ;;
                *) 
                    if [ "$hls_min_bitrates" -gt 0 ]
                    then
                        break
                    else
                        echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                    fi
                ;;
            esac
        done

        hls_min_bitrates=$((hls_min_bitrates * 1000))
    fi

    echo && echo "请输入尝试重启的次数"
    while read -p "(默认: $d_hls_restart_nums次):" hls_restart_nums
    do
        case $hls_restart_nums in
            "") hls_restart_nums=$d_hls_restart_nums && break
            ;;
            *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
            ;;
            *) 
                if [ "$hls_restart_nums" -gt 0 ]
                then
                    break
                else
                    echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                fi
            ;;
        esac
    done

    flv_delay_seconds=${flv_delay_seconds:-$d_flv_delay_seconds}
    flv_restart_nums=${flv_restart_nums:-$d_flv_restart_nums}
    hls_delay_seconds=${hls_delay_seconds:-$d_hls_delay_seconds}
    hls_min_bitrates=${hls_min_bitrates:-$d_hls_min_bitrates}
    $JQ_FILE '(.default|.flv_delay_seconds)='"$flv_delay_seconds"'|(.default|.flv_restart_nums)='"$flv_restart_nums"'|(.default|.hls_delay_seconds)='"$hls_delay_seconds"'|(.default|.hls_min_bitrates)='"$((hls_min_bitrates / 1000))"'|(.default|.hls_restart_nums)='"$hls_restart_nums"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
}

Progress(){
    echo && echo -ne "$info 安装中，请等待..."
    while true
    do
        echo -n "."
        sleep 5
    done
}

InstallNginx()
{
    echo -e "$info 检查依赖，耗时可能会很长..."
    Progress &
    progress_pid=$!
    CheckRelease
    if [ "$release" == "rpm" ] 
    then
        yum -y install gcc gcc-c++ >/dev/null 2>&1
        timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1
        systemctl restart crond >/dev/null 2>&1
        echo -n "...40%..."
    else
        apt-get -y update >/dev/null 2>&1
        locale-gen zh_CN.UTF-8 >/dev/null 2>&1
        timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1
        systemctl restart cron >/dev/null 2>&1
        apt-get -y install debconf-utils >/dev/null 2>&1
        echo '* libraries/restart-without-asking boolean true' | debconf-set-selections
        apt-get -y install software-properties-common pkg-config libssl-dev libghc-zlib-dev libcurl4-gnutls-dev libexpat1-dev unzip gettext build-essential >/dev/null 2>&1
        echo -n "...40%..."
    fi

    cd ~
    if [ ! -e "./pcre-8.43" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "https://ftp.pcre.org/pub/pcre/pcre-8.43.tar.gz" -qO "pcre-8.43.tar.gz"
        tar xzvf "pcre-8.43.tar.gz" >/dev/null 2>&1
    fi

    if [ ! -e "./zlib-1.2.11" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "https://www.zlib.net/zlib-1.2.11.tar.gz" -qO "zlib-1.2.11.tar.gz"
        tar xzvf "zlib-1.2.11.tar.gz" >/dev/null 2>&1
    fi

    if [ ! -e "./openssl-1.1.1d" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "https://www.openssl.org/source/openssl-1.1.1d.tar.gz" -qO "openssl-1.1.1d.tar.gz"
        tar xzvf "openssl-1.1.1d.tar.gz" >/dev/null 2>&1
    fi

    if [ ! -e "./nginx-http-flv-module-master" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "$FFMPEG_MIRROR_LINK/nginx-http-flv-module.zip" -qO "nginx-http-flv-module.zip"
        unzip "nginx-http-flv-module.zip" >/dev/null 2>&1
    fi

    while IFS= read -r line
    do
        if [[ "$line" == *"/download/"* ]] 
        then
            nginx_name=${line#*/download/}
            nginx_name=${nginx_name%%.tar.gz*}
        fi
    done < <( wget "http://nginx.org/en/download.html" -qO- )
    

    if [ ! -e "./$nginx_name" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "https://nginx.org/download/$nginx_name.tar.gz" -qO "$nginx_name.tar.gz"
        tar xzvf "$nginx_name.tar.gz" >/dev/null 2>&1
    fi

    echo -n "...60%..."
    cd "$nginx_name/"
    ./configure --add-module=../nginx-http-flv-module-master --with-pcre=../pcre-8.43 --with-pcre-jit --with-zlib=../zlib-1.2.11 --with-openssl=../openssl-1.1.1d --with-openssl-opt=no-nextprotoneg --with-http_stub_status_module --with-http_ssl_module --with-http_realip_module --with-debug >/dev/null 2>&1
    echo -n "...80%..."
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    kill $progress_pid
    ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/
    echo -n "...100%" && echo
}

UninstallNginx()
{
    if [ ! -e "/usr/local/nginx" ] 
    then
        echo && echo -e "$error Nginx 未安装 !" && echo && exit 1
    fi

    echo && echo "确定删除 nginx 包括所有配置文件，操作不可恢复？[y/N]"
    read -p "(默认: N):" nginx_uninstall_yn
    nginx_uninstall_yn=${nginx_uninstall_yn:-"N"}

    if [[ $nginx_uninstall_yn == [Yy] ]] 
    then
        nginx -s stop
        rm -rf /usr/local/nginx/
        echo && echo -e "$info Nginx 卸载完成" && echo
    else
        echo && echo "已取消..." && echo && exit 1
    fi
}

ToggleNginx()
{
    if [ ! -s "/usr/local/nginx/logs/nginx.pid" ] 
    then
        echo && echo "nginx 未运行，是否开启？[Y/n]"
        read -p "(默认: Y):" nginx_start_yn
        nginx_start_yn=${nginx_start_yn:-"Y"}
        if [[ $nginx_start_yn == [Yy] ]] 
        then
            nginx
            echo && echo -e "$info Nginx 已开启" && echo
        else
            echo && echo "已取消..." && echo && exit 1
        fi
    else
        PID=$(< "/usr/local/nginx/logs/nginx.pid")
        if kill -0  "$PID" 2> /dev/null
        then
            echo && echo "nginx 正在运行，是否关闭？[Y/n]"
            read -p "(默认: Y):" nginx_stop_yn
            nginx_stop_yn=${nginx_stop_yn:-"Y"}
            if [[ $nginx_stop_yn == [Yy] ]] 
            then
                nginx -s stop
                echo && echo -e "$info Nginx 已关闭" && echo
            else
                echo && echo "已取消..." && echo && exit 1
            fi
        else
            echo && echo "nginx 未运行，是否开启？[Y/n]"
            read -p "(默认: Y):" nginx_start_yn
            nginx_start_yn=${nginx_start_yn:-"Y"}
            if [[ $nginx_start_yn == [Yy] ]] 
            then
                nginx
                echo && echo -e "$info Nginx 已开启" && echo
            else
                echo && echo "已取消..." && echo && exit 1
            fi
        fi
    fi
}

RestartNginx()
{
    PID=$(< "/usr/local/nginx/logs/nginx.pid")
    if kill -0  "$PID" 2> /dev/null 
    then
        nginx -s stop
        sleep 1
        nginx
    else
        nginx
    fi
}

NginxConfigFlv()
{
    nginx_conf=$(< "/usr/local/nginx/conf/nginx.conf")
    if ! grep -q "location /flv" <<< "$nginx_conf"
    then
        conf=""
        found=0
        while IFS= read -r line 
        do
            if [[ "$line" == *"location / "* ]] && [ "$found" == 0 ]
            then
                conf="$conf
        location /flv {
            access_log  logs/flv.log;
            flv_live on;
            chunked_transfer_encoding  on;
        }
"
                found=1
            fi
            [ -n "$conf" ] && conf="$conf\n"
            conf="$conf$line"
        done <<< "$nginx_conf"

        if ! grep -q "rtmp {" <<< "$nginx_conf" 
        then
            conf="$conf

rtmp_auto_push on;
rtmp_auto_push_reconnect 1s;
rtmp_socket_dir /tmp;

rtmp {
    out_queue   4096;
    out_cork    8;
    max_streams   128;
    timeout   15s;
    drop_idle_publisher   10s;
    log_interval    120s;
    log_size    1m;

    server {
        listen 1935;
        server_name 127.0.0.1;
        access_log  logs/flv.log;

        application flv {
            live on;
            gop_cache on;
        }
    }
}"
        fi
        echo -e "$conf" > "/usr/local/nginx/conf/nginx.conf"
    fi
}

Usage()
{

cat << EOM
HTTP Live Stream Creator
Wrapper By MTimer

Copyright (C) 2013 B Tasker, D Atanasov
Released under BSD 3 Clause License
See LICENSE

使用方法: tv -i [直播源] [-s 段时长(秒)] [-o 输出目录名称] [-c m3u8包含的段数目] [-b 比特率] [-p m3u8文件名称] [-C]

    -i  直播源(支持 mpegts / hls / flv ...)
        hls 链接需包含 .m3u8 标识
    -s  段时长(秒)(默认：6)
    -o  输出目录名称(默认：随机名称)

    -p  m3u8名称(前缀)(默认：随机)
    -c  m3u8里包含的段数目(默认：5)
    -S  段所在子目录名称(默认：不使用子目录)
    -t  段名称(前缀)(默认：跟m3u8名称相同)
    -a  音频编码(默认：aac) (不需要转码时输入 copy)
    -v  视频编码(默认：h264) (不需要转码时输入 copy)
    -f  画面或声音延迟(格式如： v_3 画面延迟3秒，a_2 声音延迟2秒
        使用此功能*暂时*会忽略部分参数，画面声音不同步时使用)
    -q  crf视频质量(如果同时设置了输出视频比特率，则优先使用crf视频质量)(数值1~63 越大质量越差)
        (默认: 不设置crf视频质量值)
    -b  输出视频的比特率(kb/s)(默认：900-1280x720)
        如果已经设置crf视频质量值，则比特率用于 -maxrate -bufsize
        如果没有设置crf视频质量值，则可以继续设置是否固定码率
        多个比特率用逗号分隔(注意-如果设置多个比特率，就是生成自适应码流)
        同时可以指定输出的分辨率(比如：-b 600-600x400,900-1280x720)
        可以输入 omit 省略此选项
    -C  固定码率(只有在没有设置crf视频质量的情况下才有效)(默认：否)
    -e  加密段(默认：不加密)
    -K  Key名称(默认：跟m3u8名称相同)
    -z  频道名称(默认：跟m3u8名称相同)

    也可以不输出 HLS，比如 flv 推流
    -k  设置推流类型，比如 -k flv
    -T  设置推流地址，比如 rtmp://127.0.0.1/live/xxx
    -L  输入拉流(播放)地址(可省略)，比如 http://domain.com/live?app=live&stream=xxx

    -m  ffmpeg 额外的 INPUT FLAGS
        (默认："-reconnect 1 -reconnect_at_eof 1 
        -reconnect_streamed 1 -reconnect_delay_max 2000 
        -timeout 2000000000 -y -nostats -nostdin -hide_banner -loglevel fatal")
    -n  ffmpeg 额外的 OUTPUT FLAGS, 可以输入 omit 省略此选项
        (默认："-g 25 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main")

举例:
    使用crf值控制视频质量: 
        tv -i http://xxx.com/xxx.ts -s 6 -o hbo1 -p hbo1 -q 15 -b 1500-1280x720 -z 'hbo直播1'
    使用比特率控制视频质量[默认]: 
        tv -i http://xxx.com/xxx.ts -s 6 -o hbo2 -p hbo2 -b 900-1280x720 -z 'hbo直播2'

    不需要转码的设置: -a copy -v copy -n omit

    不输出 HLS, 推流 flv :
        tv -i http://xxx/xxx.ts -a aac -v h264 -b 3000 -k flv -T rtmp://127.0.0.1/live/xxx

EOM

exit

}

if [ -e "$IPTV_ROOT" ] && [ ! -e "$LOCK_FILE" ] 
then
    UpdateSelf
fi

if [ "${0##*/}" == "v2" ] 
then
        echo && echo -e "  v2ray 管理面板 $plain

  ${green}1.$plain 安装
  ${green}2.$plain 查看
  ${green}3.$plain 升级
————————————
  ${green}4.$plain 开关
  ${green}5.$plain 重启
————————————
  ${green}6.$plain 配置域名
 " && echo
        read -p "请输入数字 [1-6]：" v2ray_num
        case $v2ray_num in
            1) 
                CheckRelease
                if [ -e "/etc/v2ray/config.json" ] 
                then
                    while IFS= read -r line 
                    do
                        if [[ "$line" == *"port"* ]] 
                        then
                            port=${line#*: }
                            port=${port%,*}
                        elif [[ "$line" == *"id"* ]] 
                        then
                            id=${line#*: \"}
                            id=${id%\"*}
                        elif [[ "$line" == *"path"* ]] 
                        then
                            path=${line#*: \"}
                            path=${path%\"*}
                            break
                        fi
                    done < "/etc/v2ray/config.json"

                    if [ -n "${path:-}" ] 
                    then
                        echo && echo -e "$error v2ray 已安装..." && echo && exit 1
                    fi
                fi

                echo && echo -e "$info 安装 v2ray..."

                bash <(curl --silent -m 10 https://install.direct/go.sh) > /dev/null

                while IFS= read -r line 
                do
                    if [[ "$line" == *"port"* ]] 
                    then
                        port=${line#*: }
                        port=${port%,*}
                    elif [[ "$line" == *"id"* ]] 
                    then
                        id=${line#*: \"}
                        id=${id%\"*}
                        break
                    fi
                done < "/etc/v2ray/config.json"

                v2ray_config='{
  "inbounds": [{
    "port": '"$port"',
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "'"$id"'",
          "level": 1,
          "alterId": 64
        }
      ]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "/'"$(RandStr)"'"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  },{
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}'
                printf '%s' "$v2ray_config" > "/etc/v2ray/config.json"
                service v2ray start > /dev/null
                echo && echo -e "$info v2ray 安装完成..." && echo
            ;;
            2) 
                if [ ! -e "/etc/v2ray/config.json" ] 
                then
                    echo && echo -e "$error v2ray 未安装..." && echo && exit 1
                fi

                while IFS= read -r line 
                do
                    if [[ "$line" == *"port"* ]] 
                    then
                        port=${line#*: }
                        port=${port%,*}
                    elif [[ "$line" == *"id"* ]] 
                    then
                        id=${line#*: \"}
                        id=${id%\"*}
                    elif [[ "$line" == *"path"* ]] 
                    then
                        path=${line#*: \"}
                        path=${path%\"*}
                        break
                    fi
                done < "/etc/v2ray/config.json"

                if [ -e "/usr/local/nginx" ] 
                then
                    while IFS= read -r line 
                    do
                        if [[ $line == *"server_name"* ]]
                        then
                            domain=${line%;*}
                            domain=${domain##* }
                        elif [[ $line == *"v2ray.crt"* ]] 
                        then
                            break
                        fi
                    done < "/usr/local/nginx/conf/nginx.conf"
                fi

                if service v2ray status > /dev/null
                then
                    echo && echo -e "v2ray: $green开启$plain"
                else
                    echo && echo -e "v2ray: $red关闭$plain"
                fi
                
                [ -n "${domain:-}" ] && echo && echo -e "$green域名:$plain $domain"
                echo && echo -e "$green端口:$plain $port"
                echo && echo -e "${green}id:$plain $id"
                echo && echo -e "${green}协议:$plain vmess"
                echo && echo -e "${green}网络:$plain ws"
                echo && echo -e "${green}path:$plain $path"
                echo && echo -e "${green}security:$plain tls" && echo
            ;;
            3) 
                if [ ! -e "/etc/v2ray/config.json" ] 
                then
                    echo && echo -e "$error v2ray 未安装..." && echo && exit 1
                fi
                bash <(curl --silent -m 10 https://install.direct/go.sh) > /dev/null
            ;;
            4) 
                if [ ! -e "/etc/v2ray/config.json" ] 
                then
                    echo && echo -e "$error v2ray 未安装..." && echo && exit 1
                fi

                if service v2ray status > /dev/null
                then
                    echo && echo "v2ray 正在运行，是否关闭？[Y/n]"
                    read -p "(默认: Y):" v2ray_stop_yn
                    v2ray_stop_yn=${v2ray_stop_yn:-"Y"}
                    if [[ $v2ray_stop_yn == [Yy] ]] 
                    then
                        service v2ray  stop
                        echo && echo -e "$info v2ray 已关闭" && echo
                    else
                        echo && echo "已取消..." && echo && exit 1
                    fi
                else
                    echo && echo "v2ray 未运行，是否开启？[Y/n]"
                    read -p "(默认: Y):" v2ray_start_yn
                    v2ray_start_yn=${v2ray_start_yn:-"Y"}
                    if [[ $v2ray_start_yn == [Yy] ]] 
                    then
                        service v2ray start
                        echo && echo -e "$info v2ray 已开启" && echo
                    else
                        echo && echo "已取消..." && echo && exit 1
                    fi
                fi
            ;;
            5) 
                if [ ! -e "/etc/v2ray/config.json" ] 
                then
                    echo && echo -e "$error v2ray 未安装..." && echo && exit 1
                fi
                service v2ray restart
                echo && echo -e "$info v2ray 已重启" && echo
            ;;
            6) 
                if [ ! -e "/etc/v2ray/config.json" ] 
                then
                    echo && echo -e "$error v2ray 未安装..." && echo && exit 1
                else
                    while IFS= read -r line 
                    do
                        if [[ "$line" == *"port"* ]] 
                        then
                            port=${line#*: }
                            port=${port%,*}
                        elif [[ "$line" == *"id"* ]] 
                        then
                            id=${line#*: \"}
                            id=${id%\"*}
                        elif [[ "$line" == *"path"* ]] 
                        then
                            path=${line#*: \"}
                            path=${path%\"*}
                            break
                        fi
                    done < "/etc/v2ray/config.json"

                    if [ -z "${path:-}" ] 
                    then
                        echo && echo -e "$error v2ray 未安装..." && echo && exit 1
                    fi
                fi

                if [ ! -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 未安装! 输入 tv n 安装 Nginx" && echo && exit 1
                fi

                echo && echo "输入指向本机的域名"
                read -p "(默认: 取消):" domain
                [ -z "$domain" ] && echo && echo "已取消..." && echo && exit 1
                
                CheckRelease

                echo && echo -e "$info 安装证书..."
                if [ ! -e "$HOME/.acme.sh/acme.sh" ] 
                then
                    if [ "$release" == "rpm" ] 
                    then
                        yum -y install socat > /dev/null
                    else
                        apt-get -y install socat > /dev/null
                    fi
                    bash <(curl --silent -m 10 https://get.acme.sh) > /dev/null
                fi

                nginx -s stop
                sleep 1
                ~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 > /dev/null
                ~/.acme.sh/acme.sh --installcert -d "$domain" --fullchainpath /etc/v2ray/v2ray.crt --keypath /etc/v2ray/v2ray.key --ecc > /dev/null
                echo && echo -e "$info 证书安装完成..."

                echo && echo -e "$info 配置 Nginx..."

                nginx_conf=$(< "/usr/local/nginx/conf/nginx.conf")

                if ! grep -q "location $PATH {" <<< "$nginx_conf"
                then
                    action="add"
                else
                    action="edit"
                fi

                conf=""
                found=0
                while IFS= read -r line 
                do
                    if [[ $line == *"# HTTPS server"* ]] && [ "$action" == "add" ]
                    then
                        conf="$conf
    server {
        listen       443 ssl;
        server_name  $domain;

        access_log off;

        ssl_certificate      /etc/v2ray/v2ray.crt;
        ssl_certificate_key  /etc/v2ray/v2ray.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        ssl_ciphers  HIGH:!aNULL:!MD5;

        location /ray {
            proxy_redirect off;
            proxy_pass http://127.0.0.1:$port;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Host \$host;
            # Show real IP in v2ray access.log
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
    }
"
                    elif [ "$action" == "edit" ] && [[ $line == *"443 ssl"* ]] 
                    then
                        found=1
                    elif [ "$action" == "edit" ] && [ "$found" == 1 ] && [[ $line == *"server_name"* ]]
                    then
                        line="        server_name  $domain;"
                    fi
                    [ -n "$conf" ] && conf="$conf\n"
                    conf="$conf$line"
                done < "/usr/local/nginx/conf/nginx.conf"

                echo -e "$conf" > "/usr/local/nginx/conf/nginx.conf"
                nginx
                echo && echo -e "$info 配置 Nginx 完成..."
                echo && echo -e "$info 域名配置完成" && echo
            ;;
            *) echo -e "$error 请输入正确的数字 [1-6]"
            ;;
        esac
        exit 0
fi

if [[ -n ${1+x} ]]
then
    case $1 in
        "s") 
            [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请先安装 !" && exit 1
            Schedule "$@"
            exit 0
        ;;
        "m") 
            [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请先安装 !" && exit 1

            cmd=${2:-5}

            case $cmd in
                "s"|"stop") 
                    MonitorStop
                ;;
                "l"|"log")
                    if [ -s "$IP_LOG" ] 
                    then
                        echo -e "$info 监控日志: "
                        tail -n 10 "$MONITOR_LOG"
                        echo && echo -e "$info AntiDDoS 日志: "
                        tail -n 10 "$IP_LOG"
                    elif [ -s "$MONITOR_LOG" ] 
                    then
                        echo -e "$info 监控日志: "
                        tail -n 10 "$MONITOR_LOG"
                    else
                        echo -e "$error 无日志"
                    fi
                ;;
                *[!0-9]*)
                    echo -e "$error 请输入正确的数字(大于0) "
                ;;
                0)
                    echo -e "$error 请输入正确的数字(大于0) "
                ;;
                *) 
                    if [ ! -s "$MONITOR_PID" ] 
                    then
                        printf -v date_now "%(%m-%d %H:%M:%S)T"
                        MonitorSet
                        Monitor &
                        AntiDDoSSet
                        AntiDDoS &
                    else
                        PID=$(< "$MONITOR_PID")
                        if kill -0 "$PID" 2> /dev/null 
                        then
                            echo -e "$error 监控已经在运行 !"
                        else
                            printf -v date_now "%(%m-%d %H:%M:%S)T"
                            MonitorSet
                            Monitor &
                            AntiDDoSSet
                            AntiDDoS &
                        fi
                    fi
                ;;
            esac

            exit 0
        ;;
        "t") 
            [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1

            if [ -z ${2+x} ] 
            then
                echo -e "$error 请指定文件 !" && exit 1
            elif [ ! -e "$2" ] 
            then
                echo -e "$error 文件不存在 !" && exit 1
            fi

            echo && echo "请输入测试的频道ID"
            while read -p "(默认: 取消):" channel_id
            do
                case $channel_id in
                    "") echo && echo -e "$error 已取消..." && exit 1
                    ;;
                    *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                    ;;
                    *) 
                        if [ "$channel_id" -gt 0 ]
                        then
                            break
                        else
                            echo && echo -e "$error 请输入正确的ID(大于0)" && echo
                        fi
                    ;;
                esac
            done
            

            set +euo pipefail
            
            while IFS= read -r line
            do
                if [[ $line == *"username="* ]] 
                then
                    domain_line=${line#*http://}
                    domain=${domain_line%%/*}
                    u_line=${line#*username=}
                    p_line=${line#*password=}
                    username=${u_line%%&*}
                    password=${p_line%%&*}
                    link="http://$domain/$username/$password/$channel_id"
                    if curl --output /dev/null --silent --fail -r 0-0 "$link"
                    then
                        echo "$link"
                    fi
                fi
            done < "$2"

            exit 0
        ;;
        *)
        ;;
    esac
fi

use_menu=1

while getopts "i:o:p:S:t:s:c:v:a:f:q:b:k:K:m:n:z:T:L:Ce" flag
do
    use_menu=0
        case "$flag" in
            i) stream_link="$OPTARG";;
            o) output_dir_name="$OPTARG";;
            p) playlist_name="$OPTARG";;
            S) seg_dir_name="$OPTARG";;
            t) seg_name="$OPTARG";;
            s) seg_length="$OPTARG";;
            c) seg_count="$OPTARG";;
            v) video_codec="$OPTARG";;
            a) audio_codec="$OPTARG";;
            f) video_audio_shift="$OPTARG";;
            q) quality="$OPTARG";;
            b) bitrates="$OPTARG";;
            C) const="-C";;
            e) encrypt="-e";;
            k) kind="$OPTARG";;
            K) key_name="$OPTARG";;
            m) input_flags="$OPTARG";;
            n) output_flags="$OPTARG";;
            z) channel_name="$OPTARG";;
            T) flv_push_link="$OPTARG";;
            L) flv_pull_link="$OPTARG";;
            *) Usage;
        esac
done

cmd=$*
case "$cmd" in
    "e") 
        [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
        vi "$CHANNELS_FILE" && exit 0
    ;;
    "ee") 
        [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
        GetDefault
        [ -z "$d_sync_file" ] && echo -e "$error sync_file 未设置，请检查 !" && exit 1
        vi "$d_sync_file" && exit 0
    ;;
    "d")
        [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
        channels=""
        while IFS= read -r line 
        do
            if [[ $line == *\"pid\":* ]] 
            then
                pid=${line#*:}
                pid=${pid%,*}
                rand_pid=$pid
                while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$rand_pid"')' "$CHANNELS_FILE") ]] 
                do
                    true &
                    rand_pid=$!
                done
                line=${line//$pid/$rand_pid}
            fi
            channels="$channels$line"
        done < <(wget --no-check-certificate "$DEFAULT_DEMOS" -qO-)
        $JQ_FILE '.channels += '"$channels"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        echo && echo -e "$info 频道添加成功 !" && echo
        exit 0
    ;;
    "ffmpeg") 
        [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
        if grep -q '\--show-progress' < <(wget --help)
        then
            _PROGRESS_OPT="--show-progress"
        else
            _PROGRESS_OPT=""
        fi
        mkdir -p "$FFMPEG_MIRROR_ROOT/builds"
        mkdir -p "$FFMPEG_MIRROR_ROOT/releases"
        git_download=0
        release_download=0
        git_version_old=""
        release_version_old=""
        if [ -e "$FFMPEG_MIRROR_ROOT/index.html" ] 
        then
            while IFS= read -r line
            do
                if [[ $line == *"<th>"* ]] 
                then
                    if [[ $line == *"git"* ]] 
                    then
                        git_version_old=$line
                    else
                        release_version_old=$line
                    fi
                fi
            done < "$FFMPEG_MIRROR_ROOT/index.html"
        fi

        wget --no-check-certificate "https://www.johnvansickle.com/ffmpeg/index.html" -qO "$FFMPEG_MIRROR_ROOT/index.html"
        wget --no-check-certificate "https://www.johnvansickle.com/ffmpeg/style.css" -qO "$FFMPEG_MIRROR_ROOT/style.css"

        while IFS= read -r line
        do
            if [[ $line == *"<th>"* ]] 
            then
                if [[ $line == *"git"* ]] 
                then
                    git_version_new=$line
                    [ "$git_version_new" != "$git_version_old" ] && git_download=1
                else
                    release_version_new=$line
                    [ "$release_version_new" != "$release_version_old" ] && release_download=1
                fi
            fi

            if [[ $line == *"tar.xz"* ]]  
            then
                if [[ $line == *"git"* ]] && [ "$git_download" == 1 ]
                then
                    line=${line#*<td><a href=\"}
                    git_link=${line%%\" style*}
                    build_file_name=${git_link##*/}
                    wget --timeout=10 --tries=3 --no-check-certificate "$git_link" $_PROGRESS_OPT -qO "$FFMPEG_MIRROR_ROOT/builds/${build_file_name}_tmp"
                    if [ ! -s "$FFMPEG_MIRROR_ROOT/builds/${build_file_name}_tmp" ] 
                    then
                        echo && echo -e "$error 无法连接 github !" && exit 1
                    fi
                    mv "$FFMPEG_MIRROR_ROOT/builds/${build_file_name}_tmp" "$FFMPEG_MIRROR_ROOT/builds/${build_file_name}"
                else 
                    if [ "$release_download" == 1 ] 
                    then
                        line=${line#*<td><a href=\"}
                        release_link=${line%%\" style*}
                        release_file_name=${release_link##*/}
                        wget --timeout=10 --tries=3 --no-check-certificate "$release_link" $_PROGRESS_OPT -qO "$FFMPEG_MIRROR_ROOT/releases/${release_file_name}_tmp"
                        if [ ! -s "$FFMPEG_MIRROR_ROOT/builds/${release_file_name}_tmp" ] 
                        then
                            echo && echo -e "$error 无法连接 github !" && exit 1
                        fi
                        mv "$FFMPEG_MIRROR_ROOT/releases/${release_file_name}_tmp" "$FFMPEG_MIRROR_ROOT/releases/${release_file_name}"
                    fi
                fi
            fi

        done < "$FFMPEG_MIRROR_ROOT/index.html"

        #echo && echo "输入镜像网站链接(比如：$FFMPEG_MIRROR_LINK)"
        #read -p "(默认: 取消): " FFMPEG_LINK
        #[ -z "$FFMPEG_LINK" ] && echo "已取消..." && exit 1
        #sed -i "s+https://johnvansickle.com/ffmpeg/\(builds\|releases\)/\(.*\).tar.xz\"+$FFMPEG_LINK/\1/\2.tar.xz\"+g" "$FFMPEG_MIRROR_ROOT/index.html"

        sed -i "s+https://johnvansickle.com/ffmpeg/\(builds\|releases\)/\(.*\).tar.xz\"+\1/\2.tar.xz\"+g" "$FFMPEG_MIRROR_ROOT/index.html"

        jq_ver=$(curl --silent -m 10 "https://api.github.com/repos/stedolan/jq/releases/latest" |  grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
        if [ -n "$jq_ver" ]
        then
            mkdir -p "$FFMPEG_MIRROR_ROOT/$jq_ver/"
            wget --timeout=10 --tries=3 --no-check-certificate "https://github.com/stedolan/jq/releases/download/$jq_ver/jq-linux64" $_PROGRESS_OPT -qO "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux64_tmp"
            wget --timeout=10 --tries=3 --no-check-certificate "https://github.com/stedolan/jq/releases/download/$jq_ver/jq-linux32" $_PROGRESS_OPT -qO "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux32_tmp"
            if [ ! -s "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux64_tmp" ] || [ ! -s "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux32_tmp" ]
            then
                echo && echo -e "$error 无法连接 github !" && exit 1
            fi
            mv "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux64_tmp" "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux64"
            mv "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux32_tmp" "$FFMPEG_MIRROR_ROOT/$jq_ver/jq-linux32"
        fi

        wget --timeout=10 --tries=3 --no-check-certificate "https://github.com/winshining/nginx-http-flv-module/archive/master.zip" -qO "$FFMPEG_MIRROR_ROOT/nginx-http-flv-module.zip"
        exit 0
    ;;
    "ts") 
        [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
        TsMenu
        exit 0
    ;;
    "f") 
        [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
        kind="flv"
    ;;
    "l"|"ll") 
        flv_count=0
        chnls_channel_name=()
        chnls_stream_link=()
        while IFS= read -r flv_channel
        do
            flv_count=$((flv_count+1))
            map_channel_name=${flv_channel#*channel_name: }
            map_channel_name=${map_channel_name%, stream_link:*}
            map_stream_link=${flv_channel#*stream_link: }

            chnls_channel_name+=("$map_channel_name");
            chnls_stream_link+=("${map_stream_link:-''}");
        done < <($JQ_FILE -r '.channels | to_entries | map(select(.value.flv_status=="on")) | map("channel_name: \(.value.channel_name), stream_link: \(.value.stream_link)") | .[]' "$CHANNELS_FILE")

        if [ "$flv_count" -gt 0 ] 
        then

            echo && echo "FLV 频道" && echo

            for((i=0;i<flv_count;i++));
            do
                echo -e "  ${green}$((i+1)).$plain ${chnls_channel_name[i]} ${chnls_stream_link[i]}"
            done
        fi


        hls_count=0
        chnls_channel_name=()
        chnls_stream_link=()
        while IFS= read -r hls_channel
        do
            hls_count=$((hls_count+1))
            map_channel_name=${hls_channel#*channel_name: }
            map_channel_name=${map_channel_name%, stream_link:*}
            map_stream_link=${hls_channel#*stream_link: }

            chnls_channel_name+=("$map_channel_name");
            chnls_stream_link+=("${map_stream_link:-''}");
        done < <($JQ_FILE -r '.channels | to_entries | map(select(.value.status=="on")) | map("channel_name: \(.value.channel_name), stream_link: \(.value.stream_link)") | .[]' "$CHANNELS_FILE")

        if [ "$hls_count" -gt 0 ] 
        then
            echo && echo "HLS 频道" && echo

            for((i=0;i<hls_count;i++));
            do
                echo -e "  ${green}$((i+1)).$plain ${chnls_channel_name[i]} ${chnls_stream_link[i]}"
            done
        fi

        echo 

        if ls -A $LIVE_ROOT/* > /dev/null 2>&1 
        then
            for d in "$LIVE_ROOT"/*/ ; do
                ls "$d" -lght
            done
        fi

        if [ "$flv_count" == 0 ] && [ "$hls_count" == 0 ]
        then
            echo -e "$error 没有开启的频道 !" && echo && exit 1
        fi

        exit 0
    ;;
    "n"|"nginx")
        echo && echo -e "  Nginx 管理面板 $plain

  ${green}1.$plain 安装
  ${green}2.$plain 卸载
  ${green}3.$plain 升级
————————————
  ${green}4.$plain 开关
  ${green}5.$plain 重启
————————————
  ${green}6.$plain flv 配置
  ${green}7.$plain 日志切割
 " && echo
        read -p "请输入数字 [1-7]：" nginx_num
        case "$nginx_num" in
            1) 
                if [ -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 已经存在 !" && echo && exit 1
                fi

                echo && echo "因为是编译 nginx，耗时会很长，是否继续？[y/N]"
                read -p "(默认: N):" nginx_install_yn
                nginx_install_yn=${nginx_install_yn:-"N"}
                if [[ $nginx_install_yn == [Yy] ]] 
                then
                    InstallNginx
                    NginxConfigFlv
                    echo && echo -e "$info Nginx 安装完成" && echo
                else
                    echo && echo "已取消..." && echo && exit 1
                fi
            ;;
            2) UninstallNginx
            ;;
            3) 
                if [ ! -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 未安装 !" && echo && exit 1
                fi
                InstallNginx
                echo && echo -e "$info Nginx 升级完成" && echo
            ;;
            4) ToggleNginx
            ;;
            5) 
                RestartNginx
                echo && echo -e "$info Nginx 已重启" && echo
            ;;
            6) 
                if [ ! -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 未安装 !" && echo
                else
                    NginxConfigFlv
                    if [ -z "${conf:-}" ]
                    then
                        echo && echo -e "$error flv 配置已存在!" && echo
                    else
                        echo && echo -e "$info flv 配置已添加，是否重启 Nginx ？[Y/n]" && echo
                        read -p "(默认: Y):" restart_yn
                        restart_yn=${restart_yn:-"Y"}
                        if [[ $restart_yn == [Yy] ]] 
                        then
                            RestartNginx
                            echo && echo -e "$info Nginx 已重启" && echo
                        else
                            echo && echo "已取消..." && echo && exit 1
                        fi
                    fi
                fi
            ;;
            7) 
                if [ ! -e "$IPTV_ROOT" ] 
                then
                    echo && echo -e "$error 请先安装脚本 !" && echo && exit 1
                fi

                if crontab -l | grep -q "$LOGROTATE_CONFIG" 2> /dev/null
                then
                    echo && echo -e "$error 日志切割定时任务已存在 !" && echo
                else
                    LOGROTATE_FILE=$(command -v logrotate)

                    if [ ! -x "$LOGROTATE_FILE" ] 
                    then
                        echo && echo -e "$error 请先安装 logrotate !" && echo && exit 1
                    fi

                    logrotate=""

                    if [ -e "/usr/local/nginx" ] 
                    then
                        logrotate='
/usr/local/nginx/logs/*.log {
  daily
  missingok
  rotate 14
  compress
  delaycompress
  notifempty
  create 660 nobody root
  sharedscripts
  postrotate
    [ ! -f /usr/local/nginx/logs/nginx.pid ] || /bin/kill -USR1 $(< /usr/local/nginx/logs/nginx.pid)
  endscript
}
'
                    fi

                    logrotate="$logrotate
$IPTV_ROOT/*.log {
  daily
  missingok
  rotate 3
  compress
  nodelaycompress
  notifempty
  sharedscripts
}
"
                    printf '%s' "$logrotate" > "$LOGROTATE_CONFIG"

                    crontab -l > "$IPTV_ROOT/cron_tmp" 2> /dev/null || true
                    printf '%s\n' "0 0 * * * $LOGROTATE_FILE $LOGROTATE_CONFIG" >> "$IPTV_ROOT/cron_tmp"
                    crontab "$IPTV_ROOT/cron_tmp" > /dev/null
                    rm -rf "$IPTV_ROOT/cron_tmp"
                    echo && echo -e "$info 日志切割定时任务开启成功 !" && echo
                fi
            ;;
            *)
            echo -e "$error 请输入正确的数字 [1-7]"
            ;;
        esac
        exit 0
    ;;
    *)
    ;;
esac

if [ "$use_menu" == "1" ]
then
    [ ! -e "$SH_FILE" ] && wget --no-check-certificate "$SH_LINK" -qO "$SH_FILE" && chmod +x "$SH_FILE"
    if [ ! -s "$SH_FILE" ] 
    then
        echo -e "$error 无法连接到 Github ! 尝试备用链接..."
        wget --no-check-certificate "$SH_LINK_BACKUP" -qO "$SH_FILE" && chmod +x "$SH_FILE"
        if [ ! -s "$SH_FILE" ] 
        then
            echo -e "$error 无法连接备用链接!"
            exit 1
        fi
    fi
    [ ! -e "$V2_FILE" ] && ln -s "$SH_FILE" "$V2_FILE"
    echo -e "  IPTV 一键管理脚本（mpegts / flv => hls / flv 推流）${red}[v$sh_ver]$plain
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

 $tip 输入: tv 打开 HLS 面板, tv f 打开 FLV 面板" && echo
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
        6) EditChannelMenu
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
    stream_link=${stream_link:-}
    if [ -z "$stream_link" ]
    then
        Usage
    else
        CheckRelease
        FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
        FFMPEG="$FFMPEG_ROOT/ffmpeg"
        if [ ! -e "$FFMPEG" ]
        then
            echo && read -p "尚未安装,是否现在安装？[y/N] (默认: N): " install_yn
            install_yn=${install_yn:-"N"}
            if [[ "$install_yn" == [Yy] ]]
            then
                Install
            else
                echo "已取消..." && exit 1
            fi
        else
            GetDefault
            export FFMPEG
            output_dir_name=${output_dir_name:-"$(RandOutputDirName)"}
            output_dir_root="$LIVE_ROOT/$output_dir_name"
            playlist_name=${playlist_name:-"$(RandPlaylistName)"}
            export SEGMENT_DIRECTORY=${seg_dir_name:-}
            seg_name=${seg_name:-"$playlist_name"}
            seg_length=${seg_length:-"$d_seg_length"}
            seg_count=${seg_count:-"$d_seg_count"}
            export AUDIO_CODEC=${audio_codec:-"$d_audio_codec"}
            export VIDEO_CODEC=${video_codec:-"$d_video_codec"}
            
            video_audio_shift=${video_audio_shift:-}
            v_or_a=${video_audio_shift%_*}
            if [ "$v_or_a" == "v" ] 
            then
                video_shift=${video_audio_shift#*_}
            elif [ "$v_or_a" == "a" ] 
            then
                audio_shift=${video_audio_shift#*_}
            fi

            quality=${quality:-"$d_quality"}
            bitrates=${bitrates:-"$d_bitrates"}
            quality_command=""
            bitrates_command=""

            if [ -z "${kind:-}" ] && [ "${video_codec:-}" == "copy" ] && [ "${audio_codec:-}" == "copy" ]
            then
                quality=""
                bitrates=""
                const=""
                const_yn="no"
            else
                if [ -z "${const:-}" ]  
                then
                    if [ "$d_const_yn" == "yes" ] 
                    then
                        const="-C"
                        const_yn="yes"
                    else
                        const=""
                        const_yn="no"
                    fi
                else
                    const_yn="yes"
                fi

                if [ -n "${quality:-}" ] 
                then
                    const=""
                    const_yn="no"
                    quality_command="-q $quality"
                fi

                if [ -n "${bitrates:-}" ] 
                then
                    bitrates_command="-b $bitrates"
                fi
            fi

            if [ -z "${encrypt:-}" ]  
            then
                if [ "$d_encrypt_yn" == "yes" ] 
                then
                    encrypt="-e"
                    encrypt_yn="yes"
                else
                    encrypt=""
                    encrypt_yn="no"
                fi
            else
                encrypt_yn="yes"
            fi

            key_name=${key_name:-"$playlist_name"}

            if [[ ${stream_link:-} == *".m3u8"* ]] 
            then
                d_input_flags=${d_input_flags//-reconnect_at_eof 1/}
            elif [ "${stream_link:0:4}" == "rtmp" ] 
            then
                d_input_flags=${d_input_flags//-timeout 2000000000/}
                d_input_flags=${d_input_flags//-reconnect 1/}
                d_input_flags=${d_input_flags//-reconnect_at_eof 1/}
                d_input_flags=${d_input_flags//-reconnect_streamed 1/}
                d_input_flags=${d_input_flags//-reconnect_delay_max 2000/}
                lead=${d_input_flags%%[^[:blank:]]*}
                d_input_flags=${d_input_flags#${lead}}
            fi

            input_flags=${input_flags:-"$d_input_flags"}
            if [[ ${input_flags:0:1} == "'" ]] 
            then
                input_flags=${input_flags%\'}
                input_flags=${input_flags#\'}
            fi
            export FFMPEG_INPUT_FLAGS=$input_flags

            if [ "${output_flags:-}" == "omit" ] 
            then
                output_flags=""
            else
                output_flags=${d_input_flags}
            fi

            if [[ ${output_flags:0:1} == "'" ]] 
            then
                output_flags=${output_flags%\'}
                output_flags=${output_flags#\'}
            fi
            export FFMPEG_FLAGS=$output_flags

            channel_name=${channel_name:-"$playlist_name"}

            if [ -n "${kind:-}" ] 
            then
                if [ "$kind" == "flv" ] 
                then
                    if [ -z "${flv_push_link:-}" ] 
                    then
                        echo && echo -e "$error 未设置推流地址..." && echo && exit 1
                    else
                        flv_pull_link=${flv_pull_link:-}
                        from="command"
                        ( FlvStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null &
                    fi
                else
                    echo && echo -e "$error 暂不支持输出 $kind ..." && echo && exit 1
                fi
            elif [ -n "${video_audio_shift:-}" ] 
            then
                from="command"
                ( HlsStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null &
            else
                exec "$CREATOR_FILE" -l -i "$stream_link" -s "$seg_length" \
                    -o "$output_dir_root" -c "$seg_count" $bitrates_command \
                    -p "$playlist_name" -t "$seg_name" -K "$key_name" $quality_command \
                    "$const" "$encrypt" &
                pid=$!

                while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$pid"')' "$CHANNELS_FILE") ]] 
                do
                    kill -9 "$pid" >/dev/null 2>&1
                    exec "$CREATOR_FILE" -l -i "$stream_link" -s "$seg_length" \
                    -o "$output_dir_root" -c "$seg_count" $bitrates_command \
                    -p "$playlist_name" -t "$seg_name" -K "$key_name" $quality_command \
                    "$const" "$encrypt" &
                    pid=$!
                done

                $JQ_FILE '.channels += [
                    {
                        "pid":'"$pid"',
                        "status":"on",
                        "stream_link":"'"$stream_link"'",
                        "output_dir_name":"'"$output_dir_name"'",
                        "playlist_name":"'"$playlist_name"'",
                        "seg_dir_name":"'"$SEGMENT_DIRECTORY"'",
                        "seg_name":"'"$seg_name"'",
                        "seg_length":'"$seg_length"',
                        "seg_count":'"$seg_count"',
                        "video_codec":"'"$VIDEO_CODEC"'",
                        "audio_codec":"'"$AUDIO_CODEC"'",
                        "video_audio_shift":"",
                        "quality":"'"$quality"'",
                        "bitrates":"'"$bitrates"'",
                        "const":"'"$const_yn"'",
                        "encrypt":"'"$encrypt_yn"'",
                        "key_name":"'"$key_name"'",
                        "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                        "output_flags":"'"$FFMPEG_FLAGS"'",
                        "channel_name":"'"$channel_name"'",
                        "sync_pairs":"",
                        "flv_status":"off",
                        "flv_push_link":"",
                        "flv_pull_link":""
                    }
                ]' "$CHANNELS_FILE" > "$CHANNELS_TMP"
                mv "$CHANNELS_TMP" "$CHANNELS_FILE"
                action="add"
                SyncFile
            fi

            echo -e "$info 添加频道成功..." && echo
        fi
    fi
fi