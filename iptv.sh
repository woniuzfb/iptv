#!/bin/bash

set -euo pipefail

sh_ver="1.9.1"
SH_LINK="https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh"
SH_LINK_BACKUP="http://hbo.epub.fun/iptv.sh"
SH_FILE="/usr/local/bin/tv"
V2_FILE="/usr/local/bin/v2"
XC_FILE="/usr/local/bin/cx"
IPTV_ROOT="/usr/local/iptv"
IP_DENY="$IPTV_ROOT/ip.deny"
IP_PID="$IPTV_ROOT/ip.pid"
IP_LOG="$IPTV_ROOT/ip.log"
FFMPEG_LOG_ROOT="$IPTV_ROOT/ffmpeg"
FFMPEG_MIRROR_LINK="http://pngquant.com/ffmpeg"
FFMPEG_MIRROR_ROOT="$IPTV_ROOT/ffmpeg"
LIVE_ROOT="$IPTV_ROOT/live"
CREATOR_LINK="https://raw.githubusercontent.com/bentasker/HLS-Stream-Creator/master/HLS-Stream-Creator.sh"
CREATOR_LINK_BACKUP="http://hbo.epub.fun/HLS-Stream-Creator.sh"
CREATOR_FILE="$IPTV_ROOT/HLS-Stream-Creator.sh"
JQ_FILE="$IPTV_ROOT/jq"
CHANNELS_FILE="$IPTV_ROOT/channels.json"
DEFAULT_DEMOS="http://hbo.epub.fun/default.json"
DEFAULT_CHANNELS_LINK="http://hbo.epub.fun/channels.json"
LOCK_FILE="$IPTV_ROOT/lock"
MONITOR_PID="$IPTV_ROOT/monitor.pid"
MONITOR_LOG="$IPTV_ROOT/monitor.log"
LOGROTATE_CONFIG="$IPTV_ROOT/logrotate"
XTREAM_CODES="$IPTV_ROOT/xtream_codes"
XTREAM_CODES_LINK="http://hbo.epub.fun/xtream_codes"
green="\033[32m"
red="\033[31m"
plain="\033[0m"
info="${green}[信息]$plain"
error="${red}[错误]$plain"
tip="${green}[注意]$plain"

[ $EUID -ne 0 ] && echo -e "[$error] 当前账号非ROOT(或没有ROOT权限),无法继续操作,请使用$green sudo su $plain来获取临时ROOT权限（执行后会提示输入当前账号的密码）." && exit 1

JQ()
{
    file=$2
    local index=$3

    until mkdir -m 755 "$file.lockdir" 2>/dev/null
    do
        # MonitorError '%s 正忙' "$file"
        sleep 1
    done

    trap '
        [ -e "${file}_tmp" ] && rm -rf "${file}_tmp"
        [ -d "$file.lockdir" ] && rm -rf "$file.lockdir" 
    ' EXIT

    case $1 in
        "add") 
            if [ -n "${jq_path:-}" ] 
            then
                $JQ_FILE --argjson path "$jq_path" --argjson value "$3" 'getpath($path) += $value' "$file" > "${file}_tmp"
            else
                $JQ_FILE --arg index "$3" --argjson value "$4" '.[$index] += $value' "$file" > "${file}_tmp"
            fi
            mv "${file}_tmp" "$file"
        ;;
        "update") 
            $JQ_FILE "$3" "$file" > "${file}_tmp"
            mv "${file}_tmp" "$file"
        ;;
        "replace") 
            $JQ_FILE --arg index "$3" --argjson value "$4" '.[$index] = $value' "$file" > "${file}_tmp"
            mv "${file}_tmp" "$file"
        ;;
        "delete") 
            if [ -n "${jq_path:-}" ] 
            then
                $JQ_FILE --argjson path "$jq_path" 'del(getpath($path)[] | select(.'"$3"'=='"$4"'))' "$file" > "${file}_tmp"
            else
                $JQ_FILE --arg index "$3" 'del(.[$index][] | select(.pid=='"$4"'))' "$file" > "${file}_tmp"
            fi
            mv "${file}_tmp" "$file"
        ;;
    esac

    rm -rf "$file.lockdir"
}

SyncFile()
{
    case $action in
        "skip")
            action=""
            return
        ;;      
        "start"|"stop")
            if [ -z "${d_version:-}" ] 
            then
                GetDefault
            fi
        ;;
        "add")
            chnl_pid=$pid
            GetChannelInfo
        ;;
        *)
            echo -e "$error $action ???" && exit 1
        ;;
    esac

    chnl_sync_file=${chnl_sync_file:-$d_sync_file}
    chnl_sync_index=${chnl_sync_index:-$d_sync_index}
    chnl_sync_pairs=${chnl_sync_pairs:-$d_sync_pairs}

    if [ "$chnl_sync_yn" == "yes" ] && [ -n "$chnl_sync_file" ] && [ -n "$chnl_sync_index" ] && [ -n "$chnl_sync_pairs" ]
    then
        IFS=" " read -ra chnl_sync_files <<< "$chnl_sync_file"
        IFS=" " read -ra chnl_sync_indexs <<< "$chnl_sync_index"
        chnl_pid_key=${chnl_sync_pairs%%:pid*}
        chnl_pid_key=${chnl_pid_key##*,}
        sync_count=${#chnl_sync_files[@]}
        [ "${#chnl_sync_indexs[@]}" -lt "$sync_count" ] && sync_count=${#chnl_sync_indexs[@]}

        for((i=0;i<sync_count;i++));
        do
            if [ ! -s "${chnl_sync_files[i]}" ] 
            then
                $JQ_FILE -n --arg name "$(RandStr)" \
                '{
                    "ret": 0,
                    "data": [
                        {
                            "name": $name
                        }
                    ]
                }' > "${chnl_sync_files[i]}"
            fi
            jq_index=""
            jq_path="["
            while IFS=':' read -ra index_arr
            do
                for a in "${index_arr[@]}"
                do
                    [ "$jq_path" != "[" ] && jq_path="$jq_path,"
                    case $a in
                        '') 
                            echo -e "$error sync设置错误..." && exit 1
                        ;;
                        *[!0-9]*)
                            jq_index="$jq_index.$a"
                            jq_path="$jq_path\"$a\""
                        ;;
                        *) 
                            jq_index="${jq_index}[$a]"
                            jq_path="${jq_path}$a"
                        ;;
                    esac
                done
            done <<< "${chnl_sync_indexs[i]}"

            jq_path="$jq_path]"

            if [ "$action" == "stop" ]
            then
                if [ "$sh_ver" != "$d_version" ] 
                then
                    if [[ -n $($JQ_FILE "${jq_index}[]|select(.$chnl_pid_key==\"$chnl_pid\")" "${chnl_sync_files[i]}") ]] 
                    then
                        JQ delete "${chnl_sync_files[i]}" "$chnl_pid_key" "\"$chnl_pid\""
                    fi
                else
                    if [[ -n $($JQ_FILE "${jq_index}[]|select(.$chnl_pid_key==$chnl_pid)" "${chnl_sync_files[i]}") ]] 
                    then
                        JQ delete "${chnl_sync_files[i]}" "$chnl_pid_key" "$chnl_pid"
                    fi
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

                                    if [ -n "$jq_channel_edit" ] 
                                    then
                                        jq_channel_edit="$jq_channel_edit|"
                                    fi

                                    if [[ $value == *[!0-9]* ]] 
                                    then
                                        jq_channel_edit="$jq_channel_edit(${jq_index}[]|select(.$chnl_pid_key==$chnl_pid)|.$key)=\"$value\""
                                    else
                                        jq_channel_edit="$jq_channel_edit(${jq_index}[]|select(.$chnl_pid_key==$chnl_pid)|.$key)=$value"
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
                                        value_last=$value
                                    else 
                                        value=${!value}
                                        if [ -n "$jq_channel_edit" ] 
                                        then
                                            jq_channel_edit="$jq_channel_edit|"
                                        fi

                                        if [[ $value == *[!0-9]* ]] 
                                        then
                                            jq_channel_edit="$jq_channel_edit(${jq_index}[]|select(.$chnl_pid_key==$chnl_pid)|.$key)=\"$value\""
                                        else
                                            jq_channel_edit="$jq_channel_edit(${jq_index}[]|select(.$chnl_pid_key==$chnl_pid)|.$key)=$value"
                                        fi
                                    fi
                                fi

                                if [ "$jq_channel_add" != "[{" ] 
                                then
                                    jq_channel_add="$jq_channel_add,"
                                fi

                                if [[ $value == *[!0-9]* ]] 
                                then
                                    jq_channel_add="$jq_channel_add\"$key\":\"$value\""
                                else
                                    jq_channel_add="$jq_channel_add\"$key\":$value"
                                fi
                            ;;
                        esac
                    done
                done <<< "$chnl_sync_pairs"
                if [ "$action" == "add" ] || [[ -z $($JQ_FILE "${jq_index}[]|select(.$chnl_pid_key==$chnl_pid)" "${chnl_sync_files[i]}") ]]
                then
                    JQ add "${chnl_sync_files[i]}" "$jq_channel_add}]"
                else
                    JQ update "${chnl_sync_files[i]}" "$jq_channel_edit|(${jq_index}[]|select(.$chnl_pid_key==$chnl_pid)|.$chnl_pid_key)=$value_last"
                fi
            fi
        done

        echo -e "$info sync 执行成功..."
    fi
    action=""
    jq_path=""
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
        [ ! -e "$FFMPEG_PACKAGE_FILE" ] && echo -e "$error ffmpeg 下载失败 !" && exit 1
        tar -xJf "$FFMPEG_PACKAGE_FILE" -C "$IPTV_ROOT" && rm -rf "${FFMPEG_PACKAGE_FILE:-notfound}"
        FFMPEG=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
        [ ! -e "$FFMPEG" ] && echo -e "$error ffmpeg 解压失败 !" && exit 1
        export FFMPEG
        echo -e "$info FFmpeg 安装成功..."
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
        jq_ver=$(curl --silent -m 10 "$FFMPEG_MIRROR_LINK/jq.json" |  grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
        if [ -n "$jq_ver" ]
        then
            wget --no-check-certificate "$FFMPEG_MIRROR_LINK/$jq_ver/jq-linux$release_bit" $_PROGRESS_OPT -qO "$JQ_FILE"
        fi
        [ ! -e "$JQ_FILE" ] && echo -e "$error 下载JQ解析器失败, 请重试 !" && exit 1
        chmod +x "$JQ_FILE"
        echo -e "$info JQ解析器 安装完成..."
    else
        echo -e "$info JQ解析器 已安装..."
    fi
}

Install()
{
    echo && echo -e "$info 检查依赖，耗时可能会很长..."
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
            echo -e "$error 无法连接 Github ! 尝试备用链接..."
            wget --no-check-certificate "$CREATOR_LINK_BACKUP" -qO "$CREATOR_FILE" && chmod +x "$CREATOR_FILE"
            if [ ! -s "$CREATOR_FILE" ] 
            then
                echo -e "$error 无法连接备用链接!"
                rm -rf "${IPTV_ROOT:-notfound}"
                exit 1
            fi
        fi
        echo -e "$info 脚本就绪..."
        InstallFfmpeg
        InstallJq

        default=$(
        $JQ_FILE -n --arg playlist_name '' --arg seg_dir_name '' \
            --arg seg_name '' --arg seg_length 6 \
            --arg seg_count 6 --arg video_codec "libx264" \
            --arg audio_codec "aac" --arg video_audio_shift '' \
            --arg quality '' --arg bitrates "900-1280x720" \
            --arg const "no" --arg encrypt "no" \
            --arg keyinfo_name '' --arg key_name '' \
            --arg input_flags "-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -timeout 2000000000 -y -nostats -nostdin -hide_banner -loglevel fatal" \
            --arg output_flags "-g 25 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main" --arg sync "yes" \
            --arg sync_file '' --arg sync_index "data:0:channels" \
            --arg sync_pairs "chnl_name:channel_name,chnl_id:output_dir_name,chnl_pid:pid,chnl_cat=港澳台,url=http://xxx.com/live" --arg schedule_file '' \
            --arg flv_delay_seconds 20 --arg flv_restart_nums 20 \
            --arg hls_delay_seconds 120 --arg hls_min_bitrates 500 \
            --arg hls_max_seg_size 5 --arg hls_restart_nums 20 \
            --arg anti_ddos_port 80 --arg anti_ddos_seconds 120 \
            --arg anti_ddos_level 6 --arg anti_leech "no" \
            --arg anti_leech_restart_nums 3 --arg anti_leech_restart_flv_changes "yes" \
            --arg anti_leech_restart_hls_changes "yes" --arg version "$sh_ver" \
            '{
                playlist_name: $playlist_name,
                seg_dir_name: $seg_dir_name,
                seg_name: $seg_name,
                seg_length: $seg_length | tonumber,
                seg_count: $seg_count | tonumber,
                video_codec: $video_codec,
                audio_codec: $audio_codec,
                video_audio_shift: $video_audio_shift,
                quality: $quality,
                bitrates: $bitrates,
                const: $const,
                encrypt: $encrypt,
                keyinfo_name: $keyinfo_name,
                key_name: $key_name,
                input_flags: $input_flags,
                output_flags: $output_flags,
                sync: $sync,
                sync_file: $sync_file,
                sync_index: $sync_index,
                sync_pairs: $sync_pairs,
                schedule_file: $schedule_file,
                flv_delay_seconds: $flv_delay_seconds | tonumber,
                flv_restart_nums: $flv_restart_nums | tonumber,
                hls_delay_seconds: $hls_delay_seconds | tonumber,
                hls_min_bitrates: $hls_min_bitrates | tonumber,
                hls_max_seg_size: $hls_max_seg_size | tonumber,
                hls_restart_nums: $hls_restart_nums | tonumber,
                anti_ddos_port: $anti_ddos_port | tonumber,
                anti_ddos_seconds: $anti_ddos_seconds | tonumber,
                anti_ddos_level: $anti_ddos_level | tonumber,
                anti_leech: $anti_leech,
                anti_leech_restart_nums: $anti_leech_restart_nums | tonumber,
                anti_leech_restart_flv_changes: $anti_leech_restart_flv_changes,
                anti_leech_restart_hls_changes: $anti_leech_restart_hls_changes,
                version: $version
            }'
        )

        $JQ_FILE -n --argjson default "$default" \
        '{
            default: $default,
            channels: []
        }' > "$CHANNELS_FILE"

        echo -e "$info 安装完成..."
        ln -sf "$IPTV_ROOT"/ffmpeg-git-*/ff* /usr/local/bin/
    fi
}

Uninstall()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    CheckRelease
    echo "确定要 卸载此脚本以及产生的全部文件？[y/N]"
    read -p "(默认: N): " uninstall_yn
    uninstall_yn=${uninstall_yn:-N}
    if [[ $uninstall_yn == [Yy] ]]
    then
        MonitorStop
        if crontab -l | grep -q "$LOGROTATE_CONFIG" 2> /dev/null
        then
            crontab -l > "$IPTV_ROOT/cron_tmp" 2> /dev/null || true
            sed -i "#$LOGROTATE_CONFIG#d" "$IPTV_ROOT/cron_tmp"
            crontab "$IPTV_ROOT/cron_tmp" > /dev/null
            rm -rf "$IPTV_ROOT/cron_tmp"
            echo && echo -e "$info 已停止 logrotate" && echo
        fi
        while IFS= read -r chnl_pid
        do
            GetChannelInfo
            if [ "$chnl_flv_status" == "on" ] 
            then
                kind="flv"
                StopChannel
            elif [ "$chnl_status" == "on" ]
            then
                kind=""
                StopChannel
            fi
        done < <($JQ_FILE '.channels[].pid' $CHANNELS_FILE)
        rm -rf "${IPTV_ROOT:-notfound}"
        echo && echo -e "$info 卸载完成 !" && echo
    else
        echo && echo -e "$info 卸载已取消..." && echo
    fi
}

Update()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    if [ -s "$MONITOR_PID" ] 
    then
        PID=$(< "$MONITOR_PID")
        if kill -0 "$PID" 2> /dev/null 
        then
            echo && echo -e "$info 需要先关闭监控，是否继续? [Y/n]"
            read -p "(默认: Y): " stop_monitor_yn
            stop_monitor_yn=${stop_monitor_yn:-Y}
            if [[ $stop_monitor_yn == [Yy] ]] 
            then
                MonitorStop
            else
                echo && echo "已取消..." && echo && exit 1
            fi
        fi
    fi

    while IFS= read -r line 
    do
        if [[ $line == *"built on "* ]] 
        then
            line=${line#*built on }
            git_date=${line%<*}
            break
        fi
    done < <(wget --no-check-certificate "$FFMPEG_MIRROR_LINK/index.html" -qO-)

    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    if [[ ${FFMPEG_ROOT##*/} == *"${git_date:-20200101}"* ]] 
    then
        echo && echo -e "$info FFmpeg 已经是最新，是否重装? [y/N]"
        read -p "(默认: N): " reinstall_ffmpeg_yn
        reinstall_ffmpeg_yn=${reinstall_ffmpeg_yn:-N}
    else
        reinstall_ffmpeg_yn="Y"
    fi

    echo && echo -e "$info 升级中..."
    CheckRelease
    if grep -q '\--show-progress' < <(wget --help)
    then
        _PROGRESS_OPT="--show-progress"
    else
        _PROGRESS_OPT=""
    fi

    if [[ ${reinstall_ffmpeg_yn:-N} == [Yy] ]] 
    then
        rm -rf "$IPTV_ROOT"/ffmpeg-git-*/
        echo -e "$info 更新 FFmpeg..."
        InstallFfmpeg
    fi

    rm -rf "${JQ_FILE:-notfound}"
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
        rm -rf "${LOCK_FILE:-notfound}"
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

    rm -rf ${CREATOR_FILE:-notfound}
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

GetDefault()
{
    while IFS= read -r d
    do
        d_playlist_name=${d#*playlist_name: }
        d_playlist_name=${d_playlist_name%, seg_dir_name:*}
        d_playlist_name_text=${d_playlist_name:-随机名称}
        d_seg_dir_name=${d#*, seg_dir_name: }
        d_seg_dir_name=${d_seg_dir_name%, seg_name:*}
        d_seg_dir_name_text=${d_seg_dir_name:-不使用}
        d_seg_name=${d#*, seg_name: }
        d_seg_name=${d_seg_name%, seg_length:*}
        d_seg_name_text=${d_seg_name:-跟m3u8名称相同}
        d_seg_length=${d#*, seg_length: }
        d_seg_length=${d_seg_length%, seg_count:*}
        d_seg_count=${d#*, seg_count: }
        d_seg_count=${d_seg_count%, video_codec:*}
        d_video_codec=${d#*, video_codec: }
        d_video_codec=${d_video_codec%, audio_codec:*}
        d_audio_codec=${d#*, audio_codec: }
        d_audio_codec=${d_audio_codec%, video_audio_shift:*}
        d_video_audio_shift=${d#*, video_audio_shift: }
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
        d_quality=${d#*, quality: }
        d_quality=${d_quality%, bitrates:*}
        d_bitrates=${d#*, bitrates: }
        d_bitrates=${d_bitrates%, const:*}
        d_const_yn=${d#*, const: }
        d_const_yn=${d_const_yn%, encrypt:*}
        if [ "$d_const_yn" == "no" ] 
        then
            d_const_text="N"
        else
            d_const_text="Y"
        fi
        d_encrypt_yn=${d#*, encrypt: }
        d_encrypt_yn=${d_encrypt_yn%, key_name:*}
        d_encrypt_yn=${d_encrypt_yn%, keyinfo_name:*}
        d_keyinfo_name=${d#*, keyinfo_name: }
        d_keyinfo_name=${d_keyinfo_name%, key_name:*}
        [ "$d_keyinfo_name" == null ] && d_keyinfo_name=""
        d_key_name=${d#*, key_name: }
        d_key_name=${d_key_name%, input_flags:*}
        if [ "$d_encrypt_yn" == "no" ] 
        then
            d_encrypt_text="N"
        else
            d_encrypt_text="Y"
        fi
        d_input_flags=${d#*, input_flags: }
        d_input_flags=${d_input_flags%, output_flags:*}
        d_output_flags=${d#*, output_flags: }
        d_output_flags=${d_output_flags%, sync:*}
        d_sync_yn=${d#*, sync: }
        d_sync_yn=${d_sync_yn%, sync_file:*}
        [ "$d_sync_yn" == null ] && d_sync_yn="yes"
        if [ "$d_sync_yn" == "no" ] 
        then
            d_sync_text="N"
        else
            d_sync_text="Y"
        fi
        d_sync_file=${d#*, sync_file: }
        d_sync_file=${d_sync_file%, sync_index:*}
        d_sync_index=${d#*, sync_index: }
        d_sync_index=${d_sync_index%, sync_pairs:*}
        d_sync_pairs=${d#*, sync_pairs: }
        d_sync_pairs=${d_sync_pairs%, schedule_file:*}
        d_schedule_file=${d#*, schedule_file: }
        d_schedule_file=${d_schedule_file%, flv_delay_seconds:*}
        d_flv_delay_seconds=${d#*, flv_delay_seconds: }
        d_flv_delay_seconds=${d_flv_delay_seconds%, flv_restart_nums:*}
        [ "$d_flv_delay_seconds" == null ] && d_flv_delay_seconds=20
        d_flv_delay_seconds=${d_flv_delay_seconds:-20}
        d_flv_restart_nums=${d#*, flv_restart_nums: }
        d_flv_restart_nums=${d_flv_restart_nums%, hls_delay_seconds:*}
        [ "$d_flv_restart_nums" == null ] && d_flv_restart_nums=20
        d_flv_restart_nums=${d_flv_restart_nums:-20}
        d_hls_delay_seconds=${d#*, hls_delay_seconds: }
        d_hls_delay_seconds=${d_hls_delay_seconds%, hls_min_bitrates:*}
        [ "$d_hls_delay_seconds" == null ] && d_hls_delay_seconds=120
        d_hls_delay_seconds=${d_hls_delay_seconds:-120}
        d_hls_min_bitrates=${d#*, hls_min_bitrates: }
        d_hls_min_bitrates=${d_hls_min_bitrates%, hls_max_seg_size:*}
        d_hls_max_seg_size=${d#*, hls_max_seg_size: }
        d_hls_max_seg_size=${d_hls_max_seg_size%, hls_restart_nums:*}
        [ "$d_hls_min_bitrates" == null ] && d_hls_min_bitrates=500
        d_hls_min_bitrates=${d_hls_min_bitrates:-500}
        [ "$d_hls_max_seg_size" == null ] && d_hls_max_seg_size=5
        d_hls_max_seg_size=${d_hls_max_seg_size:-5}
        d_hls_restart_nums=${d#*, hls_restart_nums: }
        d_hls_restart_nums=${d_hls_restart_nums%, anti_ddos_port:*}
        [ "$d_hls_restart_nums" == null ] && d_hls_restart_nums=20
        d_hls_restart_nums=${d_hls_restart_nums:-20}
        d_anti_ddos_port=${d#*, anti_ddos_port: }
        d_anti_ddos_port=${d_anti_ddos_port%, anti_ddos_seconds:*}
        [ "$d_anti_ddos_port" == null ] && d_anti_ddos_port=80
        d_anti_ddos_port=${d_anti_ddos_port:-80}
        d_anti_ddos_seconds=${d#*, anti_ddos_seconds: }
        d_anti_ddos_seconds=${d_anti_ddos_seconds%, anti_ddos_level:*}
        [ "$d_anti_ddos_seconds" == null ] && d_anti_ddos_seconds=120
        d_anti_ddos_seconds=${d_anti_ddos_seconds:-120}
        d_anti_ddos_level=${d#*, anti_ddos_level: }
        d_anti_ddos_level=${d_anti_ddos_level%, anti_leech:*}
        [ "$d_anti_ddos_level" == null ] && d_anti_ddos_level=6
        d_anti_ddos_level=${d_anti_ddos_level:-6}
        d_anti_leech_yn=${d#*, anti_leech: }
        d_anti_leech_yn=${d_anti_leech_yn%, anti_leech_restart_nums:*}
        [ "$d_anti_leech_yn" == null ] && d_anti_leech_yn="no"
        d_anti_leech_yn=${d_anti_leech_yn:-no}
        if [ "$d_anti_leech_yn" == "no" ] 
        then
            d_anti_leech="N"
        else
            d_anti_leech="Y"
        fi
        d_anti_leech_restart_nums=${d#*, anti_leech_restart_nums: }
        d_anti_leech_restart_nums=${d_anti_leech_restart_nums%, anti_leech_restart_flv_changes:*}
        [ "$d_anti_leech_restart_nums" == null ] && d_anti_leech_restart_nums=0
        d_anti_leech_restart_nums=${d_anti_leech_restart_nums:-0}
        d_anti_leech_restart_flv_changes_yn=${d#*, anti_leech_restart_flv_changes: }
        d_anti_leech_restart_flv_changes_yn=${d_anti_leech_restart_flv_changes_yn%, anti_leech_restart_hls_changes:*}
        [ "$d_anti_leech_restart_flv_changes_yn" == null ] && d_anti_leech_restart_flv_changes_yn="no"
        d_anti_leech_restart_flv_changes_yn=${d_anti_leech_restart_flv_changes_yn:-no}
        if [ "$d_anti_leech_restart_flv_changes_yn" == "no" ] 
        then
            d_anti_leech_restart_flv_changes="N"
        else
            d_anti_leech_restart_flv_changes="Y"
        fi
        d_anti_leech_restart_hls_changes_yn=${d#*, anti_leech_restart_hls_changes: }
        d_anti_leech_restart_hls_changes_yn=${d_anti_leech_restart_hls_changes_yn%, version:*}
        [ "$d_anti_leech_restart_hls_changes_yn" == null ] && d_anti_leech_restart_hls_changes_yn="no"
        d_anti_leech_restart_hls_changes_yn=${d_anti_leech_restart_hls_changes_yn:-no}
        if [ "$d_anti_leech_restart_hls_changes_yn" == "no" ] 
        then
            d_anti_leech_restart_hls_changes="N"
        else
            d_anti_leech_restart_hls_changes="Y"
        fi
        d_version=${d#*, version: }
        d_version=${d_version%\"}
    done < <($JQ_FILE 'to_entries | map(select(.key=="default")) | map("playlist_name: \(.value.playlist_name), seg_dir_name: \(.value.seg_dir_name), seg_name: \(.value.seg_name), seg_length: \(.value.seg_length), seg_count: \(.value.seg_count), video_codec: \(.value.video_codec), audio_codec: \(.value.audio_codec), video_audio_shift: \(.value.video_audio_shift), quality: \(.value.quality), bitrates: \(.value.bitrates), const: \(.value.const), encrypt: \(.value.encrypt), keyinfo_name: \(.value.keyinfo_name), key_name: \(.value.key_name), input_flags: \(.value.input_flags), output_flags: \(.value.output_flags), sync: \(.value.sync), sync_file: \(.value.sync_file), sync_index: \(.value.sync_index), sync_pairs: \(.value.sync_pairs), schedule_file: \(.value.schedule_file), flv_delay_seconds: \(.value.flv_delay_seconds), flv_restart_nums: \(.value.flv_restart_nums), hls_delay_seconds: \(.value.hls_delay_seconds), hls_min_bitrates: \(.value.hls_min_bitrates), hls_max_seg_size: \(.value.hls_max_seg_size), hls_restart_nums: \(.value.hls_restart_nums), anti_ddos_port: \(.value.anti_ddos_port), anti_ddos_seconds: \(.value.anti_ddos_seconds), anti_ddos_level: \(.value.anti_ddos_level), anti_leech: \(.value.anti_leech), anti_leech_restart_nums: \(.value.anti_leech_restart_nums), anti_leech_restart_flv_changes: \(.value.anti_leech_restart_flv_changes), anti_leech_restart_hls_changes: \(.value.anti_leech_restart_hls_changes), version: \(.value.version)") | .[]' "$CHANNELS_FILE")
    #done < <($JQ_FILE '.default | to_entries | map([.key,.value]|join(": ")) | join(", ")' "$CHANNELS_FILE")
}

GetChannelsInfo()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1

    chnls_count=0
    chnls_pid=()
    chnls_status=()
    chnls_stream_link=()
    chnls_stream_links=()
    chnls_live=()
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
    chnls_keyinfo_name=()
    chnls_key_name=()
    chnls_input_flags=()
    chnls_output_flags=()
    chnls_channel_name=()
    chnls_sync=()
    chnls_sync_file=()
    chnls_sync_index=()
    chnls_sync_pairs=()
    chnls_flv_status=()
    chnls_flv_push_link=()
    chnls_flv_pull_link=()
    
    while IFS= read -r channel
    do
        chnls_count=$((chnls_count+1))
        map_pid=${channel#*pid: }
        map_pid=${map_pid%, status:*}
        map_status=${channel#*, status: }
        map_status=${map_status%, stream_link:*}
        map_stream_link=${channel#*, stream_link: }
        map_stream_link=${map_stream_link%, live:*}
        IFS=" " read -ra map_stream_links <<< "$map_stream_link"
        map_live=${channel#*, live: }
        map_live=${map_live%, output_dir_name:*}
        [ "$map_live" == null ] && map_live="yes"
        map_output_dir_name=${channel#*, output_dir_name: }
        map_output_dir_name=${map_output_dir_name%, playlist_name:*}
        map_playlist_name=${channel#*, playlist_name: }
        map_playlist_name=${map_playlist_name%, seg_dir_name:*}
        map_seg_dir_name=${channel#*, seg_dir_name: }
        map_seg_dir_name=${map_seg_dir_name%, seg_name:*}
        map_seg_name=${channel#*, seg_name: }
        map_seg_name=${map_seg_name%, seg_length:*}
        map_seg_length=${channel#*, seg_length: }
        map_seg_length=${map_seg_length%, seg_count:*}
        map_seg_count=${channel#*, seg_count: }
        map_seg_count=${map_seg_count%, video_codec:*}
        map_video_codec=${channel#*, video_codec: }
        map_video_codec=${map_video_codec%, audio_codec:*}
        map_audio_codec=${channel#*, audio_codec: }
        map_audio_codec=${map_audio_codec%, video_audio_shift:*}
        map_video_audio_shift=${channel#*, video_audio_shift: }
        map_video_audio_shift=${map_video_audio_shift%, quality:*}
        [ "$map_video_audio_shift" == null ] && map_video_audio_shift=""
        map_quality=${channel#*, quality: }
        map_quality=${map_quality%, bitrates:*}
        map_bitrates=${channel#*, bitrates: }
        map_bitrates=${map_bitrates%, const:*}
        map_const=${channel#*, const: }
        map_const=${map_const%, encrypt:*}
        map_encrypt=${channel#*, encrypt: }
        map_encrypt=${map_encrypt%, keyinfo_name:*}
        map_keyinfo_name=${channel#*, keyinfo_name: }
        map_keyinfo_name=${map_keyinfo_name%, key_name:*}
        [ "$map_keyinfo_name" == null ] && map_keyinfo_name=$(RandStr)
        map_key_name=${channel#*, key_name: }
        map_key_name=${map_key_name%, input_flags:*}
        map_input_flags=${channel#*, input_flags: }
        map_input_flags=${map_input_flags%, output_flags:*}
        map_output_flags=${channel#*, output_flags: }
        map_output_flags=${map_output_flags%, channel_name:*}
        map_channel_name=${channel#*, channel_name: }
        map_channel_name=${map_channel_name%, sync:*}
        map_sync=${channel#*, sync: }
        map_sync=${map_sync%, sync_file:*}
        [ "$map_sync" == null ] && map_sync="yes"
        map_sync_file=${channel#*, sync_file: }
        map_sync_file=${map_sync_file%, sync_index:*}
        [ "$map_sync_file" == null ] && map_sync_file=""
        map_sync_index=${channel#*, sync_index: }
        map_sync_index=${map_sync_index%, sync_pairs:*}
        [ "$map_sync_index" == null ] && map_sync_index=""
        map_sync_pairs=${channel#*, sync_pairs: }
        map_sync_pairs=${map_sync_pairs%, flv_status:*}
        [ "$map_sync_pairs" == null ] && map_sync_pairs=""
        map_flv_status=${channel#*, flv_status: }
        map_flv_status=${map_flv_status%, flv_push_link:*}
        [ "$map_flv_status" == null ] && map_flv_status="off"
        map_flv_push_link=${channel#*, flv_push_link: }
        map_flv_push_link=${map_flv_push_link%, flv_pull_link:*}
        [ "$map_flv_push_link" == null ] && map_flv_push_link=""
        map_flv_pull_link=${channel#*, flv_pull_link: }
        map_flv_pull_link=${map_flv_pull_link%\"}
        [ "$map_flv_pull_link" == null ] && map_flv_pull_link=""

        chnls_pid+=("$map_pid")
        chnls_status+=("$map_status")
        chnls_stream_link+=("${map_stream_links[0]}")
        chnls_stream_links+=("$map_stream_link")
        chnls_live+=("$map_live")
        chnls_output_dir_name+=("$map_output_dir_name")
        chnls_playlist_name+=("$map_playlist_name")
        chnls_seg_dir_name+=("$map_seg_dir_name")
        chnls_seg_name+=("$map_seg_name")
        chnls_seg_length+=("$map_seg_length")
        chnls_seg_count+=("$map_seg_count")
        chnls_video_codec+=("$map_video_codec")
        chnls_audio_codec+=("$map_audio_codec")
        chnls_video_audio_shift+=("$map_video_audio_shift")
        chnls_quality+=("$map_quality")
        chnls_bitrates+=("$map_bitrates")
        chnls_const+=("$map_const")
        chnls_encrypt+=("$map_encrypt")
        chnls_keyinfo_name+=("$map_keyinfo_name")
        chnls_key_name+=("$map_key_name")
        chnls_input_flags+=("$map_input_flags")
        chnls_output_flags+=("$map_output_flags")
        chnls_channel_name+=("$map_channel_name")
        chnls_sync+=("$map_sync")
        chnls_sync_file+=("$map_sync_file")
        chnls_sync_index+=("$map_sync_index")
        chnls_sync_pairs+=("$map_sync_pairs")
        chnls_flv_status+=("$map_flv_status")
        chnls_flv_push_link+=("$map_flv_push_link")
        chnls_flv_pull_link+=("$map_flv_pull_link")
        
    done < <($JQ_FILE '.channels | to_entries | map("pid: \(.value.pid), status: \(.value.status), stream_link: \(.value.stream_link), live: \(.value.live), output_dir_name: \(.value.output_dir_name), playlist_name: \(.value.playlist_name), seg_dir_name: \(.value.seg_dir_name), seg_name: \(.value.seg_name), seg_length: \(.value.seg_length), seg_count: \(.value.seg_count), video_codec: \(.value.video_codec), audio_codec: \(.value.audio_codec), video_audio_shift: \(.value.video_audio_shift), quality: \(.value.quality), bitrates: \(.value.bitrates), const: \(.value.const), encrypt: \(.value.encrypt), keyinfo_name: \(.value.keyinfo_name), key_name: \(.value.key_name), input_flags: \(.value.input_flags), output_flags: \(.value.output_flags), channel_name: \(.value.channel_name), sync: \(.value.sync), sync_file: \(.value.sync_file), sync_index: \(.value.sync_index), sync_pairs: \(.value.sync_pairs), flv_status: \(.value.flv_status), flv_push_link: \(.value.flv_push_link), flv_pull_link: \(.value.flv_pull_link)") | .[]' "$CHANNELS_FILE")

    return 0
}

ListChannels()
{
    GetChannelsInfo
    if [ "$chnls_count" == 0 ]
    then
        echo && echo -e "$error 没有发现 频道，请检查 !" && echo && exit 1
    fi
    chnls_list=""
    for((index = 0; index < chnls_count; index++)); do
        chnls_output_dir_root="$LIVE_ROOT/${chnls_output_dir_name[index]}"

        v_or_a=${chnls_video_audio_shift[index]%_*}
        if [ "$v_or_a" == "v" ] 
        then
            chnls_video_shift=${chnls_video_audio_shift[index]#*_}
            chnls_video_audio_shift_text="画面延迟 $chnls_video_shift 秒"
        elif [ "$v_or_a" == "a" ] 
        then
            chnls_audio_shift=${chnls_video_audio_shift[index]#*_}
            chnls_video_audio_shift_text="声音延迟 $chnls_audio_shift 秒"
        else
            chnls_video_audio_shift_text="不设置"
        fi

        if [ "${chnls_const[index]}" == "no" ] 
        then
            chnls_const_index_text=" 固定频率:否"
        else
            chnls_const_index_text=" 固定频率:是"
        fi

        chnls_quality_text=""
        chnls_bitrates_text=""
        chnls_playlist_file_text=""

        if [ -n "${chnls_bitrates[index]}" ] 
        then
            while IFS= read -r chnls_br
            do
                if [[ $chnls_br == *"-"* ]]
                then
                    chnls_br_a=${chnls_br%-*}
                    chnls_br_b=" 分辨率: ${chnls_br#*-}"
                    chnls_quality_text="${chnls_quality_text}[ -maxrate ${chnls_br_a}k -bufsize ${chnls_br_a}k${chnls_br_b} ] "
                    chnls_bitrates_text="${chnls_bitrates_text}[ 比特率 ${chnls_br_a}k${chnls_br_b}${chnls_const_index_text} ] "
                    chnls_playlist_file_text="$chnls_playlist_file_text$chnls_output_dir_root/${chnls_playlist_name[index]}_$chnls_br_a.m3u8 "
                elif [[ $chnls_br == *"x"* ]] 
                then
                    chnls_quality_text="${chnls_quality_text}[ 分辨率: $chnls_br ] "
                    chnls_bitrates_text="${chnls_bitrates_text}[ 分辨率: $chnls_br${chnls_const_index_text} ] "
                    chnls_playlist_file_text="$chnls_playlist_file_text$chnls_output_dir_root/${chnls_playlist_name[index]}.m3u8 "
                else
                    chnls_quality_text="${chnls_quality_text}[ -maxrate ${chnls_br}k -bufsize ${chnls_br}k ] "
                    chnls_bitrates_text="${chnls_bitrates_text}[ 比特率 ${chnls_br}k${chnls_const_index_text} ] "
                    chnls_playlist_file_text="$chnls_playlist_file_text$chnls_output_dir_root/${chnls_playlist_name[index]}_$chnls_br.m3u8 "
                fi
            done <<< ${chnls_bitrates[index]//,/$'\n'}
        else
            chnls_playlist_file_text="$chnls_playlist_file_text$chnls_output_dir_root/${chnls_playlist_name[index]}.m3u8 "
        fi

        if [ -z "${kind:-}" ] 
        then
            if [ "${chnls_status[index]}" == "on" ]
            then
                if kill -0 "${chnls_pid[index]}" 2> /dev/null 
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
                    done <<< $(pgrep -P "${chnls_pid[index]}")

                    if [ "$working" == 1 ] || [ "${chnls_live[index]}" == "no" ]
                    then
                        chnls_status_text=$green"开启"$plain
                    else
                        chnls_status_text=$red"关闭"$plain
                        JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"${chnls_pid[index]}"')|.status)="off"'
                        chnl_pid=${chnls_pid[index]}
                        GetChannelInfo
                        StopChannel
                    fi
                elif [ "${chnls_live[index]}" == "yes" ] 
                then
                    chnls_status_text=$red"关闭"$plain
                    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"${chnls_pid[index]}"')|.status)="off"'
                    chnl_pid=${chnls_pid[index]}
                    GetChannelInfo
                    StopChannel
                fi
            else
                chnls_status_text=$red"关闭"$plain
            fi
        fi

        if [ -n "${chnls_quality[index]}" ] 
        then
            chnls_video_quality_text="crf值${chnls_quality[index]} ${chnls_quality_text:-不设置}"
        else
            chnls_video_quality_text="比特率值 ${chnls_bitrates_text:-不设置}"
        fi

        if [ -z "${kind:-}" ] && [ "${chnls_video_codec[index]}" == "copy" ] && [ "${chnls_audio_codec[index]}" == "copy" ]  
        then
            chnls_video_quality_text="原画"
        fi

        if [ "$index" -lt 9 ] 
        then
            blank=" "
        else
            blank=""
        fi

        if [ -z "${kind:-}" ] 
        then
            chnls_list=$chnls_list"# $green$((index+1))$plain $blank进程ID: $green${chnls_pid[index]}$plain 状态: $chnls_status_text 频道名称: $green${chnls_channel_name[index]}$plain\n     编码: $green${chnls_video_codec[index]}:${chnls_audio_codec[index]}$plain 延迟: $green$chnls_video_audio_shift_text$plain 视频质量: $green$chnls_video_quality_text$plain\n     源: ${chnls_stream_link[index]}\n     m3u8位置: $chnls_playlist_file_text\n\n"
        elif [ "$kind" == "flv" ] 
        then
            if [ "${chnls_flv_status[index]}" == "on" ] 
            then
                chnls_flv_status_text=$green"开启"$plain
            else
                chnls_flv_status_text=$red"关闭"$plain
            fi
            chnls_list=$chnls_list"# $green$((index+1))$plain $blank进程ID: $green${chnls_pid[index]}$plain 状态: $chnls_flv_status_text 频道名称: $green${chnls_channel_name[index]}$plain\n     编码: $green${chnls_video_codec[index]}:${chnls_audio_codec[index]}$plain 延迟: $green$chnls_video_audio_shift_text$plain 视频质量: $green$chnls_video_quality_text$plain\n     flv推流地址: ${chnls_flv_push_link[index]:-无}\n     flv拉流地址: ${chnls_flv_pull_link[index]:-无}\n\n"
        fi
        
    done
    echo && echo -e "=== 频道总数 $green $chnls_count $plain" && echo
    echo -e "$chnls_list"
}

GetChannelInfo()
{
    if [ -z "${d_version:-}" ] 
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
        chnl_status=${channel#*, status: }
        chnl_status=${chnl_status%, stream_link:*}
        chnl_stream_links=${channel#*, stream_link: }
        chnl_stream_links=${chnl_stream_links%, live:*}
        chnl_stream_link=${chnl_stream_links%% *}
        chnl_live_yn=${channel#*, live: }
        chnl_live_yn=${chnl_live_yn%, output_dir_name:*}
        if [ "$chnl_live_yn" == "no" ]
        then
            chnl_live=""
            chnl_live_text="$red否$plain"
        else
            chnl_live="-l"
            chnl_live_text="$green是$plain"
        fi
        chnl_output_dir_name=${channel#*, output_dir_name: }
        chnl_output_dir_name=${chnl_output_dir_name%, playlist_name:*}
        chnl_output_dir_root="$LIVE_ROOT/$chnl_output_dir_name"
        chnl_playlist_name=${channel#*, playlist_name: }
        chnl_playlist_name=${chnl_playlist_name%, seg_dir_name:*}
        chnl_seg_dir_name=${channel#*, seg_dir_name: }
        chnl_seg_dir_name=${chnl_seg_dir_name%, seg_name:*}
        chnl_seg_name=${channel#*, seg_name: }
        chnl_seg_name=${chnl_seg_name%, seg_length:*}
        chnl_seg_length=${channel#*, seg_length: }
        chnl_seg_length=${chnl_seg_length%, seg_count:*}
        chnl_seg_count=${channel#*, seg_count: }
        chnl_seg_count=${chnl_seg_count%, video_codec:*}
        chnl_video_codec=${channel#*, video_codec: }
        chnl_video_codec=${chnl_video_codec%, audio_codec:*}
        chnl_audio_codec=${channel#*, audio_codec: }
        chnl_audio_codec=${chnl_audio_codec%, video_audio_shift:*}
        chnl_video_audio_shift=${channel#*, video_audio_shift: }
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
        chnl_quality=${channel#*, quality: }
        chnl_quality=${chnl_quality%, bitrates:*}
        chnl_bitrates=${channel#*, bitrates: }
        chnl_bitrates=${chnl_bitrates%, const:*}
        chnl_const_yn=${channel#*, const: }
        chnl_const_yn=${chnl_const_yn%, encrypt:*}
        if [ "$chnl_const_yn" == "no" ]
        then
            chnl_const=""
            chnl_const_text=" 固定频率:否"
        else
            chnl_const="-C"
            chnl_const_text=" 固定频率:是"
        fi
        chnl_encrypt_yn=${channel#*, encrypt: }
        chnl_encrypt_yn=${chnl_encrypt_yn%, keyinfo_name:*}
        chnl_keyinfo_name=${channel#*, keyinfo_name: }
        chnl_keyinfo_name=${chnl_keyinfo_name%, key_name:*}
        chnl_key_name=${channel#*, key_name: }
        chnl_key_name=${chnl_key_name%, input_flags:*}
        if [ "$chnl_encrypt_yn" == "no" ]
        then
            chnl_encrypt=""
            chnl_encrypt_text=$red"否"$plain
            chnl_key_name_text=$red$chnl_key_name$plain
        else
            chnl_encrypt="-e"
            chnl_encrypt_text=$green"是"$plain
            chnl_key_name_text=$green$chnl_key_name$plain
        fi
        chnl_input_flags=${channel#*, input_flags: }
        chnl_input_flags=${chnl_input_flags%, output_flags:*}
        chnl_output_flags=${channel#*, output_flags: }
        chnl_output_flags=${chnl_output_flags%, channel_name:*}
        chnl_channel_name=${channel#*, channel_name: }
        chnl_channel_name=${chnl_channel_name%, sync:*}
        chnl_sync_yn=${channel#*, sync: }
        chnl_sync_yn=${chnl_sync_yn%, sync_file:*}
        if [ "$chnl_sync_yn" == "no" ]
        then
            chnl_sync_text="$red禁用$plain"
        else
            chnl_sync_text="$green启用$plain"
        fi
        chnl_sync_file=${channel#*, sync_file: }
        chnl_sync_file=${chnl_sync_file%, sync_index:*}
        chnl_sync_index=${channel#*, sync_index: }
        chnl_sync_index=${chnl_sync_index%, sync_pairs:*}
        chnl_sync_pairs=${channel#*, sync_pairs: }
        chnl_sync_pairs=${chnl_sync_pairs%, flv_status:*}
        chnl_flv_status=${channel#*, flv_status: }
        chnl_flv_status=${chnl_flv_status%, flv_push_link:*}
        chnl_flv_push_link=${channel#*, flv_push_link: }
        chnl_flv_push_link=${chnl_flv_push_link%, flv_pull_link:*}
        chnl_flv_pull_link=${channel#*, flv_pull_link: }
        chnl_flv_pull_link=${chnl_flv_pull_link%\"}

        if [ -z "${monitor:-}" ] 
        then
            if [ "$chnl_status" == "on" ]
            then
                chnl_status_text=$green"开启"$plain
            else
                chnl_status_text=$red"关闭"$plain
            fi

            chnl_seg_dir_name_text=${chnl_seg_dir_name:-不使用}
            chnl_seg_length_text=$chnl_seg_length"s"

            chnl_crf_text=""
            chnl_nocrf_text=""
            chnl_playlist_file_text=""

            if [ -n "$chnl_bitrates" ] 
            then
                while IFS= read -r chnl_br
                do
                    if [[ $chnl_br == *"-"* ]]
                    then
                        chnl_br_a=${chnl_br%-*}
                        chnl_br_b=" 分辨率: ${chnl_br#*-}"
                        chnl_crf_text="${chnl_crf_text}[ -maxrate ${chnl_br_a}k -bufsize ${chnl_br_a}k${chnl_br_b} ] "
                        chnl_nocrf_text="${chnl_nocrf_text}[ 比特率 ${chnl_br_a}k${chnl_br_b}${chnl_const_text} ] "
                        chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}_$chnl_br_a.m3u8$plain "
                    elif [[ $chnl_br == *"x"* ]] 
                    then
                        chnl_crf_text="${chnl_crf_text}[ 分辨率: $chnl_br ] "
                        chnl_nocrf_text="${chnl_nocrf_text}[ 分辨率: $chnl_br${chnl_const_text} ] "
                        chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}.m3u8$plain "
                    else
                        chnl_crf_text="${chnl_crf_text}[ -maxrate ${chnl_br}k -bufsize ${chnl_br}k ] "
                        chnl_nocrf_text="${chnl_nocrf_text}[ 比特率 ${chnl_br}k${chnl_const_text} ] "
                        chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}_$chnl_br.m3u8$plain "
                    fi
                done <<< ${chnl_bitrates//,/$'\n'}
            else
                chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}.m3u8$plain "
            fi

            if [ "$chnl_sync_yn" == "yes" ]
            then
                sync_file=${chnl_sync_file:-$d_sync_file}
                sync_index=${chnl_sync_index:-$d_sync_index}
                sync_pairs=${chnl_sync_pairs:-$d_sync_pairs}
                if [ -n "$sync_file" ] && [ -n "$sync_index" ] && [ -n "$sync_pairs" ] && [[ $sync_pairs == *"=http"* ]]
                then
                    chnl_playlist_link=${sync_pairs#*=http}
                    chnl_playlist_link=${chnl_playlist_link%%,*}
                    chnl_playlist_link="http$chnl_playlist_link/$chnl_output_dir_name/${chnl_playlist_name}_master.m3u8"
                    chnl_playlist_link_text="$green$chnl_playlist_link$plain"
                else
                    chnl_playlist_link_text="$red请先设置 sync$plain"
                fi
            else
                chnl_playlist_link_text="$red请先启用 sync$plain"
            fi

            if [ -n "$chnl_quality" ] 
            then
                chnl_video_quality_text="crf值$chnl_quality ${chnl_crf_text:-不设置}"
            else
                chnl_video_quality_text="比特率值 ${chnl_nocrf_text:-不设置}"
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
    done < <($JQ_FILE '.channels | to_entries | map(select('"$select"')) | map("pid: \(.value.pid), status: \(.value.status), stream_link: \(.value.stream_link), live: \(.value.live), output_dir_name: \(.value.output_dir_name), playlist_name: \(.value.playlist_name), seg_dir_name: \(.value.seg_dir_name), seg_name: \(.value.seg_name), seg_length: \(.value.seg_length), seg_count: \(.value.seg_count), video_codec: \(.value.video_codec), audio_codec: \(.value.audio_codec), video_audio_shift: \(.value.video_audio_shift), quality: \(.value.quality), bitrates: \(.value.bitrates), const: \(.value.const), encrypt: \(.value.encrypt), keyinfo_name: \(.value.keyinfo_name), key_name: \(.value.key_name), input_flags: \(.value.input_flags), output_flags: \(.value.output_flags), channel_name: \(.value.channel_name), sync: \(.value.sync), sync_file: \(.value.sync_file), sync_index: \(.value.sync_index), sync_pairs: \(.value.sync_pairs), flv_status: \(.value.flv_status), flv_push_link: \(.value.flv_push_link), flv_pull_link: \(.value.flv_pull_link)") | .[]' "$CHANNELS_FILE")

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
        if [ -z "$chnl_live" ] 
        then
            echo -e " 加密\t    : $chnl_encrypt_text"
            if [ -n "$chnl_encrypt" ] 
            then
                echo -e " key名称    : $chnl_key_name_text"
            fi
        fi
    elif [ "$kind" == "flv" ] 
    then
        echo -e " 状态\t    : $chnl_flv_status_text"
        echo -e " 推流地址   : $green${chnl_flv_push_link:-无}$plain"
        echo -e " 拉流地址   : $green${chnl_flv_pull_link:-无}$plain"
    fi
    
    echo -e " 直播源\t    : $green${chnl_stream_links// /, }$plain"
    echo -e " 无限时长直播: $chnl_live_text"
    echo -e " 视频编码   : $green$chnl_video_codec$plain"
    echo -e " 音频编码   : $green$chnl_audio_codec$plain"
    echo -e " 视频质量   : $green$chnl_video_quality_text$plain"
    echo -e " 延迟\t    : $green$chnl_video_audio_shift_text$plain"

    echo -e " input flags    : $green${chnl_input_flags:-不设置}$plain"
    echo -e " output flags   : $green${chnl_output_flags:-不设置}$plain"
    echo -e " sync           : $chnl_sync_text"
    if [ -n "$chnl_sync_file" ] 
    then
        echo -e " sync_file      : $green${chnl_sync_file// /, }$plain"
    fi
    if [ -n "$chnl_sync_index" ] 
    then
        echo -e " sync_index     : $green${chnl_sync_index// /, }$plain"
    fi
    if [ -n "$chnl_sync_pairs" ] 
    then
        echo -e " sync_pairs     : $green$chnl_sync_pairs$plain"
    fi
    echo
}

InputChannelsIndex()
{
    echo -e "请输入频道的序号 "
    echo -e "$tip 多个序号用空格分隔 比如: 5 7 9-11 " && echo
    while read -p "(默认: 取消): " chnls_index_input
    do
        chnls_pid_chosen=()
        IFS=" " read -ra chnls_index <<< "$chnls_index_input"
        [ -z "$chnls_index_input" ] && echo && echo "已取消..." && echo && exit 1

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
                elif [[ $chnl_index_start -gt 0 ]] && [[ $chnl_index_end -le $chnls_count ]] && [[ $chnl_index_end -gt $chnl_index_start ]] 
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
    echo -e "$tip 可以是视频路径, 可以输入不同链接地址(监控按顺序尝试使用), 用空格分隔" && echo
    read -p "(默认: 取消): " stream_links_input
    [ -z "$stream_links_input" ] && echo && echo "已取消..." && echo && exit 1
    IFS=" " read -ra stream_links <<< "$stream_links_input"
    stream_link=${stream_links[0]}
    echo && echo -e "	直播源: $green $stream_link $plain" && echo
}

SetIsHls()
{
    echo && echo "是否是 HLS 链接? [y/N]"
    echo -e "$tip 如果直播链接重定向至 .m3u8 地址，请选择 Y" && echo
    read -p "(默认: N): " is_hls_yn
    is_hls_yn=${is_hls_yn:-N}
    if [[ $is_hls_yn == [Yy] ]]
    then
        is_hls=1
        is_hls_text="是"
    else
        is_hls=0
        is_hls_text="否"
    fi
    echo && echo -e "	HLS 链接: $green $is_hls_text $plain" && echo
}

SetLive()
{
    echo && echo "是否是无限时长直播源? [Y/n]"
    if [ -z "${kind:-}" ] 
    then
        echo -e "$tip 选择 Y 则无法使用加密功能，选择 n 则无法设置切割段数目且无法监控" && echo
    else
        echo -e "$tip 选择 n 则无法监控" && echo
    fi
    read -p "(默认: Y): " live_yn
    live_yn=${live_yn:-Y}
    if [[ $live_yn == [Yy] ]]
    then
        live="-l"
        live_yn="yes"
        live_text="是"
    else
        live=""
        live_yn="no"
        live_text="否"
    fi
    echo && echo -e "	无限时长: $green $live_text $plain" && echo
}

SetOutputDirName()
{
    echo "请输入频道输出目录名称"
    echo -e "$tip 是名称不是路径" && echo
    while read -p "(默认: 随机名称): " output_dir_name
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
    read -p "(默认: $d_playlist_name_text): " playlist_name
    if [ -z "$playlist_name" ] 
    then
        playlist_name=${d_playlist_name:-$(RandPlaylistName)}
    fi
    echo && echo -e "	m3u8名称: $green $playlist_name $plain" && echo
}

SetSegDirName()
{
    echo "请输入段所在子目录名称"
    read -p "(默认: $d_seg_dir_name_text): " seg_dir_name
    if [ -z "$seg_dir_name" ] 
    then
        seg_dir_name=$d_seg_dir_name
    fi
    echo && echo -e "	段子目录名: $green ${seg_dir_name:-不使用} $plain" && echo
}

SetSegName()
{
    echo "请输入段名称"
    read -p "(默认: $d_seg_name_text): " seg_name
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
    while read -p "(默认: $d_seg_length): " seg_length
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
    echo -e "$tip 如果填0就是无限" && echo
    while read -p "(默认: $d_seg_count): " seg_count
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
    read -p "(默认: $d_video_codec): " video_codec
    video_codec=${video_codec:-$d_video_codec}
    echo && echo -e "	视频编码: $green $video_codec $plain" && echo
}

SetAudioCodec()
{
    echo "请输入音频编码(不需要转码时输入 copy)"
    read -p "(默认: $d_audio_codec): " audio_codec
    audio_codec=${audio_codec:-$d_audio_codec}
    echo && echo -e "	音频编码: $green $audio_codec $plain" && echo
}

SetQuality()
{
    echo -e "请输入输出视频质量[0-63]"
    echo -e "$tip 改变CRF，数字越大越视频质量越差，如果设置CRF则无法用比特率控制视频质量"
    while read -p "(默认: ${d_quality:-不设置}): " quality
    do
        case "$quality" in
            "")
                quality=$d_quality
                break
            ;;
            *[!0-9]*)
                echo -e "$error 请输入正确的数字(大于等于0,小于等于63)或直接回车 "
            ;;
            *)
                if [ "$quality" -ge 0 ] && [ "$quality" -lt 63 ]
                then
                    break
                else
                    echo -e "$error 请输入正确的数字(大于等于0,小于等于63)或直接回车 "
                fi
            ;;
        esac
    done
    echo && echo -e "	crf视频质量: $green ${quality:-不设置} $plain" && echo
}

SetBitrates()
{
    echo "请输入比特率(kb/s), 可以输入 omit 省略此选项"

    if [ -z "$quality" ] 
    then
        echo -e "$tip 用于指定输出视频比特率，同时可以指定输出的分辨率"
    else
        echo -e "$tip 用于 -maxrate 和 -bufsize，同时可以指定输出的分辨率"
    fi
    
    if [ -z "${kind:-}" ] 
    then
        echo -e "$tip 多个比特率用逗号分隔(生成自适应码流)
    同时可以指定输出的分辨率(比如：600-600x400,900-1280x720)"
    fi

    echo && read -p "(默认: ${d_bitrates:-不设置}): " bitrates
    bitrates=${bitrates:-$d_bitrates}
    if [ "$bitrates" == "omit" ] 
    then
        bitrates=""
    fi
    echo && echo -e "	比特率: $green ${bitrates:-不设置} $plain" && echo
}

SetConst()
{
    echo "是否使用固定码率[y/N]"
    read -p "(默认: $d_const_text): " const_yn
    const_yn=${const_yn:-$d_const_text}
    if [[ $const_yn == [Yy] ]]
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
    read -p "(默认: $d_encrypt_text): " encrypt_yn
    encrypt_yn=${encrypt_yn:-$d_encrypt_text}
    if [[ $encrypt_yn == [Yy] ]]
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

SetKeyInfoName()
{
    echo "请输入 keyinfo 名称"
    read -p "(默认: ${d_keyinfo_name:-随机}): " keyinfo_name
    keyinfo_name=${keyinfo_name:-$d_keyinfo_name}
    keyinfo_name=${keyinfo_name:-$(RandStr)}
    echo && echo -e "	keyinfo 名称: $green $keyinfo_name $plain" && echo 
}

SetKeyName()
{
    echo "请输入 key 名称"
    read -p "(默认: ${d_key_name:-随机}): " key_name
    key_name=${key_name:-$d_key_name}
    key_name=${key_name:-$(RandStr)}
    echo && echo -e "	key 名称: $green $key_name $plain" && echo 
}

SetInputFlags()
{
    if [[ ${stream_link:-} == *".m3u8"* ]] || [ "${is_hls:-0}" -eq 1 ]
    then
        d_input_flags=${d_input_flags//-reconnect_at_eof 1/}
    elif [ "${stream_link:0:4}" == "rtmp" ] || [ "${is_local:-0}" -eq 1 ]
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
    read -p "(默认: $d_input_flags): " input_flags
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
    read -p "(默认: ${d_output_flags:-不设置}): " output_flags
    output_flags=${output_flags:-$d_output_flags}
    if [ "$output_flags" == "omit" ] 
    then
        output_flags=""
    fi
    echo && echo -e "	output flags: $green ${output_flags:-不设置} $plain" && echo 
}

SetVideoAudioShift()
{
    echo && echo -e "画面或声音延迟？
    ${green}1.$plain 设置 画面延迟
    ${green}2.$plain 设置 声音延迟
    ${green}3.$plain 不设置
    " && echo
    while read -p "(默认: $d_video_audio_shift_text): " video_audio_shift_num
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
    read -p "(默认: 跟m3u8名称相同): " channel_name
    if [ -z "${playlist_name:-}" ] 
    then
        playlist_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').playlist_name' "$CHANNELS_FILE")
    fi
    channel_name=${channel_name:-$playlist_name}
    echo && echo -e "	频道名称: $green $channel_name $plain" && echo
}

SetSync()
{
    echo "是否启用 sync ? [Y/n]"
    read -p "(默认: $d_sync_text): " sync_yn
    sync_yn=${sync_yn:-$d_sync_text}
    if [[ $sync_yn == [Yy] ]]
    then
        sync_yn="yes"
        sync_text="$green启用$plain"
    else
        sync_yn="no"
        sync_text="$red禁用$plain"
    fi
    echo && echo -e "	sync: $sync_text" && echo
}

SetSyncFile()
{
    echo "设置单独的 sync_file"
    echo -e "$tip 多个文件用空格分隔" && echo
    read -p "(默认: ${d_sync_file:-不设置}): " sync_file
    sync_file_text=${sync_file:-$d_sync_file}
    echo && echo -e "	单独的 sync_file: $green ${sync_file_text:-不设置} $plain" && echo
}

SetSyncIndex()
{
    echo "设置单独的 sync_index"
    echo -e "$tip 多个 sync_index 用空格分隔" && echo
    read -p "(默认: ${d_sync_index:-不设置}): " sync_index
    sync_index_text=${sync_index:-$d_sync_index}
    echo && echo -e "	单独的 sync_index: $green ${sync_index_text:-不设置} $plain" && echo
}

SetSyncPairs()
{
    echo "设置单独的 sync_pairs"
    read -p "(默认: ${d_sync_pairs:-不设置}): " sync_pairs
    sync_pairs_text=${sync_pairs:-$d_sync_pairs}
    echo && echo -e "	单独的 sync_pairs: $green ${sync_pairs_text:-不设置} $plain" && echo
}

SetFlvPushLink()
{
    echo && echo "请输入推流地址(比如 rtmp://127.0.0.1/flv/xxx )"
    while read -p "(默认: 取消): " flv_push_link
    do
        [ -z "$flv_push_link" ] && echo && echo "已取消..." && echo && exit 1
        if [[ -z $($JQ_FILE '.channels[] | select(.flv_push_link=="'"$flv_push_link"'")' "$CHANNELS_FILE") ]]
        then
            break
        else
            echo -e "$error 推流地址已存在！请重新输入" && echo
        fi
    done
    echo && echo -e "	推流地址: $green $flv_push_link $plain" && echo
}

SetFlvPullLink()
{
    echo && echo "请输入拉流(播放)地址, 如 http://domain.com/flv?app=flv&stream=xxx"
    echo -e "$tip 监控会验证此链接来确定是否重启频道，如果不确定可以先留空" && echo
    read -p "(默认: 不设置): " flv_pull_link
    echo && echo -e "	拉流地址: $green ${flv_pull_link:-不设置} $plain" && echo
}

FlvStreamCreatorWithShift()
{
    trap '' HUP INT QUIT TERM
    trap 'MonitorError $LINENO' ERR
    pid="$BASHPID"
    mkdir -p "/tmp/flv.lockdir"
    mkdir -m 755 "/tmp/flv.lockdir/$pid"
    if [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$pid"')' "$CHANNELS_FILE") ]] 
    then
        true &
        rand_pid=$!
        while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$rand_pid"')' "$CHANNELS_FILE") ]] 
        do
            true &
            rand_pid=$!
        done
        JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.pid)='"$rand_pid"''
    fi
    case $from in
        "AddChannel") 
            new_channel=$(
            $JQ_FILE -n --arg pid "$pid" --arg status "off" \
                --arg stream_link "$stream_links_input" --arg live "$live_yn" \
                --arg output_dir_name "$output_dir_name" --arg playlist_name "$playlist_name" \
                --arg seg_dir_name "$SEGMENT_DIRECTORY" --arg seg_name "$seg_name" \
                --arg seg_length "$seg_length" --arg seg_count "$seg_count" \
                --arg video_codec "$VIDEO_CODEC" --arg audio_codec "$AUDIO_CODEC" \
                --arg video_audio_shift "$video_audio_shift" --arg quality "$quality" \
                --arg bitrates "$bitrates" --arg const "$const_yn" \
                --arg encrypt "$encrypt_yn" --arg keyinfo_name "$keyinfo_name" \
                --arg key_name "$key_name" \
                --arg input_flags "$FFMPEG_INPUT_FLAGS" --arg output_flags "$FFMPEG_FLAGS" \
                --arg channel_name "$channel_name" --arg sync "$sync_yn" \
                --arg sync_file "$sync_file" --arg sync_index "$sync_index" \
                --arg sync_pairs "$sync_pairs" --arg flv_status "on" \
                --arg flv_push_link "$flv_push_link" --arg flv_pull_link "$flv_pull_link" \
                '{
                    pid: $pid | tonumber,
                    status: $status,
                    stream_link: $stream_link,
                    live: $live,
                    output_dir_name: $output_dir_name,
                    playlist_name: $playlist_name,
                    seg_dir_name: $seg_dir_name,
                    seg_name: $seg_name,
                    seg_length: $seg_length | tonumber,
                    seg_count: $seg_count | tonumber,
                    video_codec: $video_codec,
                    audio_codec: $audio_codec,
                    video_audio_shift: $video_audio_shift,
                    quality: $quality,
                    bitrates: $bitrates,
                    const: $const,
                    encrypt: $encrypt,
                    keyinfo_name: $keyinfo_name,
                    key_name: $key_name,
                    input_flags: $input_flags,
                    output_flags: $output_flags,
                    channel_name: $channel_name,
                    sync: $sync,
                    sync_file: $sync_file,
                    sync_index: $sync_index,
                    sync_pairs: $sync_pairs,
                    flv_status: $flv_status,
                    flv_push_link: $flv_push_link,
                    flv_pull_link: $flv_pull_link
                }'
            )
            JQ add "$CHANNELS_FILE" channels "[$new_channel]"

            action="add"
            SyncFile

            resolution=""

            if [ -z "$quality" ]
            then
                if [ -n "$bitrates" ] 
                then
                    bitrates=${bitrates%%,*}
                    if [[ $bitrates == *"-"* ]] 
                    then
                        resolution=${bitrates#*-}
                        resolution="-vf scale=${resolution//x/:}"
                        bitrates=${bitrates%-*}
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                    elif [[ $bitrates == *"x"* ]] 
                    then
                        resolution=$bitrates
                        resolution="-vf scale=${resolution//x/:}"
                    else
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                    fi
                fi
            elif [ -n "$bitrates" ] 
            then
                bitrates=${bitrates%%,*}
                if [[ $bitrates == *"-"* ]] 
                then
                    resolution=${bitrates#*-}
                    resolution="-vf scale=${resolution//x/:}"
                    bitrates=${bitrates%-*}
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                elif [[ $bitrates == *"x"* ]] 
                then
                    resolution=$bitrates
                    resolution="-vf scale=${resolution//x/:}"
                    quality_command="-crf $quality"
                else
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                fi
            else
                quality_command="-crf $quality"
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

            if [[ $FFMPEG_FLAGS == *"-vf "* ]] && [ -n "$resolution" ]
            then
                FFMPEG_FLAGS_A=${FFMPEG_FLAGS%-vf *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS#*-vf }
                FFMPEG_FLAGS_C=${FFMPEG_FLAGS_B%% *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS_B#* }
                FFMPEG_FLAGS="$FFMPEG_FLAGS_A $FFMPEG_FLAGS_B"
                resolution="-vf $FFMPEG_FLAGS_C,${resolution#*-vf }"
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command \
            -y -vcodec "$VIDEO_CODEC" -acodec "$AUDIO_CODEC" $quality_command $bitrates_command $resolution \
            $FFMPEG_FLAGS -f flv "$flv_push_link" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.flv_status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $channel_name flv 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            rm -rf "/tmp/flv.lockdir/$pid"
            kill -9 "$chnl_pid"
        ;;
        "StartChannel") 
            new_pid=$pid
            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'
            |(.channels[]|select(.pid=='"$new_pid"')|.flv_status)="on"
            |(.channels[]|select(.pid=='"$new_pid"')|.stream_link)="'"$chnl_stream_links"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.flv_push_link)="'"$chnl_flv_push_link"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.flv_pull_link)="'"$chnl_flv_pull_link"'"'
            action="start"
            SyncFile

            resolution=""

            if [ -z "$chnl_quality" ]
            then
                if [ -n "$chnl_bitrates" ] 
                then
                    chnl_bitrates=${chnl_bitrates%%,*}
                    if [[ $chnl_bitrates == *"-"* ]] 
                    then
                        resolution=${chnl_bitrates#*-}
                        resolution="-vf scale=${resolution//x/:}"
                        chnl_bitrates=${chnl_bitrates%-*}
                        if [ -n "$chnl_const" ] 
                        then
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k -bufsize ${chnl_bitrates}k -minrate ${chnl_bitrates}k -maxrate ${chnl_bitrates}k"
                        else
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k"
                        fi
                    elif [[ $chnl_bitrates == *"x"* ]] 
                    then
                        resolution=$chnl_bitrates
                        resolution="-vf scale=${resolution//x/:}"
                    else
                        if [ -n "$chnl_const" ] 
                        then
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k -bufsize ${chnl_bitrates}k -minrate ${chnl_bitrates}k -maxrate ${chnl_bitrates}k"
                        else
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k"
                        fi
                    fi
                fi
            elif [ -n "$chnl_bitrates" ] 
            then
                chnl_bitrates=${chnl_bitrates%%,*}
                if [[ $chnl_bitrates == *"-"* ]] 
                then
                    resolution=${chnl_bitrates#*-}
                    resolution="-vf scale=${resolution//x/:}"
                    chnl_bitrates=${chnl_bitrates%-*}
                    chnl_quality_command="-crf $chnl_quality -maxrate ${chnl_bitrates}k -bufsize ${chnl_bitrates}k"
                    if [ "$chnl_video_codec" == "libx265" ]
                    then
                    chnl_quality_command="$chnl_quality_command -x265-params --vbv-maxrate ${chnl_bitrates}k --vbv-bufsize ${chnl_bitrates}k"
                    fi
                elif [[ $chnl_bitrates == *"x"* ]] 
                then
                    resolution=$chnl_bitrates
                    resolution="-vf scale=${resolution//x/:}"
                    chnl_quality_command="-crf $chnl_quality"
                else
                    chnl_quality_command="-crf $chnl_quality -maxrate ${chnl_bitrates}k -bufsize ${chnl_bitrates}k"
                    if [ "$chnl_video_codec" == "libx265" ]
                    then
                    chnl_quality_command="$chnl_quality_command -x265-params --vbv-maxrate ${chnl_bitrates}k --vbv-bufsize ${chnl_bitrates}k"
                    fi
                fi
            else
                chnl_quality_command="-crf $chnl_quality"
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

            if [[ $FFMPEG_FLAGS == *"-vf "* ]] && [ -n "$resolution" ]
            then
                FFMPEG_FLAGS_A=${FFMPEG_FLAGS%-vf *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS#*-vf }
                FFMPEG_FLAGS_C=${FFMPEG_FLAGS_B%% *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS_B#* }
                FFMPEG_FLAGS="$FFMPEG_FLAGS_A $FFMPEG_FLAGS_B"
                resolution="-vf $FFMPEG_FLAGS_C,${resolution#*-vf }"
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$chnl_stream_link" $map_command \
            -y -vcodec "$chnl_video_codec" -acodec "$chnl_audio_codec" $chnl_quality_command $chnl_bitrates_command $resolution \
            $FFMPEG_FLAGS -f flv "$chnl_flv_push_link" > "$FFMPEG_LOG_ROOT/$new_pid.log" 2> "$FFMPEG_LOG_ROOT/$new_pid.err" || true

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$new_pid"')|.flv_status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $chnl_channel_name flv 关闭" >> "$MONITOR_LOG"
            chnl_pid=$new_pid
            action="stop"
            SyncFile
            rm -rf "/tmp/flv.lockdir/$chnl_pid"
            kill -9 "$chnl_pid"
        ;;
        "command") 
            new_channel=$(
            $JQ_FILE -n --arg pid "$pid" --arg status "off" \
                --arg stream_link "$stream_link" --arg live "yes" \
                --arg output_dir_name "$output_dir_name" --arg playlist_name "$playlist_name" \
                --arg seg_dir_name "$SEGMENT_DIRECTORY" --arg seg_name "$seg_name" \
                --arg seg_length "$seg_length" --arg seg_count "$seg_count" \
                --arg video_codec "$VIDEO_CODEC" --arg audio_codec "$AUDIO_CODEC" \
                --arg video_audio_shift "$video_audio_shift" --arg quality "$quality" \
                --arg bitrates "$bitrates" --arg const "$const_yn" \
                --arg encrypt "$encrypt_yn" --arg keyinfo_name "$keyinfo_name" \
                --arg key_name "$key_name" \
                --arg input_flags "$FFMPEG_INPUT_FLAGS" --arg output_flags "$FFMPEG_FLAGS" \
                --arg channel_name "$channel_name" --arg sync "$sync_yn" \
                --arg sync_file '' --arg sync_index '' \
                --arg sync_pairs '' --arg flv_status "on" \
                --arg flv_push_link "$flv_push_link" --arg flv_pull_link "$flv_pull_link" \
                '{
                    pid: $pid | tonumber,
                    status: $status,
                    stream_link: $stream_link,
                    live: $live,
                    output_dir_name: $output_dir_name,
                    playlist_name: $playlist_name,
                    seg_dir_name: $seg_dir_name,
                    seg_name: $seg_name,
                    seg_length: $seg_length | tonumber,
                    seg_count: $seg_count | tonumber,
                    video_codec: $video_codec,
                    audio_codec: $audio_codec,
                    video_audio_shift: $video_audio_shift,
                    quality: $quality,
                    bitrates: $bitrates,
                    const: $const,
                    encrypt: $encrypt,
                    key_name: $key_name,
                    input_flags: $input_flags,
                    output_flags: $output_flags,
                    channel_name: $channel_name,
                    sync: $sync,
                    sync_file: $sync_file,
                    sync_index: $sync_index,
                    sync_pairs: $sync_pairs,
                    flv_status: $flv_status,
                    flv_push_link: $flv_push_link,
                    flv_pull_link: $flv_pull_link
                }'
            )

            JQ add "$CHANNELS_FILE" channels "[$new_channel]"

            action="add"
            SyncFile

            resolution=""

            if [ -z "$quality" ]
            then
                if [ -n "$bitrates" ] 
                then
                    bitrates=${bitrates%%,*}
                    if [[ $bitrates == *"-"* ]] 
                    then
                        resolution=${bitrates#*-}
                        resolution="-vf scale=${resolution//x/:}"
                        bitrates=${bitrates%-*}
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                    elif [[ $bitrates == *"x"* ]] 
                    then
                        resolution=$bitrates
                        resolution="-vf scale=${resolution//x/:}"
                    else
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                    fi
                fi
            elif [ -n "$bitrates" ] 
            then
                bitrates=${bitrates%%,*}
                if [[ $bitrates == *"-"* ]] 
                then
                    resolution=${bitrates#*-}
                    resolution="-vf scale=${resolution//x/:}"
                    bitrates=${bitrates%-*}
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                elif [[ $bitrates == *"x"* ]] 
                then
                    resolution=$bitrates
                    resolution="-vf scale=${resolution//x/:}"
                    quality_command="-crf $quality"
                else
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                fi
            else
                quality_command="-crf $quality"
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

            if [[ $FFMPEG_FLAGS == *"-vf "* ]] && [ -n "$resolution" ]
            then
                FFMPEG_FLAGS_A=${FFMPEG_FLAGS%-vf *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS#*-vf }
                FFMPEG_FLAGS_C=${FFMPEG_FLAGS_B%% *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS_B#* }
                FFMPEG_FLAGS="$FFMPEG_FLAGS_A $FFMPEG_FLAGS_B"
                resolution="-vf $FFMPEG_FLAGS_C,${resolution#*-vf }"
            fi

            $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
            -vcodec "$VIDEO_CODEC" -acodec "$AUDIO_CODEC" $quality_command $bitrates_command $resolution \
            $FFMPEG_FLAGS -f flv "$flv_push_link" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.flv_status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $channel_name flv 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            rm -rf "/tmp/flv.lockdir/$chnl_pid"
            kill -9 "$chnl_pid"
        ;;
    esac
}

HlsStreamCreatorPlus()
{
    trap '' HUP INT QUIT TERM
    trap 'MonitorError $LINENO' ERR
    pid="$BASHPID"
    if [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$pid"')' "$CHANNELS_FILE") ]] 
    then
        true &
        rand_pid=$!
        while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$rand_pid"')' "$CHANNELS_FILE") ]] 
        do
            true &
            rand_pid=$!
        done

        JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.pid)='"$rand_pid"''
    fi
    case $from in
        "AddChannel") 
            mkdir -p "$output_dir_root"
            new_channel=$(
            $JQ_FILE -n --arg pid "$pid" --arg status "on" \
                --arg stream_link "$stream_links_input" --arg live "$live_yn" \
                --arg output_dir_name "$output_dir_name" --arg playlist_name "$playlist_name" \
                --arg seg_dir_name "$SEGMENT_DIRECTORY" --arg seg_name "$seg_name" \
                --arg seg_length "$seg_length" --arg seg_count "$seg_count" \
                --arg video_codec "$VIDEO_CODEC" --arg audio_codec "$AUDIO_CODEC" \
                --arg video_audio_shift "$video_audio_shift" --arg quality "$quality" \
                --arg bitrates "$bitrates" --arg const "$const_yn" \
                --arg encrypt "$encrypt_yn" --arg keyinfo_name "$keyinfo_name" \
                --arg key_name "$key_name" \
                --arg input_flags "$FFMPEG_INPUT_FLAGS" --arg output_flags "$FFMPEG_FLAGS" \
                --arg channel_name "$channel_name" --arg sync "$sync_yn" \
                --arg sync_file "$sync_file" --arg sync_index "$sync_index" \
                --arg sync_pairs "$sync_pairs" --arg flv_status "off" \
                --arg flv_push_link '' --arg flv_pull_link '' \
                '{
                    pid: $pid | tonumber,
                    status: $status,
                    stream_link: $stream_link,
                    live: $live,
                    output_dir_name: $output_dir_name,
                    playlist_name: $playlist_name,
                    seg_dir_name: $seg_dir_name,
                    seg_name: $seg_name,
                    seg_length: $seg_length | tonumber,
                    seg_count: $seg_count | tonumber,
                    video_codec: $video_codec,
                    audio_codec: $audio_codec,
                    video_audio_shift: $video_audio_shift,
                    quality: $quality,
                    bitrates: $bitrates,
                    const: $const,
                    encrypt: $encrypt,
                    keyinfo_name: $keyinfo_name,
                    key_name: $key_name,
                    input_flags: $input_flags,
                    output_flags: $output_flags,
                    channel_name: $channel_name,
                    sync: $sync,
                    sync_file: $sync_file,
                    sync_index: $sync_index,
                    sync_pairs: $sync_pairs,
                    flv_status: $flv_status,
                    flv_push_link: $flv_push_link,
                    flv_pull_link: $flv_pull_link
                }'
            )

            JQ add "$CHANNELS_FILE" channels "[$new_channel]"

            action="add"
            SyncFile

            resolution=""
            output_name="${seg_name}_%05d"

            if [ -z "$quality" ]
            then
                if [ -n "$bitrates" ] 
                then
                    bitrates=${bitrates%%,*}
                    if [[ $bitrates == *"-"* ]] 
                    then
                        resolution=${bitrates#*-}
                        resolution="-vf scale=${resolution//x/:}"
                        bitrates=${bitrates%-*}
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                        output_name="${seg_name}_${bitrates}_%05d"
                    elif [[ $bitrates == *"x"* ]] 
                    then
                        resolution=$bitrates
                        resolution="-vf scale=${resolution//x/:}"
                    else
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                        output_name="${seg_name}_${bitrates}_%05d"
                    fi
                fi
            elif [ -n "$bitrates" ] 
            then
                bitrates=${bitrates%%,*}
                if [[ $bitrates == *"-"* ]] 
                then
                    resolution=${bitrates#*-}
                    resolution="-vf scale=${resolution//x/:}"
                    bitrates=${bitrates%-*}
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                    output_name="${seg_name}_${bitrates}_%05d"
                elif [[ $bitrates == *"x"* ]] 
                then
                    resolution=$bitrates
                    resolution="-vf scale=${resolution//x/:}"
                    quality_command="-crf $quality"
                else
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                    output_name="${seg_name}_${bitrates}_%05d"
                fi
            else
                quality_command="-crf $quality"
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

            if [[ $FFMPEG_FLAGS == *"-vf "* ]] && [ -n "$resolution" ]
            then
                FFMPEG_FLAGS_A=${FFMPEG_FLAGS%-vf *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS#*-vf }
                FFMPEG_FLAGS_C=${FFMPEG_FLAGS_B%% *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS_B#* }
                FFMPEG_FLAGS="$FFMPEG_FLAGS_A $FFMPEG_FLAGS_B"
                resolution="-vf $FFMPEG_FLAGS_C,${resolution#*-vf }"
            fi

            if [ "$live_yn" == "yes" ] 
            then
                live_command="-segment_list_flags +live"
                seg_count_command="-segment_list_size $seg_count -segment_wrap $((seg_count * 2))"
                hls_flags_command="-hls_flags periodic_rekey+delete_segments"
            else
                live_command=""
                seg_count_command=""
                hls_flags_command="-hls_flags periodic_rekey"
            fi

            if [ "$encrypt_yn" == "yes" ]
            then
                openssl rand 16 > "$output_dir_root/$key_name.key"
                echo -e "$key_name.key\n$output_dir_root/$key_name.key\n$(openssl rand -hex 16)" > "$output_dir_root/$keyinfo_name.keyinfo"
                $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
                -vcodec "$VIDEO_CODEC" -acodec "$AUDIO_CODEC" $quality_command $bitrates_command $resolution \
                -threads 0 -flags -global_header $FFMPEG_FLAGS -f hls -hls_time "$seg_length" \
                -hls_list_size $seg_count -hls_delete_threshold $seg_count -hls_key_info_file "$output_dir_root/$keyinfo_name.keyinfo" \
                $hls_flags_command -hls_segment_filename "$output_dir_root/$seg_dir_name/$output_name.ts" "$output_dir_root/$playlist_name.m3u8" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true
            else
                $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
                -vcodec "$VIDEO_CODEC" -acodec "$AUDIO_CODEC" $quality_command $bitrates_command $resolution \
                -threads 0 -flags -global_header -f segment -segment_list "$output_dir_root/$playlist_name.m3u8" \
                -segment_time "$seg_length" -segment_format mpeg_ts $live_command \
                $seg_count_command $FFMPEG_FLAGS "$output_dir_root/$seg_dir_name/$output_name.ts" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true
            fi

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            rm -rf "$LIVE_ROOT/${output_dir_name:-notfound}"
            kill -9 "$pid"
        ;;
        "StartChannel") 
            mkdir -p "$chnl_output_dir_root"
            new_pid=$pid
            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'
            |(.channels[]|select(.pid=='"$new_pid"')|.status)="on"
            |(.channels[]|select(.pid=='"$new_pid"')|.stream_link)="'"$chnl_stream_links"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.playlist_name)="'"$chnl_playlist_name"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.seg_name)="'"$chnl_seg_name"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.key_name)="'"$chnl_key_name"'"'
            action="start"
            SyncFile

            resolution=""
            output_name="${chnl_seg_name}_%05d"

            if [ -z "$chnl_quality" ]
            then
                if [ -n "$chnl_bitrates" ] 
                then
                    chnl_bitrates=${chnl_bitrates%%,*}
                    if [[ $chnl_bitrates == *"-"* ]] 
                    then
                        resolution=${chnl_bitrates#*-}
                        resolution="-vf scale=${resolution//x/:}"
                        chnl_bitrates=${chnl_bitrates%-*}
                        if [ -n "$chnl_const" ] 
                        then
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k -bufsize ${chnl_bitrates}k -minrate ${chnl_bitrates}k -maxrate ${chnl_bitrates}k"
                        else
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k"
                        fi
                        output_name="${chnl_seg_name}_${chnl_bitrates}_%05d"
                    elif [[ $chnl_bitrates == *"x"* ]] 
                    then
                        resolution=$chnl_bitrates
                        resolution="-vf scale=${resolution//x/:}"
                    else
                        if [ -n "$chnl_const" ] 
                        then
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k -bufsize ${chnl_bitrates}k -minrate ${chnl_bitrates}k -maxrate ${chnl_bitrates}k"
                        else
                            chnl_bitrates_command="-b:v ${chnl_bitrates}k"
                        fi
                        output_name="${chnl_seg_name}_${chnl_bitrates}_%05d"
                    fi
                fi
            elif [ -n "$chnl_bitrates" ] 
            then
                chnl_bitrates=${chnl_bitrates%%,*}
                if [[ $chnl_bitrates == *"-"* ]] 
                then
                    resolution=${chnl_bitrates#*-}
                    resolution="-vf scale=${resolution//x/:}"
                    chnl_bitrates=${chnl_bitrates%-*}
                    chnl_quality_command="-crf $chnl_quality -maxrate ${chnl_bitrates}k -bufsize ${chnl_bitrates}k"
                    if [ "$chnl_video_codec" == "libx265" ]
                    then
                    chnl_quality_command="$chnl_quality_command -x265-params --vbv-maxrate ${chnl_bitrates}k --vbv-bufsize ${chnl_bitrates}k"
                    fi
                    output_name="${chnl_seg_name}_${chnl_bitrates}_%05d"
                elif [[ $chnl_bitrates == *"x"* ]] 
                then
                    resolution=$chnl_bitrates
                    resolution="-vf scale=${resolution//x/:}"
                    chnl_quality_command="-crf $chnl_quality"
                else
                    chnl_quality_command="-crf $chnl_quality -maxrate ${chnl_bitrates}k -bufsize ${chnl_bitrates}k"
                    if [ "$chnl_video_codec" == "libx265" ]
                    then
                    chnl_quality_command="$chnl_quality_command -x265-params --vbv-maxrate ${chnl_bitrates}k --vbv-bufsize ${chnl_bitrates}k"
                    fi
                    output_name="${chnl_seg_name}_${chnl_bitrates}_%05d"
                fi
            else
                chnl_quality_command="-crf $chnl_quality"
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

            if [ -n "$chnl_live" ] 
            then
                chnl_live_command="-segment_list_flags +live"
                chnl_seg_count_command="-segment_list_size $chnl_seg_count -segment_wrap $((chnl_seg_count * 2))"
                chnl_hls_flags_command="-hls_flags periodic_rekey+delete_segments"
            else
                chnl_live_command=""
                chnl_seg_count_command=""
                chnl_hls_flags_command="-hls_flags periodic_rekey"
            fi

            if [[ $FFMPEG_FLAGS == *"-vf "* ]] && [ -n "$resolution" ]
            then
                FFMPEG_FLAGS_A=${FFMPEG_FLAGS%-vf *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS#*-vf }
                FFMPEG_FLAGS_C=${FFMPEG_FLAGS_B%% *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS_B#* }
                FFMPEG_FLAGS="$FFMPEG_FLAGS_A $FFMPEG_FLAGS_B"
                resolution="-vf $FFMPEG_FLAGS_C,${resolution#*-vf }"
            fi

            if [ "$chnl_encrypt_yn" == "yes" ] 
            then
                openssl rand 16 > "$chnl_output_dir_root/$chnl_key_name.key"
                echo -e "$chnl_key_name.key\n$chnl_output_dir_root/$chnl_key_name.key\n$(openssl rand -hex 16)" > "$chnl_output_dir_root/$chnl_keyinfo_name.keyinfo"
                $FFMPEG $FFMPEG_INPUT_FLAGS -i "$chnl_stream_link" $map_command -y \
                -vcodec "$chnl_video_codec" -acodec "$chnl_audio_codec" $chnl_quality_command $chnl_bitrates_command $resolution \
                -threads 0 -flags -global_header $FFMPEG_FLAGS -f hls -hls_time "$chnl_seg_length" \
                -hls_list_size $chnl_seg_count -hls_delete_threshold $chnl_seg_count -hls_key_info_file "$chnl_output_dir_root/$chnl_keyinfo_name.keyinfo" \
                $chnl_hls_flags_command -hls_segment_filename "$chnl_output_dir_root/$chnl_seg_dir_name/$output_name.ts" "$chnl_output_dir_root/$chnl_playlist_name.m3u8" > "$FFMPEG_LOG_ROOT/$new_pid.log" 2> "$FFMPEG_LOG_ROOT/$new_pid.err" || true
            else
                $FFMPEG $FFMPEG_INPUT_FLAGS -i "$chnl_stream_link" $map_command -y \
                -vcodec "$chnl_video_codec" -acodec "$chnl_audio_codec" $chnl_quality_command $chnl_bitrates_command $resolution \
                -threads 0 -flags -global_header -f segment -segment_list "$chnl_output_dir_root/$chnl_playlist_name.m3u8" \
                -segment_time "$chnl_seg_length" -segment_format mpeg_ts $chnl_live_command \
                $chnl_seg_count_command $FFMPEG_FLAGS "$chnl_output_dir_root/$chnl_seg_dir_name/$output_name.ts" > "$FFMPEG_LOG_ROOT/$new_pid.log" 2> "$FFMPEG_LOG_ROOT/$new_pid.err" || true
            fi

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$new_pid"')|.status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $chnl_channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$new_pid
            action="stop"
            SyncFile
            rm -rf "$LIVE_ROOT/${chnl_output_dir_name:-notfound}"
            kill -9 "$new_pid"
        ;;
        "command") 
            mkdir -p "$output_dir_root"
            new_channel=$(
            $JQ_FILE -n --arg pid "$pid" --arg status "on" \
                --arg stream_link "$stream_link" --arg live "yes" \
                --arg output_dir_name "$output_dir_name" --arg playlist_name "$playlist_name" \
                --arg seg_dir_name "$SEGMENT_DIRECTORY" --arg seg_name "$seg_name" \
                --arg seg_length "$seg_length" --arg seg_count "$seg_count" \
                --arg video_codec "$VIDEO_CODEC" --arg audio_codec "$AUDIO_CODEC" \
                --arg video_audio_shift "$video_audio_shift" --arg quality "$quality" \
                --arg bitrates "$bitrates" --arg const "$const_yn" \
                --arg encrypt "$encrypt_yn" --arg keyinfo_name "$keyinfo_name" \
                --arg key_name "$key_name" \
                --arg input_flags "$FFMPEG_INPUT_FLAGS" --arg output_flags "$FFMPEG_FLAGS" \
                --arg channel_name "$channel_name" --arg sync "$sync_yn" \
                --arg sync_file '' --arg sync_index '' \
                --arg sync_pairs '' --arg flv_status "off" \
                --arg flv_push_link "$flv_push_link" --arg flv_pull_link "$flv_pull_link" \
                '{
                    pid: $pid | tonumber,
                    status: $status,
                    stream_link: $stream_link,
                    live: $live,
                    output_dir_name: $output_dir_name,
                    playlist_name: $playlist_name,
                    seg_dir_name: $seg_dir_name,
                    seg_name: $seg_name,
                    seg_length: $seg_length | tonumber,
                    seg_count: $seg_count | tonumber,
                    video_codec: $video_codec,
                    audio_codec: $audio_codec,
                    video_audio_shift: $video_audio_shift,
                    quality: $quality,
                    bitrates: $bitrates,
                    const: $const,
                    encrypt: $encrypt,
                    keyinfo_name: $keyinfo_name,
                    key_name: $key_name,
                    input_flags: $input_flags,
                    output_flags: $output_flags,
                    channel_name: $channel_name,
                    sync: $sync,
                    sync_file: $sync_file,
                    sync_index: $sync_index,
                    sync_pairs: $sync_pairs,
                    flv_status: $flv_status,
                    flv_push_link: $flv_push_link,
                    flv_pull_link: $flv_pull_link
                }'
            )

            JQ add "$CHANNELS_FILE" channels "[$new_channel]"

            action="add"
            SyncFile

            resolution=""
            output_name="${seg_name}_%05d"

            if [ -z "$quality" ]
            then
                if [ -n "$bitrates" ] 
                then
                    bitrates=${bitrates%%,*}
                    if [[ $bitrates == *"-"* ]] 
                    then
                        resolution=${bitrates#*-}
                        resolution="-vf scale=${resolution//x/:}"
                        bitrates=${bitrates%-*}
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                        output_name="${seg_name}_${bitrates}_%05d"
                    elif [[ $bitrates == *"x"* ]] 
                    then
                        resolution=$bitrates
                        resolution="-vf scale=${resolution//x/:}"
                    else
                        if [ -n "$const" ] 
                        then
                            bitrates_command="-b:v ${bitrates}k -bufsize ${bitrates}k -minrate ${bitrates}k -maxrate ${bitrates}k"
                        else
                            bitrates_command="-b:v ${bitrates}k"
                        fi
                        output_name="${seg_name}_${bitrates}_%05d"
                    fi
                fi
            elif [ -n "$bitrates" ] 
            then
                bitrates=${bitrates%%,*}
                if [[ $bitrates == *"-"* ]] 
                then
                    resolution=${bitrates#*-}
                    resolution="-vf scale=${resolution//x/:}"
                    bitrates=${bitrates%-*}
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                    output_name="${seg_name}_${bitrates}_%05d"
                elif [[ $bitrates == *"x"* ]] 
                then
                    resolution=$bitrates
                    resolution="-vf scale=${resolution//x/:}"
                    quality_command="-crf $quality"
                else
                    quality_command="-crf $quality -maxrate ${bitrates}k -bufsize ${bitrates}k"
                    if [ "$VIDEO_CODEC" == "libx265" ]
                    then
                    quality_command="$quality_command -x265-params --vbv-maxrate ${bitrates}k --vbv-bufsize ${bitrates}k"
                    fi
                    output_name="${seg_name}_${bitrates}_%05d"
                fi
            else
                quality_command="-crf $quality"
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

            if [[ $FFMPEG_FLAGS == *"-vf "* ]] && [ -n "$resolution" ]
            then
                FFMPEG_FLAGS_A=${FFMPEG_FLAGS%-vf *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS#*-vf }
                FFMPEG_FLAGS_C=${FFMPEG_FLAGS_B%% *}
                FFMPEG_FLAGS_B=${FFMPEG_FLAGS_B#* }
                FFMPEG_FLAGS="$FFMPEG_FLAGS_A $FFMPEG_FLAGS_B"
                resolution="-vf $FFMPEG_FLAGS_C,${resolution#*-vf }"
            fi

            if [ "$live_yn" == "yes" ] 
            then
                live_command="-segment_list_flags +live"
                seg_count_command="-segment_list_size $seg_count -segment_wrap $((seg_count * 2))"
                hls_flags_command="-hls_flags periodic_rekey+delete_segments"
            else
                live_command=""
                seg_count_command=""
                hls_flags_command="-hls_flags periodic_rekey"
            fi

            if [ "$encrypt_yn" == "yes" ]
            then
                openssl rand 16 > "$output_dir_root/$key_name.key"
                echo -e "$key_name.key\n$output_dir_root/$key_name.key\n$(openssl rand -hex 16)" > "$output_dir_root/$keyinfo_name.keyinfo"
                $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
                -vcodec "$VIDEO_CODEC" -acodec "$AUDIO_CODEC" $quality_command $bitrates_command $resolution \
                -threads 0 -flags -global_header $FFMPEG_FLAGS -f hls -hls_time "$seg_length" \
                -hls_list_size $seg_count -hls_delete_threshold $seg_count -hls_key_info_file "$output_dir_root/$keyinfo_name.keyinfo" \
                $hls_flags_command -hls_segment_filename "$output_dir_root/$seg_dir_name/$output_name.ts" "$output_dir_root/$playlist_name.m3u8" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true
            else
                $FFMPEG $FFMPEG_INPUT_FLAGS -i "$stream_link" $map_command -y \
                -vcodec "$VIDEO_CODEC" -acodec "$AUDIO_CODEC" $quality_command $bitrates_command $resolution \
                -threads 0 -flags -global_header -f segment -segment_list "$output_dir_root/$playlist_name.m3u8" \
                -segment_time "$seg_length" -segment_format mpeg_ts $live_command \
                $seg_count_command $FFMPEG_FLAGS "$output_dir_root/$seg_dir_name/$output_name.ts" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true
            fi

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            rm -rf "$LIVE_ROOT/${output_dir_name:-notfound}"
            kill -9 "$pid"
        ;;
    esac
}

HlsStreamCreator()
{
    trap '' HUP INT QUIT TERM
    trap 'MonitorError $LINENO' ERR
    pid="$BASHPID"
    if [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$pid"')' "$CHANNELS_FILE") ]] 
    then
        true &
        rand_pid=$!
        while [[ -n $($JQ_FILE '.channels[]|select(.pid=='"$rand_pid"')' "$CHANNELS_FILE") ]] 
        do
            true &
            rand_pid=$!
        done

        JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.pid)='"$rand_pid"''
    fi
    case $from in
        "AddChannel") 
            mkdir -p "$output_dir_root"
            new_channel=$(
            $JQ_FILE -n --arg pid "$pid" --arg status "on" \
                --arg stream_link "$stream_links_input" --arg live "$live_yn" \
                --arg output_dir_name "$output_dir_name" --arg playlist_name "$playlist_name" \
                --arg seg_dir_name "$SEGMENT_DIRECTORY" --arg seg_name "$seg_name" \
                --arg seg_length "$seg_length" --arg seg_count "$seg_count" \
                --arg video_codec "$VIDEO_CODEC" --arg audio_codec "$AUDIO_CODEC" \
                --arg video_audio_shift "$video_audio_shift" --arg quality "$quality" \
                --arg bitrates "$bitrates" --arg const "$const_yn" \
                --arg encrypt "$encrypt_yn" --arg key_name "$key_name" \
                --arg input_flags "$FFMPEG_INPUT_FLAGS" --arg output_flags "$FFMPEG_FLAGS" \
                --arg channel_name "$channel_name" --arg sync "$sync_yn" \
                --arg sync_file "$sync_file" --arg sync_index "$sync_index" \
                --arg sync_pairs "$sync_pairs" --arg flv_status "off" \
                --arg flv_push_link '' --arg flv_pull_link '' \
                '{
                    pid: $pid | tonumber,
                    status: $status,
                    stream_link: $stream_link,
                    live: $live,
                    output_dir_name: $output_dir_name,
                    playlist_name: $playlist_name,
                    seg_dir_name: $seg_dir_name,
                    seg_name: $seg_name,
                    seg_length: $seg_length | tonumber,
                    seg_count: $seg_count | tonumber,
                    video_codec: $video_codec,
                    audio_codec: $audio_codec,
                    video_audio_shift: $video_audio_shift,
                    quality: $quality,
                    bitrates: $bitrates,
                    const: $const,
                    encrypt: $encrypt,
                    key_name: $key_name,
                    input_flags: $input_flags,
                    output_flags: $output_flags,
                    channel_name: $channel_name,
                    sync: $sync,
                    sync_file: $sync_file,
                    sync_index: $sync_index,
                    sync_pairs: $sync_pairs,
                    flv_status: $flv_status,
                    flv_push_link: $flv_push_link,
                    flv_pull_link: $flv_pull_link
                }'
            )

            JQ add "$CHANNELS_FILE" channels "[$new_channel]"

            action="add"
            SyncFile

            if [ -n "$quality" ] 
            then
                quality_command="-q $quality"
            fi

            if [ -n "$bitrates" ] 
            then
                bitrates_command="-b $bitrates"
            fi

            $CREATOR_FILE $live -i "$stream_link" -s "$seg_length" \
            -o "$output_dir_root" $seg_count_command $bitrates_command \
            -p "$playlist_name" -t "$seg_name" $key_name_command $quality_command \
            "$const" "$encrypt" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            rm -rf "$LIVE_ROOT/${output_dir_name:-notfound}"
            kill -9 "$pid"
        ;;
        "StartChannel") 
            mkdir -p "$chnl_output_dir_root"
            new_pid=$pid
            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'
            |(.channels[]|select(.pid=='"$new_pid"')|.status)="on"
            |(.channels[]|select(.pid=='"$new_pid"')|.stream_link)="'"$chnl_stream_links"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.playlist_name)="'"$chnl_playlist_name"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.seg_name)="'"$chnl_seg_name"'"
            |(.channels[]|select(.pid=='"$new_pid"')|.key_name)="'"$chnl_key_name"'"'
            action="start"
            SyncFile

            if [ -n "$chnl_quality" ] 
            then
                chnl_quality_command="-q $chnl_quality"
            fi

            if [ -n "$chnl_bitrates" ] 
            then
                chnl_bitrates_command="-b $chnl_bitrates"
            fi

            $CREATOR_FILE $chnl_live -i "$chnl_stream_link" -s "$chnl_seg_length" \
            -o "$chnl_output_dir_root" $chnl_seg_count_command $chnl_bitrates_command \
            -p "$chnl_playlist_name" -t "$chnl_seg_name" $chnl_key_name_command $chnl_quality_command \
            "$chnl_const" "$chnl_encrypt" > "$FFMPEG_LOG_ROOT/$new_pid.log" 2> "$FFMPEG_LOG_ROOT/$new_pid.err" || true

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$new_pid"')|.status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $chnl_channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$new_pid
            action="stop"
            SyncFile
            rm -rf "$LIVE_ROOT/${chnl_output_dir_name:-notfound}"
            kill -9 "$new_pid"
        ;;
        "command") 
            mkdir -p "$output_dir_root"
            new_channel=$(
            $JQ_FILE -n --arg pid "$pid" --arg status "on" \
                --arg stream_link "$stream_link" --arg live "yes" \
                --arg output_dir_name "$output_dir_name" --arg playlist_name "$playlist_name" \
                --arg seg_dir_name "$SEGMENT_DIRECTORY" --arg seg_name "$seg_name" \
                --arg seg_length "$seg_length" --arg seg_count "$seg_count" \
                --arg video_codec "$VIDEO_CODEC" --arg audio_codec "$AUDIO_CODEC" \
                --arg video_audio_shift '' --arg quality "$quality" \
                --arg bitrates "$bitrates" --arg const "$const_yn" \
                --arg encrypt "$encrypt_yn" --arg key_name "$key_name" \
                --arg input_flags "$FFMPEG_INPUT_FLAGS" --arg output_flags "$FFMPEG_FLAGS" \
                --arg channel_name "$channel_name" --arg sync "$sync_yn" \
                --arg sync_file '' --arg sync_index '' \
                --arg sync_pairs '' --arg flv_status "off" \
                --arg flv_push_link "$flv_push_link" --arg flv_pull_link "$flv_pull_link" \
                '{
                    pid: $pid | tonumber,
                    status: $status,
                    stream_link: $stream_link,
                    live: $live,
                    output_dir_name: $output_dir_name,
                    playlist_name: $playlist_name,
                    seg_dir_name: $seg_dir_name,
                    seg_name: $seg_name,
                    seg_length: $seg_length | tonumber,
                    seg_count: $seg_count | tonumber,
                    video_codec: $video_codec,
                    audio_codec: $audio_codec,
                    video_audio_shift: $video_audio_shift,
                    quality: $quality,
                    bitrates: $bitrates,
                    const: $const,
                    encrypt: $encrypt,
                    key_name: $key_name,
                    input_flags: $input_flags,
                    output_flags: $output_flags,
                    channel_name: $channel_name,
                    sync: $sync,
                    sync_file: $sync_file,
                    sync_index: $sync_index,
                    sync_pairs: $sync_pairs,
                    flv_status: $flv_status,
                    flv_push_link: $flv_push_link,
                    flv_pull_link: $flv_pull_link
                }'
            )

            JQ add "$CHANNELS_FILE" channels "[$new_channel]"

            action="add"
            SyncFile

            if [ -n "$quality" ] 
            then
                quality_command="-q $quality"
            fi

            if [ -n "$bitrates" ] 
            then
                bitrates_command="-b $bitrates"
            fi

            $CREATOR_FILE -l -i "$stream_link" -s "$seg_length" \
            -o "$output_dir_root" -c "$seg_count" $bitrates_command \
            -p "$playlist_name" -t "$seg_name" -K "$key_name" $quality_command \
            "$const" "$encrypt" > "$FFMPEG_LOG_ROOT/$pid.log" 2> "$FFMPEG_LOG_ROOT/$pid.err" || true

            JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$pid"')|.status)="off"'

            printf -v date_now '%(%m-%d %H:%M:%S)T'
            printf '%s\n' "$date_now $channel_name HLS 关闭" >> "$MONITOR_LOG"
            chnl_pid=$pid
            action="stop"
            SyncFile
            rm -rf "$LIVE_ROOT/${output_dir_name:-notfound}"
            kill -9 "$pid"
        ;;
    esac
}

AddChannel()
{
    [ ! -e "$IPTV_ROOT" ] && echo && echo -e "$error 尚未安装，请检查 !" && echo && exit 1
    GetDefault
    SetStreamLink

    if [ "${stream_link:0:1}" == "/" ] 
    then
        is_local=1
    else
        is_local=0
    fi

    if [[ $stream_link == *".m3u8"* ]] 
    then
        is_hls=1
    elif [[ $stream_link == *".flv"* ]] || [[ $stream_link == *".ts"* ]]
    then
        is_hls=0
    else
        SetIsHls
    fi

    SetLive
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
        SetBitrates

        if [ -n "$bitrates" ] 
        then
            if [[ $bitrates != *"-"* ]] && [[ $bitrates == *"x"* ]]
            then
                master=0
            else
                master=1
            fi
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
        SetFlvPushLink
        SetFlvPullLink
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
        if [ -n "$live" ] 
        then
            SetSegCount
            seg_count_command="-c $seg_count"
        else
            seg_count=$d_seg_count
            seg_count_command=""
        fi
        SetEncrypt
        if [ -n "$encrypt" ] 
        then
            SetKeyInfoName
            SetKeyName
            key_name_command="-K $key_name"
        else
            keyinfo_name=$(RandStr)
            key_name=$(RandStr)
            key_name_command=""
        fi
    fi

    SetInputFlags
    SetOutputFlags
    SetChannelName
    SetSync

    if [ "$sync_yn" == "yes" ]
    then
        SetSyncFile
        SetSyncIndex
        SetSyncPairs
    else
        sync_file=""
        sync_index=""
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

    [ ! -e $FFMPEG_LOG_ROOT ] && mkdir $FFMPEG_LOG_ROOT
    from="AddChannel"

    if [ -n "${kind:-}" ] 
    then
        if [ "$kind" == "flv" ] 
        then
            ( FlvStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null & 
        else
            echo && echo -e "$error 暂不支持输出 $kind ..." && echo && exit 1
        fi
    elif [ -n "${video_audio_shift:-}" ] || { [ "$encrypt_yn" == "yes" ] && [ "$live_yn" == "yes" ]; }
    then
        ( HlsStreamCreatorPlus ) > /dev/null 2>/dev/null </dev/null &
    else
        ( HlsStreamCreator ) > /dev/null 2>/dev/null </dev/null &
    fi

    echo && echo -e "$info 频道添加成功 !" && echo
}

EditStreamLink()
{
    SetStreamLink
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.stream_link)="'"$stream_links_input"'"'
    echo && echo -e "$info 直播源修改成功 !" && echo
}

EditLive()
{
    SetLive
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.live)="'"$live_yn"'"'
    echo && echo -e "$info 无限时长直播修改成功 !" && echo
}

EditOutputDirName()
{
    if [ "$chnl_status" == "on" ]
    then
        echo && echo -e "$error 检测到频道正在运行，是否现在关闭？[y/N]"
        read -p "(默认: N): " stop_channel_yn
        stop_channel_yn=${stop_channel_yn:-n}
        if [[ $stop_channel_yn == [Yy] ]]
        then
            StopChannel
            echo && echo
        else
            echo && echo "已取消..." && echo && exit 1
        fi
    fi
    SetOutputDirName
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.output_dir_name)="'"$output_dir_name"'"'
    echo && echo -e "$info 输出目录名称修改成功 !" && echo
}

EditPlaylistName()
{
    SetPlaylistName
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.playlist_name)="'"$playlist_name"'"'
    echo && echo -e "$info m3u8名称修改成功 !" && echo
}

EditSegDirName()
{
    SetSegDirName
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_dir_name)="'"$seg_dir_name"'"'
    echo && echo -e "$info 段所在子目录名称修改成功 !" && echo
}

EditSegName()
{
    SetSegName
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_name)="'"$seg_name"'"'
    echo && echo -e "$info 段名称修改成功 !" && echo
}

EditSegLength()
{
    SetSegLength
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_length)='"$seg_length"''
    echo && echo -e "$info 段时长修改成功 !" && echo
}

EditSegCount()
{
    SetSegCount
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.seg_count)='"$seg_count"''
    echo && echo -e "$info 段数目修改成功 !" && echo
}

EditVideoCodec()
{
    SetVideoCodec
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.video_codec)="'"$video_codec"'"'
    echo && echo -e "$info 视频编码修改成功 !" && echo
}

EditAudioCodec()
{
    SetAudioCodec
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.audio_codec)="'"$audio_codec"'"'
    echo && echo -e "$info 音频编码修改成功 !" && echo
}

EditQuality()
{
    SetQuality
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.quality)="'"$quality"'"'
    echo && echo -e "$info crf质量值修改成功 !" && echo
}

EditBitrates()
{
    SetBitrates
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.bitrates)="'"$bitrates"'"'
    echo && echo -e "$info 比特率修改成功 !" && echo
}

EditConst()
{
    SetConst
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.const)="'"$const_yn"'"'
    echo && echo -e "$info 是否固定码率修改成功 !" && echo
}

EditEncrypt()
{
    SetEncrypt
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.encrypt)="'"$encrypt"'"'
    echo && echo -e "$info 是否加密修改成功 !" && echo
}

EditKeyName()
{
    SetKeyName
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.key_name)="'"$key_name"'"'
    echo && echo -e "$info key名称修改成功 !" && echo
}

EditInputFlags()
{
    SetInputFlags
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.input_flags)="'"$input_flags"'"'
    echo && echo -e "$info input flags修改成功 !" && echo
}

EditOutputFlags()
{
    SetOutputFlags
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.output_flags)="'"$output_flags"'"'
    echo && echo -e "$info output flags修改成功 !" && echo
}

EditChannelName()
{
    SetChannelName
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.channel_name)="'"$channel_name"'"'
    echo && echo -e "$info 频道名称修改成功 !" && echo
}

EditSync()
{
    SetSync
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.sync)="'"$sync_yn"'"'
    echo && echo -e "$info 是否开启 sync 修改成功 !" && echo
}

EditSyncFile()
{
    SetSyncFile
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.sync_file)="'"$sync_file"'"'
    echo && echo -e "$info sync_file 修改成功 !" && echo
}

EditSyncIndex()
{
    SetSyncIndex
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.sync_index)="'"$sync_index"'"'
    echo && echo -e "$info sync_index 修改成功 !" && echo
}

EditSyncPairs()
{
    SetSyncPairs
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.sync_pairs)="'"$sync_pairs"'"'
    echo && echo -e "$info sync_pairs 修改成功 !" && echo
}

EditFlvPushLink()
{
    SetFlvPushLink
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.flv_push_link)="'"$flv_push_link"'"'
    echo && echo -e "$info 推流地址修改成功 !" && echo
}

EditFlvPullLink()
{
    SetFlvPullLink
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.flv_pull_link)="'"$flv_pull_link"'"'
    echo && echo -e "$info 拉流地址修改成功 !" && echo
}

EditChannelAll()
{
    if [ "$chnl_flv_status" == "on" ] 
    then
        kind="flv"
        echo && echo -e "$error 检测到频道正在运行，是否现在关闭？[y/N]"
        read -p "(默认: N): " stop_channel_yn
        stop_channel_yn=${stop_channel_yn:-n}
        if [[ $stop_channel_yn == [Yy] ]]
        then
            StopChannel
            echo && echo
        else
            echo && echo "已取消..." && echo && exit 1
        fi
    elif [ "$chnl_status" == "on" ]
    then
        kind=""
        echo && echo -e "$error 检测到频道正在运行，是否现在关闭？[y/N]"
        read -p "(默认: N): " stop_channel_yn
        stop_channel_yn=${stop_channel_yn:-n}
        if [[ $stop_channel_yn == [Yy] ]]
        then
            StopChannel
            echo && echo
        else
            echo && echo "已取消..." && echo && exit 1
        fi
    fi

    SetStreamLink

    if [ "${stream_link:0:1}" == "/" ] 
    then
        is_local=1
    else
        is_local=0
    fi

    if [[ $stream_link == *".m3u8"* ]] 
    then
        is_hls=1
    elif [[ $stream_link == *".flv"* ]] || [[ $stream_link == *".ts"* ]]
    then
        is_hls=0
    else
        SetIsHls
    fi

    SetLive
    SetOutputDirName
    SetPlaylistName
    SetSegDirName
    SetSegName
    SetSegLength

    if [ -n "$live" ] 
    then
        SetSegCount
    else
        seg_count=$d_seg_count
    fi

    SetVideoCodec
    SetAudioCodec
    SetVideoAudioShift

    if [ -z "${kind:-}" ] && [ "$video_codec" == "copy" ] && [ "$video_codec" == "copy" ]
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

    if [ "${kind:-}" == "flv" ] 
    then
        SetFlvPushLink
        SetFlvPullLink
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
        if [ -n "$live" ] 
        then
            SetSegCount
        else
            seg_count=$d_seg_count
        fi
        SetEncrypt
        if [ -n "$encrypt" ] 
        then
            SetKeyInfoName
            SetKeyName
        else
            keyinfo_name=$(RandStr)
            key_name=$(RandStr)
        fi
    fi

    SetInputFlags
    SetOutputFlags
    SetChannelName
    SetSync

    if [ "$sync_yn" == "yes" ]
    then
        SetSyncFile
        SetSyncIndex
        SetSyncPairs
    else
        sync_file=""
        sync_index=""
        sync_pairs=""
    fi

    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.stream_link)="'"$stream_links_input"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.live)="'"$live_yn"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.output_dir_name)="'"$output_dir_name"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.playlist_name)="'"$playlist_name"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.seg_dir_name)="'"$seg_dir_name"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.seg_name)="'"$seg_name"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.seg_length)='"$seg_length"'
    |(.channels[]|select(.pid=='"$chnl_pid"')|.seg_count)='"$seg_count"'
    |(.channels[]|select(.pid=='"$chnl_pid"')|.video_codec)="'"$video_codec"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.audio_codec)="'"$audio_codec"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.video_audio_shift)="'"$video_audio_shift"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.quality)="'"$quality"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.bitrates)="'"$bitrates"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.const)="'"$const_yn"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.encrypt)="'"$encrypt_yn"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.keyinfo_name)="'"$keyinfo_name"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.key_name)="'"$key_name"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.input_flags)="'"$input_flags"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.output_flags)="'"$output_flags"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.channel_name)="'"$channel_name"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.sync)="'"$sync_yn"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.sync_file)="'"$sync_file"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.sync_index)="'"$sync_index"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.sync_pairs)="'"$sync_pairs"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.flv_push_link)="'"$flv_push_link"'"
    |(.channels[]|select(.pid=='"$chnl_pid"')|.flv_pull_link)="'"$flv_pull_link"'"'

    echo && echo -e "$info 频道 [ $channel_name ] 修改成功 !" && echo
}

EditForSecurity()
{
    SetPlaylistName
    SetSegName
    JQ update "$CHANNELS_FILE" '(.channels[]|select(.pid=='"$chnl_pid"')|.playlist_name)="'"$playlist_name"'"|(.channels[]|select(.pid=='"$chnl_pid"')|.seg_name)="'"$seg_name"'"'
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
    ${green}2.$plain 修改 无限时长直播
    ${green}3.$plain 修改 输出目录名称
    ${green}4.$plain 修改 m3u8名称
    ${green}5.$plain 修改 段所在子目录名称
    ${green}6.$plain 修改 段名称
    ${green}7.$plain 修改 段时长
    ${green}8.$plain 修改 段数目
    ${green}9.$plain 修改 视频编码
    ${green}10.$plain 修改 音频编码
    ${green}11.$plain 修改 crf质量值
    ${green}12.$plain 修改 比特率
    ${green}13.$plain 修改 是否固定码率
    ${green}14.$plain 修改 是否加密
    ${green}15.$plain 修改 key名称
    ${green}16.$plain 修改 input flags
    ${green}17.$plain 修改 output flags
    ${green}18.$plain 修改 频道名称
    ${green}19.$plain 修改 是否开启 sync
    ${green}20.$plain 修改 sync file
    ${green}21.$plain 修改 sync index
    ${green}22.$plain 修改 sync pairs
    ${green}23.$plain 修改 推流地址
    ${green}24.$plain 修改 拉流地址
    ${green}25.$plain 修改 全部配置
    ————— 组合[常用] —————
    ${green}26.$plain 修改 段名称、m3u8名称 (防盗链/DDoS)
    " && echo
        read -p "(默认: 取消): " edit_channel_num
        [ -z "$edit_channel_num" ] && echo && echo "已取消..." && echo && exit 1
        case $edit_channel_num in
            1)
                EditStreamLink
            ;;
            2)
                EditLive
            ;;
            3)
                EditOutputDirName
            ;;
            4)
                EditPlaylistName
            ;;
            5)
                EditSegDirName
            ;;
            6)
                EditSegName
            ;;
            7)
                EditSegLength
            ;;
            8)
                EditSegCount
            ;;
            9)
                EditVideoCodec
            ;;
            10)
                EditAudioCodec
            ;;
            11)
                EditQuality
            ;;
            12)
                EditBitrates
            ;;
            13)
                EditConst
            ;;
            14)
                EditEncrypt
            ;;
            15)
                EditKeyName
            ;;
            16)
                EditInputFlags
            ;;
            17)
                EditOutputFlags
            ;;
            18)
                EditChannelName
            ;;
            19)
                EditSync
            ;;
            20)
                EditSyncFile
            ;;
            21)
                EditSyncIndex
            ;;
            22)
                EditSyncPairs
            ;;
            23)
                EditFlvPushLink
            ;;
            24)
                EditFlvPullLink
            ;;
            25)
                EditChannelAll
            ;;
            26)
                EditForSecurity
            ;;
            *)
                echo "请输入正确序号..." && exit 1
            ;;
        esac

        if [ "$chnl_status" == "on" ] || [ "$chnl_flv_status" == "on" ]
        then
            echo "是否重启此频道？[Y/n]"
            read -p "(默认: Y): " restart_yn
            restart_yn=${restart_yn:-Y}
            if [[ $restart_yn == [Yy] ]] 
            then
                StopChannel
                GetChannelInfo
                StartChannel
                echo && echo -e "$info 频道重启成功 !" && echo
            else
                echo "不重启..."
            fi
        else
            echo "是否启动此频道？[y/N]"
            read -p "(默认: N): " start_yn
            start_yn=${start_yn:-N}
            if [[ $start_yn == [Yy] ]] 
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
    if [ "${chnl_stream_link:0:4}" == "rtmp" ] || [ "${chnl_stream_link:0:1}" == "/" ]
    then
        chnl_input_flags=${chnl_input_flags//-timeout 2000000000/}
        chnl_input_flags=${chnl_input_flags//-reconnect 1/}
        chnl_input_flags=${chnl_input_flags//-reconnect_at_eof 1/}
        chnl_input_flags=${chnl_input_flags//-reconnect_streamed 1/}
        chnl_input_flags=${chnl_input_flags//-reconnect_delay_max 2000/}
        lead=${chnl_input_flags%%[^[:blank:]]*}
        chnl_input_flags=${chnl_input_flags#${lead}}
    elif [[ ${chnl_stream_link:-} == *".m3u8"* ]] 
    then
        chnl_input_flags=${chnl_input_flags//-reconnect_at_eof 1/}
    fi
    chnl_quality_command=""
    chnl_bitrates_command=""

    if [ -n "$chnl_live" ]
    then
        chnl_seg_count_command="-c $chnl_seg_count"
    else
        chnl_seg_count_command=""
    fi

    if [ -n "$chnl_encrypt" ] 
    then
        chnl_key_name_command="-K $chnl_key_name"
    else
        chnl_key_name_command=""
    fi

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
        fi

        if [ -n "$chnl_bitrates" ] 
        then
            if [[ $chnl_bitrates != *"-"* ]] && [[ $chnl_bitrates == *"x"* ]]
            then
                master=0
            else
                master=1
            fi
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

    [ ! -e $FFMPEG_LOG_ROOT ] && mkdir $FFMPEG_LOG_ROOT
    from="StartChannel"

    if [ -n "${kind:-}" ] 
    then
        if [ "$chnl_status" == "on" ] 
        then
            echo && echo -e "$error HLS 频道正开启，走错片场了？" && echo && exit 1
        fi
        FFMPEG_FLAGS=${FFMPEG_FLAGS//-sc_threshold 0/}
        if [ "$kind" == "flv" ] 
        then
            rm -rf "$FFMPEG_LOG_ROOT/$chnl_pid.log"
            rm -rf "$FFMPEG_LOG_ROOT/$chnl_pid.err"
            ( FlvStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null &
        else
            echo && echo -e "$error 暂不支持输出 $kind ..." && echo && exit 1
        fi
    else
        if [ "$chnl_flv_status" == "on" ] 
        then
            echo && echo -e "$error FLV 频道正开启，走错片场了？" && echo && exit 1
        fi
        rm -rf "$FFMPEG_LOG_ROOT/$chnl_pid.log"
        rm -rf "$FFMPEG_LOG_ROOT/$chnl_pid.err"
        if [ -n "${chnl_video_audio_shift:-}" ] || { [ "$chnl_encrypt_yn" == "yes" ] && [ "$chnl_live_yn" == "yes" ]; }
        then
            ( HlsStreamCreatorPlus ) > /dev/null 2>/dev/null </dev/null &
        else
            ( HlsStreamCreator ) > /dev/null 2>/dev/null </dev/null &
        fi
    fi

    echo && echo -e "$info 频道[ $chnl_channel_name ]已开启 !" && echo
}

StopChannel()
{
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

    while [ "$stopped" == 0 ] 
    do
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
    done

    if [ "${kind:-}" == "flv" ] 
    then
        until [ ! -d "/tmp/flv.lockdir/$chnl_pid" ] 
        do
            sleep 1
        done
        chnl_flv_status="off"
        echo && echo -e "$info 频道[ $chnl_channel_name ]已关闭 !" && echo
    else
        until [ ! -d "$LIVE_ROOT/$chnl_output_dir_name" ] 
        do
            sleep 1
        done
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
            fi
        elif [ "$chnl_status" == "on" ] 
        then
            action="skip"
            StopChannel
        fi
        StartChannel
        echo && echo -e "$info 频道重启成功 !" && echo
    done
}

ViewChannelLog()
{
    ListChannels
    InputChannelsIndex
    for chnl_pid in "${chnls_pid_chosen[@]}"
    do
        GetChannelInfo
        ViewChannelInfo

        echo && echo -e "${green}输出日志:$plain" && echo
        if [ -s "$FFMPEG_LOG_ROOT/$chnl_pid.log" ] 
        then
            tail -n 10 "$FFMPEG_LOG_ROOT/$chnl_pid.log"
        else
            echo "无"
        fi

        echo && echo -e "${red}错误日志:$plain" && echo
        if [ -s "$FFMPEG_LOG_ROOT/$chnl_pid.err" ] 
        then
            cat "$FFMPEG_LOG_ROOT/$chnl_pid.err"
        else
            echo "无"
        fi
        echo
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
        JQ delete "$CHANNELS_FILE" channels "$chnl_pid"
        rm -rf "$FFMPEG_LOG_ROOT/$chnl_pid.log"
        rm -rf "$FFMPEG_LOG_ROOT/$chnl_pid.err"
        echo && echo -e "$info 频道删除成功 !" && echo
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
        if [[ -z $($JQ_FILE '.channels[] | select(.output_dir_name=="'"$output_dir_name"'")' "$CHANNELS_FILE") ]]
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
        if [[ -z $($JQ_FILE '.channels[] | select(.playlist_name=="'"$playlist_name"'")' "$CHANNELS_FILE") ]]
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
        if [[ -z $($JQ_FILE '.channels[] | select(.seg_dir_name=="'"$seg_dir_name"'")' "$CHANNELS_FILE") ]]
        then
            echo "$seg_dir_name"
            break
        fi
    done
}

# printf %s "$1" | jq -s -R -r @uri
Urlencode() {
    local LANG=C i c e=''
    for ((i=0;i<${#1};i++)); do
        c=${1:$i:1}
        [[ "$c" =~ [a-zA-Z0-9\.\~\_\-] ]] || printf -v c '%%%02X' "'$c"
        e+="$c"
    done
    echo "$e"
}

GenerateScheduleNowtv()
{
    SCHEDULE_LINK_NOWTV="https://nowplayer.now.com/tvguide/epglist?channelIdList%5B%5D=$1&day=1"

    nowtv_schedule=$(curl --cookie "LANG=zh" -s "$SCHEDULE_LINK_NOWTV" || true)

    if [ -z "${nowtv_schedule:-}" ]
    then
        echo -e "\nNowTV empty: $chnl_nowtv_id\n"
        return 0
    else
        if [ ! -s "$SCHEDULE_JSON" ] 
        then
            printf '{"%s":[]}' "$chnl_nowtv_id" > "$SCHEDULE_JSON"
        fi

        schedule=""
        while IFS= read -r program
        do
            title=${program#*title: }
            title=${title%, time:*}
            time=${program#*time: }
            time=${time%, sys_time:*}
            sys_time=${program#*sys_time: }
            sys_time=${sys_time%\"}
            sys_time=${sys_time:0:10}
            [ -n "$schedule" ] && schedule="$schedule,"
            schedule=$schedule'{
                "title":"'"$title"'",
                "time":"'"$time"'",
                "sys_time":"'"$sys_time"'"
            }'
        done < <($JQ_FILE '.[0] | to_entries | map("title: \(.value.name), time: \(.value.startTime), sys_time: \(.value.start)") | .[]' <<< "$nowtv_schedule")

        if [ -z "$schedule" ] 
        then
            echo -e "$error\nNowTV not found\n"
        else
            JQ replace "$SCHEDULE_JSON" "$chnl_nowtv_id" "[$schedule]"
        fi
    fi
}

GenerateScheduleNiotv()
{
    if [ ! -s "$SCHEDULE_JSON" ] 
    then
        printf '{"%s":[]}' "$chnl_niotv_id" > "$SCHEDULE_JSON"
    fi

    printf -v today '%(%Y-%m-%d)T'
    SCHEDULE_LINK_NIOTV="http://www.niotv.com/i_index.php?cont=day"

    empty=1
    check=1
    schedule=""
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
            sys_time=$(date -d "$today $start_time" +%s)

            start_time_num=$sys_time
            end_time_num=$(date -d "$today $end_time" +%s)

            if [ "$check" == 1 ] && [ "$start_time_num" -gt "$end_time_num" ] 
            then
                continue
            fi

            check=0

            [ -n "$schedule" ] && schedule="$schedule,"
            schedule=$schedule'{
                "title":"'"$title"'",
                "time":"'"$start_time"'",
                "sys_time":"'"$sys_time"'"
            }'
        fi
    done < <(wget --post-data "act=select&day=$today&sch_id=$1" "$SCHEDULE_LINK_NIOTV" -qO- || true)
    #curl -d "day=$today&sch_id=$1" -X POST "$SCHEDULE_LINK_NIOTV" || true

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
                GenerateScheduleNowtv "$chnl_nowtv_num"
                break
            fi
        done
        [ "$match_nowtv" == 0 ] && echo -e "\nNowTV not found\n"
        return 0
    fi

    JQ replace "$SCHEDULE_JSON" "$chnl_niotv_id" "[$schedule]"
}

GenerateSchedule()
{
    if [ ! -s "$SCHEDULE_JSON" ] 
    then
        printf '{"%s":[]}' "$chnl_id" > "$SCHEDULE_JSON"
    fi

    chnl_id=${1%%:*}
    chnl_name=${chnl#*:}
    chnl_name=${chnl_name// /-}
    chnl_name_encode=$(Urlencode "$chnl_name")

    printf -v today '%(%Y-%m-%d)T'

    SCHEDULE_LINK="https://xn--i0yt6h0rn.tw/channel/$chnl_name_encode/index.json"

    schedule=""
    while IFS= read -r program 
    do
        program_title=${program#*name: }
        program_title=${program_title%%, time: *}
        program_time=${program#*, time: }
        program_time=${program_time%\"}
        program_sys_time=$(date -d "$today $program_time" +%s)

        [ -n "$schedule" ] && schedule="$schedule,"
        schedule=$schedule'{
            "title":"'"$program_title"'",
            "time":"'"$program_time"'",
            "sys_time":"'"$program_sys_time"'"
        }'
    done < <($JQ_FILE '.list[] | select(.key=="'"$today"'").values | to_entries | map("name: \(.value.name), time: \(.value.time)")[]' <<< $(wget --no-check-certificate "$SCHEDULE_LINK" -qO- || true))

    if [ -z "$schedule" ]
    then
        today=${today//-/\/}
        while IFS= read -r program 
        do
            program_title=${program#*name: }
            program_title=${program_title%%, time: *}
            program_time=${program#*, time: }
            program_time=${program_time%\"}
            program_sys_time=$(date -d "$today $program_time" +%s)

            [ -n "$schedule" ] && schedule="$schedule,"
            schedule=$schedule'{
                "title":"'"$program_title"'",
                "time":"'"$program_time"'",
                "sys_time":"'"$program_sys_time"'"
            }'
        done < <($JQ_FILE '.list[] | select(.key=="'"$today"'").values | to_entries | map("name: \(.value.name), time: \(.value.time)")[]' <<< $(wget --no-check-certificate "$SCHEDULE_LINK" -qO- || true))

        if [ -z "$schedule" ] 
        then
            echo -e "\n\nempty: $1\ntrying NioTV...\n"

            match=0
            for chnl_niotv in "${chnls_niotv[@]}" ; do
                chnl_niotv_id=${chnl_niotv%%:*}
                if [ "$chnl_niotv_id" == "$chnl_id" ] 
                then
                    match=1
                    chnl_niotv_num=${chnl_niotv#*:}
                    GenerateScheduleNiotv "$chnl_niotv_num"
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
                        GenerateScheduleNowtv "$chnl_nowtv_num"
                        break
                    fi
                done
            fi

            [ "$match" == 0 ] && echo -e "\nNowTV not found\n"
            return 0
        fi
    fi

    JQ replace "$SCHEDULE_JSON" "$chnl_id" "[$schedule]"
}

InstallPdf2html()
{
    Progress &
    progress_pid=$!
    if [ "$release" == "rpm" ] 
    then
        yum install cmake gcc gnu-getopt java-1.8.0-openjdk libpng-devel fontforge-devel cairo-devel poppler-devel libspiro-devel freetype-devel libtiff-devel openjpeg libxml2-devel giflibgiflib-devel libjpeg-turbo-devel libuninameslist-devel pango-devel make gcc-c++ >/dev/null 2>&1
    else
        apt-get -y update >/dev/null 2>&1
        apt-get -y install libpoppler-private-dev libpoppler-dev libfontforge-dev pkg-config libopenjp2-7-dev libjpeg-dev libtiff5-dev libpng-dev libfreetype6-dev libgif-dev libgtk-3-dev libxml2-dev libpango1.0-dev libcairo2-dev libspiro-dev libuninameslist-dev python3-dev ninja-build cmake build-essential >/dev/null 2>&1
    fi

    echo -n "...40%..."

    while IFS= read -r line
    do
        if [[ $line == *"latest stable release is"* ]] 
        then
            line=${line#*<a href=\"}
            poppler_name=${line%%.tar.xz*}
        elif [[ $line == *"poppler encoding data"* ]] 
        then
            line=${line#*<a href=\"}
            poppler_data_name=${line%%.tar.gz*}
            break
        fi
    done < <( wget --timeout=10 --tries=3 --no-check-certificate "https://poppler.freedesktop.org/" -qO- )

    cd ~
    if [ ! -e "./$poppler_data_name" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "$FFMPEG_MIRROR_LINK/$poppler_data_name.tar.gz" -qO "$poppler_data_name.tar.gz"
        tar xzvf "$poppler_data_name.tar.gz" >/dev/null 2>&1
    fi

    cd "$poppler_data_name/"
    make install >/dev/null 2>&1

    echo -n "...50%..."

    poppler_name="poppler-0.81.0"

    cd ~
    if [ ! -e "./$poppler_name" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "$FFMPEG_MIRROR_LINK/$poppler_name.tar.xz" -qO "$poppler_name.tar.xz"
        tar -xJf "$poppler_name.tar.xz" >/dev/null 2>&1
    fi

    cd "$poppler_name/"
    mkdir -p build
    cd build
    cmake -DENABLE_UNSTABLE_API_ABI_HEADERS=ON .. >/dev/null 2>&1
    make >/dev/null 2>&1
    make install >/dev/null 2>&1

    echo -n "...70%..."

    cd ~
    if [ ! -e "./fontforge-20190413" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "$FFMPEG_MIRROR_LINK/fontforge-20190413.tar.gz" -qO "fontforge-20190413.tar.gz"
        tar xzvf "fontforge-20190413.tar.gz" >/dev/null 2>&1
    fi

    cd "fontforge-20190413/"
    ./bootstrap >/dev/null 2>&1
    ./configure >/dev/null 2>&1
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    echo -n "...90%..."

    cd ~
    if [ ! -e "./pdf2htmlEX-0.18.7-poppler-0.81.0" ] 
    then
        wget --timeout=10 --tries=3 --no-check-certificate "$FFMPEG_MIRROR_LINK/pdf2htmlEX-0.18.7-poppler-0.81.0.zip" -qO "pdf2htmlEX-0.18.7-poppler-0.81.0.zip"
        unzip "pdf2htmlEX-0.18.7-poppler-0.81.0.zip" >/dev/null 2>&1
    fi

    cd "pdf2htmlEX-0.18.7-poppler-0.81.0/"
    ./dobuild >/dev/null 2>&1
    cd build
    make install >/dev/null 2>&1

    kill $progress_pid
    echo && echo -n "...100%" && echo

    if grep -q "profile.d" < "/etc/profile"
    then
        echo 'export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig' >> /etc/profile.d/pdf2htmlEX
        echo 'export LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH:-}' >> /etc/profile.d/pdf2htmlEX
        # shellcheck source=/dev/null
        source /etc/profile.d/pdf2htmlEX &>/dev/null
    else
        echo 'export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig' >> /etc/profile
        echo 'export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH' >> /etc/profile
    fi
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
        "minshi:民視"
        "mtvlivetw:MTV-Live"
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
        "mtvtw:MTV綜合電視台"
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
        "minshi:16"
        "mtvlivetw:751"
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
        "mtvtw:69"
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
            GenerateSchedule "$chnl"
            count=$((count + 1))
            echo -n $count
        done

        return
    fi

    case $2 in
        "hbo")
            printf -v today '%(%Y-%m-%d)T'

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "hbo" > "$SCHEDULE_JSON"
            fi

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
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$today&channel=$chnl&feed=cn"
                elif [ "$chnl" == "hbotw" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$today&channel=hbo&feed=satellite"
                elif [ "$chnl" == "hbored" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$today&channel=red&feed=satellite"
                elif [ "$chnl" == "cinemax" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$today&channel=$chnl&feed=satellite"
                else
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-tw/ajax/home_schedule?date=$today&channel=$chnl&feed=satellite"
                fi

                schedule=""
                while IFS= read -r program 
                do
                    program_id=${program#*id: }
                    program_id=${program_id%%, title: *}
                    program_title=${program#*, title: }
                    program_title=${program_title%%, title_local: *}
                    program_title_local=${program#*, title_local: }
                    program_title_local=${program_title_local%%, time: *}
                    program_time=${program#*, time: }
                    program_time=${program_time%%, sys_time: *}
                    program_sys_time=${program#*, sys_time: }
                    program_sys_time=${program_sys_time%\"}

                    if [ -n "$program_title_local" ] 
                    then
                        program_title="$program_title_local $program_title"
                    fi

                    [ -n "$schedule" ] && schedule="$schedule,"
                    schedule=$schedule'{
                        "id":"'"$program_id"'",
                        "title":"'"$program_title"'",
                        "time":"'"$program_time"'",
                        "sys_time":"'"$program_sys_time"'"
                    }'
                done < <($JQ_FILE 'to_entries | map("id: \(.value.id), title: \(.value.title), title_local: \(.value.title_local), time: \(.value.time), sys_time: \(.value.sys_time)")[]' <<< $(wget --no-check-certificate "$SCHEDULE_LINK" -qO-))

                if [ -z "$schedule" ] 
                then
                    echo -e "$error\n$chnl not found\n"
                else
                    JQ replace "$SCHEDULE_JSON" "$chnl" "[$schedule]"
                fi
            done
        ;;
        "hbous")
            printf -v today '%(%Y-%m-%d)T'
            sys_time=$(date -d $today +%s)
            min_sys_time=$((sys_time-7200))
            max_sys_time=$((sys_time+86400))
            yesterday=$(printf '%(%Y-%m-%d)T' $((sys_time - 86400)))

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "hbous_hbo" > "$SCHEDULE_JSON"
            fi

            chnls=(
                "hbo:HBO:EAST"
                "hbo2:HBO2:EAST"
                "hbosignature:HBO SIGNATURE:EAST"
                "hbofamily:HBO FAMILY:EAST"
                "hbocomedy:HBO COMEDY:EAST"
                "hbozone:HBO ZONE:EAST"
                "hbolatino:HBO LATINO:EAST"
                "hbo:HBO:WEST"
                "hbo2:HBO2:WEST"
                "hbosignature:HBO SIGNATURE:WEST"
                "hbofamily:HBO FAMILY:WEST"
                "hbocomedy:HBO COMEDY:WEST"
                "hbozone:HBO ZONE:WEST"
                "hbolatino:HBO LATINO:WEST" )

            if [ "${4:-}" == "WEST" ] || [ "${4:-}" == "west" ]
            then
                zone="WEST"
            else
                zone="EAST"
            fi

            hbous_yesterday_schedule=$(wget --no-check-certificate "https://proxy-v4.cms.hbo.com/v1/schedule?date=$yesterday" -qO-)
            hbous_today_schedule=$(wget --no-check-certificate "https://proxy-v4.cms.hbo.com/v1/schedule?date=$today" -qO-)

            for chnl in "${chnls[@]}" ; do
                chnl_id=${chnl%%:*}
                chnl=${chnl#*:}
                chnl_name=${chnl%:*}
                chnl_zone=${chnl#*:}

                if [ -n "${3:-}" ] 
                then
                    if [ "$3" != "$chnl_id" ] || [ "$zone" != "$chnl_zone" ]
                    then
                        continue
                    fi
                fi

                schedule=""

                while IFS="=" read -r program_time program_title
                do
                    program_time=${program_time#\"}
                    program_title=${program_title%\"}
                    program_sys_time=$(date -d "$program_time" +%s)
                    if [ "$program_sys_time" -ge "$min_sys_time" ] 
                    then
                        program_time=$(printf '%(%H:%M)T' "$program_sys_time")
                        [ -n "$schedule" ] && schedule="$schedule,"
                        schedule=$schedule'{
                            "title":"'"$program_title"'",
                            "time":"'"$program_time"'",
                            "sys_time":"'"$program_sys_time"'"
                        }'
                    fi
                done < <($JQ_FILE --arg channelName "$chnl_name" --arg channelZone "$chnl_zone" '.channels | to_entries | map(select(.value.channelName==$channelName and .value.channelZone==$channelZone))[].value.programAirings | to_entries | map("\(.value.airing.playDate)=\(.value.program.title)")[]' <<< "$hbous_yesterday_schedule")

                min_sys_time=${program_sys_time:-$sys_time}

                while IFS="=" read -r program_time program_title
                do
                    program_time=${program_time#\"}
                    program_title=${program_title%\"}
                    program_sys_time=$(date -d "$program_time" +%s)
                    if [ "$program_sys_time" -le "$max_sys_time" ] && [ "$program_sys_time" -gt "$min_sys_time" ]
                    then
                        program_time=$(printf '%(%H:%M)T' "$program_sys_time")
                        [ -n "$schedule" ] && schedule="$schedule,"
                        schedule=$schedule'{
                            "title":"'"$program_title"'",
                            "time":"'"$program_time"'",
                            "sys_time":"'"$program_sys_time"'"
                        }'
                    fi
                done < <($JQ_FILE --arg channelName "$chnl_name" --arg channelZone "$chnl_zone" '.channels | to_entries | map(select(.value.channelName==$channelName and .value.channelZone==$channelZone))[].value.programAirings | to_entries | map("\(.value.airing.playDate)=\(.value.program.title)")[]' <<< "$hbous_today_schedule")

                if [ -n "$schedule" ] 
                then
                    JQ replace "$SCHEDULE_JSON" "hbous_$chnl_id" "[$schedule]"
                fi
            done
        ;;
        "ontvtonight")
            printf -v today '%(%Y-%m-%d)T'
            sys_time=$(date -d $today +%s)
            min_sys_time=$((sys_time-7200))
            max_sys_time=$((sys_time+86400))
            yesterday=$(printf '%(%Y-%m-%d)T' $((sys_time - 86400)))

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "us_abc" > "$SCHEDULE_JSON"
            fi

            chnls=(
                "abc@abc@69048344@-04:00"
                "cbs@cbs@69048345@-04:00"
                "nbc@nbc@69048423@-04:00"
                "fox@fox@69048367@-04:00"
                "msnbc@msnbc@69023101@-04:00"
                "amc@amc-east@69047124@-04:00"
                "nickjr@nick-jr@69047681@-04:00"
                "universalkids@universal-kids@69027178@-04:00"
                "disneyjr@disney-junior-hdtv-east@69044944@-04:00"
                "mtvlive@mtv-live-hdtv@69027734@-04:00"
                "mtvlivehd@mtv-live-hdtv@69038784@+00:00"
                "mtvdance@mtv-dance@69036268@+02:00"
                "comedycentral@comedy-central-east@69036536@-04:00" )

            for chnl in "${chnls[@]}" ; do
                IFS="@" read -r chnl_id chnl_name chnl_no chnl_zone <<< "$chnl"

                if [ -n "${3:-}" ] && [ "${3:-}" != "$chnl_id" ]
                then
                    continue
                fi

                schedule=""
                start=0

                if [ "$chnl_id" == "mtvdance" ] 
                then
                    uk="uk/"
                else
                    uk=""
                fi

                while IFS= read -r line
                do
                    if [[ $line == *"<tbody>"* ]] 
                    then
                        start=1
                    elif [ "$start" == 1 ] && [[ $line == *"<h5"* ]] && [[ $line == *"</h5>"* ]]
                    then
                        line=${line#*>}
                        program_time=${line%<*}
                        new_program_time=${program_time% *}
                        hour=${new_program_time%:*}
                        if [ "${program_time#* }" == "pm" ] && [ "$hour" -lt 12 ]
                        then
                            hour=$((hour+12))
                            new_program_time="$hour:${new_program_time#*:}"
                        elif [ "${program_time#* }" == "am" ] && [ "$hour" -eq 12 ]
                        then
                            new_program_time="00:${new_program_time#*:}"
                        fi
                    elif [ "$start" == 1 ] && [[ $line == *"</a></h5>"* ]] 
                    then
                        line=${line%%<\/a>*}
                        lead=${line%%[^[:blank:]]*}
                        program_title=${line#${lead}}
                        program_title=${program_title//amp;/}
                        program_title=${program_title//&#039;/\'}
                        program_sys_time=$(date -d "${yesterday}T$new_program_time$chnl_zone" +%s)
                        if [ "$program_sys_time" -ge "$min_sys_time" ] 
                        then
                            program_time=$(printf '%(%H:%M)T' "$program_sys_time")
                            [ -n "$schedule" ] && schedule="$schedule,"
                            schedule=$schedule'{
                                "title":"'"$program_title"'",
                                "time":"'"$program_time"'",
                                "sys_time":"'"$program_sys_time"'"
                            }'
                        fi
                    elif [ "$start" == 1 ] && [[ $line == *"</tbody>"* ]] 
                    then
                        break
                    fi
                done < <(wget --no-check-certificate "https://www.ontvtonight.com/${uk}guide/listings/channel/$chnl_no/$chnl_name.html?dt=$yesterday" -qO-)

                while IFS= read -r line
                do
                    if [[ $line == *"<tbody>"* ]] 
                    then
                        start=1
                    elif [ "$start" == 1 ] && [[ $line == *"<h5"* ]] && [[ $line == *"</h5>"* ]] 
                    then
                        line=${line#*>}
                        program_time=${line%<*}
                        new_program_time=${program_time% *}
                        hour=${new_program_time%:*}
                        if [ "${program_time#* }" == "pm" ] && [ "$hour" -lt 12 ]
                        then
                            hour=$((hour+12))
                            new_program_time="$hour:${new_program_time#*:}"
                        elif [ "${program_time#* }" == "am" ] && [ "$hour" -eq 12 ]
                        then
                            new_program_time="00:${new_program_time#*:}"
                        fi
                    elif [ "$start" == 1 ] && [[ $line == *"</a></h5>"* ]] 
                    then
                        line=${line%%<\/a>*}
                        lead=${line%%[^[:blank:]]*}
                        program_title=${line#${lead}}
                        program_title=${program_title//amp;/}
                        program_title=${program_title//&#039;/\'}
                        program_sys_time=$(date -d "${today}T$new_program_time$chnl_zone" +%s)
                        if [ "$program_sys_time" -le "$max_sys_time" ] 
                        then
                            program_time=$(printf '%(%H:%M)T' "$program_sys_time")
                            [ -n "$schedule" ] && schedule="$schedule,"
                            schedule=$schedule'{
                                "title":"'"$program_title"'",
                                "time":"'"$program_time"'",
                                "sys_time":"'"$program_sys_time"'"
                            }'
                        fi
                    elif [ "$start" == 1 ] && [[ $line == *"</tbody>"* ]] 
                    then
                        break
                    fi
                done < <(wget --no-check-certificate "https://www.ontvtonight.com/${uk}guide/listings/channel/$chnl_no/$chnl_name.html?dt=$today" -qO-)

                if [ "$chnl_id" != "mtvlivehd" ] && [ "$chnl_id" != "mtvdance" ]
                then
                    chnl_id="us_$chnl_id"
                fi

                if [ -n "$schedule" ] 
                then
                    JQ replace "$SCHEDULE_JSON" "$chnl_id" "[$schedule]"
                fi
            done
        ;;
        "disney")
            printf -v today '%(%Y%m%d)T'
            SCHEDULE_LINK="https://disney.com.tw/_schedule/full/$today/8/%2Fepg"

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "$2" > "$SCHEDULE_JSON"
            fi

            schedule=""
            while IFS= read -r program 
            do
                program_title=${program#*show_title: }
                program_title=${program_title%%, time: *}
                program_time=${program#*, time: }
                program_time=${program_time%%, iso8601_utc_time: *}
                program_sys_time=${program#*, iso8601_utc_time: }
                program_sys_time=${program_sys_time%\"}
                program_sys_time=$(date -d "$program_sys_time" +%s)

                [ -n "$schedule" ] && schedule="$schedule,"
                schedule=$schedule'{
                    "title":"'"$program_title"'",
                    "time":"'"$program_time"'",
                    "sys_time":"'"$program_sys_time"'"
                }'
            done < <($JQ_FILE '.schedule | to_entries | map(.value.schedule_items[]) | to_entries | map("show_title: \(.value.show_title), time: \(.value.time), iso8601_utc_time: \(.value.iso8601_utc_time)")[]' <<< $(wget --no-check-certificate "$SCHEDULE_LINK" -qO-))

            if [ -z "$schedule" ] 
            then
                echo -e "$error\nnot found\n"
            else
                JQ replace "$SCHEDULE_JSON" "$2" "[$schedule]"
            fi
        ;;
        "foxmovies")
            printf -v today '%(%Y-%-m-%-d)T'
            SCHEDULE_LINK="https://www.fng.tw/foxmovies/program.php?go=$today"

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "$2" > "$SCHEDULE_JSON"
            fi

            schedule=""
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
                        sys_time=$(date -d "$today $time" +%s)
                        [ -n "$schedule" ] && schedule="$schedule,"
                        schedule=$schedule'{
                            "title":"'"$line"'",
                            "time":"'"$time"'",
                            "sys_time":"'"$sys_time"'"
                        }'
                    else
                        time=${line#* }
                    fi
                fi
            done < <(wget --no-check-certificate "$SCHEDULE_LINK" -qO-)

            if [ -z "$schedule" ] 
            then
                echo -e "$error\nnot found\n"
            else
                JQ replace "$SCHEDULE_JSON" "$2" "[$schedule]"
            fi
        ;;
        "amlh")
            printf -v today '%(%Y-%-m-%-d)T'
            timestamp=$(date -d $today +%s)

            TODAY_SCHEDULE_LINK="http://wap.lotustv.cc/wap.php/Sub/program/d/$timestamp"
            YESTERDAY_SCHEDULE_LINK="http://wap.lotustv.cc/wap.php/Sub/program/d/$((timestamp-86400))"

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "$2" > "$SCHEDULE_JSON"
            fi

            found=0
            schedule=""
            replace=""

            while IFS= read -r line
            do
                if [[ $line == *"program_list"* ]] 
                then
                    found=1
                elif [ "$found" == 1 ] && [[ $line == *"<li>"* ]] 
                then
                    line=${line#*<em>}
                    time=${line%%<\/em>*}
                    while [ -n "$time" ] 
                    do
                        time=${time:0:5}
                        line=${line#*<span>}
                        if [ "${flag:-0}" -gt 0 ] && [ "${time:0:1}" == 0 ]
                        then
                            title=${line%%<\/span>*}
                            [ -z "$replace" ] && replace="${title:4:1}"
                            title="${title//$replace/ }"
                            if [ "${title:0:4}" == "經典影院" ] 
                            then
                                title=${title:5}
                            fi
                            sys_time=$(date -d "$today $time" +%s)
                            [ -n "$schedule" ] && schedule="$schedule,"
                            schedule=$schedule'{
                                "title":"'"$title"'",
                                "time":"'"$time"'",
                                "sys_time":"'"$sys_time"'"
                            }'
                        else
                            flag=${time:0:1}
                        fi
                        if [[ $line == *"<em>"* ]] 
                        then
                            line=${line#*<em>}
                            time=${line%%<\/em>*}
                        else
                            break
                        fi
                    done
                    break
                fi
            done < <(wget --no-check-certificate "$YESTERDAY_SCHEDULE_LINK" -qO-)

            flag=0
            found=0

            while IFS= read -r line
            do
                if [[ $line == *"program_list"* ]] 
                then
                    found=1
                elif [ "$found" == 1 ] && [[ $line == *"<li>"* ]] 
                then
                    line=${line#*<em>}
                    time=${line%%<\/em>*}
                    while [ -n "$time" ] 
                    do
                        time=${time:0:5}
                        line=${line#*<span>}
                        if [ ! "$flag" -gt "${time:0:1}" ]
                        then
                            flag=${time:0:1}
                            title=${line%%<\/span>*}
                            title="${title//$replace/ }"
                            if [ "${title:0:4}" == "經典影院" ] 
                            then
                                title=${title:5}
                            fi
                            sys_time=$(date -d "$today $time" +%s)
                            [ -n "$schedule" ] && schedule="$schedule,"
                            schedule=$schedule'{
                                "title":"'"$title"'",
                                "time":"'"$time"'",
                                "sys_time":"'"$sys_time"'"
                            }'
                        else
                            break 2
                        fi
                        line=${line#*<em>}
                        time=${line%%<\/em>*}
                    done
                    break
                fi
            done < <(wget --no-check-certificate "$TODAY_SCHEDULE_LINK" -qO-)

            if [ -z "$schedule" ] 
            then
                echo -e "$error\nnot found\n"
            else
                JQ replace "$SCHEDULE_JSON" "$2" "[$schedule]"
            fi
        ;;
        "tvbhk")
            printf -v today '%(%Y-%m-%d)T'
            sys_time=$(date -d $today +%s)
            max_sys_time=$((sys_time+86400))
            yesterday=$(printf '%(%Y-%m-%d)T' $((sys_time - 86400)))

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "tvbhk_pearl" > "$SCHEDULE_JSON"
            fi

            chnls=(
                "pearl:P"
                "jade:J"
                "j2:B"
                "news:C"
                "finance:A"
                "xinghe:X" )

            for chnl in "${chnls[@]}" ; do
                chnl_name=${chnl%:*}
                chnl_code=${chnl#*:}

                if [ -n "${3:-}" ] && [ "$3" != "$chnl_name" ] 
                then
                    continue
                fi

                schedule=""

                while IFS= read -r line
                do
                    if [[ $line == *"<li"* ]] 
                    then
                        while [[ $line == *"<li"* ]] 
                        do
                            line=${line#*time=\"}
                            program_sys_time=${line%%\"*}
                            if [ "$program_sys_time" -ge "$sys_time" ]
                            then
                                line=${line#*<span class=\"time\">}
                                program_time=${line%%</span>*}
                                line=${line#*<p class=\"ftit\">}
                                if [ "${line:0:7}" == "<a href" ] 
                                then
                                    line=${line#*>}
                                fi
                                program_title=${line%%</p>*}
                                program_title=${program_title%% <cite*}
                                program_title=${program_title%%</a>*}
                                program_title=${program_title%%<em *}
                                program_title=${program_title//&nbsp;/ }
                                [ -n "$schedule" ] && schedule="$schedule,"
                                schedule=$schedule'{
                                    "title":"'"$program_title"'",
                                    "time":"'"$program_time"'",
                                    "sys_time":"'"$program_sys_time"'"
                                }'
                            fi
                        done
                        break
                    fi
                done < <(wget --no-check-certificate "https://programme.tvb.com/ajax.php?action=channellist&code=$chnl_code&date=$yesterday" -qO-)

                while IFS= read -r line
                do
                    if [[ $line == *"<li"* ]] 
                    then
                        while [[ $line == *"<li"* ]] 
                        do
                            line=${line#*time=\"}
                            program_sys_time=${line%%\"*}
                            if [ "$program_sys_time" -ge "$sys_time" ] && [ "$program_sys_time" -le "$max_sys_time" ]
                            then
                                line=${line#*<span class=\"time\">}
                                program_time=${line%%</span>*}
                                line=${line#*<p class=\"ftit\">}
                                if [ "${line:0:7}" == "<a href" ] 
                                then
                                    line=${line#*>}
                                fi
                                program_title=${line%%</p>*}
                                program_title=${program_title%% <cite*}
                                program_title=${program_title%%</a>*}
                                program_title=${program_title%%<em *}
                                program_title=${program_title//&nbsp;/ }
                                [ -n "$schedule" ] && schedule="$schedule,"
                                schedule=$schedule'{
                                    "title":"'"$program_title"'",
                                    "time":"'"$program_time"'",
                                    "sys_time":"'"$program_sys_time"'"
                                }'
                            fi
                        done
                        break
                    fi
                done < <(wget --no-check-certificate "https://programme.tvb.com/ajax.php?action=channellist&code=$chnl_code&date=$today" -qO-)

                if [ -n "$schedule" ] 
                then
                    JQ replace "$SCHEDULE_JSON" "tvbhk_$chnl_name" "[$schedule]"
                fi
            done
        ;;
        "tvbhd")
            if [[ ! -x $(command -v pdf2htmlEX) ]] 
            then
                echo && echo "需要先安装 pdf2htmlEX，因为是编译 pdf2htmlEX，耗时会很长，是否继续？[y/N]"
                read -p "(默认: N): " pdf2html_install_yn
                pdf2html_install_yn=${pdf2html_install_yn:-N}
                if [[ $pdf2html_install_yn == [Yy] ]] 
                then
                    InstallPdf2html
                    echo && echo -e "$info pdf2htmlEX 安装完成" && echo
                    if ! pdf2htmlEX -v > /dev/null 2>&1
                    then
                        echo -e "$info 请先输入 source /etc/profile 以启用 pdf2htmlEX" && echo && exit 1
                    fi
                else
                    echo && echo "已取消..." && echo && exit 1
                fi
            fi

            wget --timeout=10 --tries=3 --no-check-certificate "https://schedule.tvbusa.com/current/tvb_hd.pdf" -qO "$IPTV_ROOT/tvb_hd.pdf"
            cd "$IPTV_ROOT"
            pdf2htmlEX --zoom 1.3 "./tvb_hd.pdf"

            printf -v today '%(%Y-%m-%d)T'
            sys_time=$(date -d $today +%s)
            yesterday=$(printf '%(%Y-%m-%d)T' $((sys_time - 86400)))

            weekday_program_title=()
            weekday_program_time=()
            saturday_program_title=()
            saturday_program_time=()
            sunday_program_title=()
            sunday_program_time=()

            while IFS= read -r line 
            do
                if [[ $line == *"節目表"* ]] 
                then
                    line=${line#*"星期日"}
                    line=${line#*"日期"}
                    line=${line//"<span class=\"_ _28\"></span>"/}
                    line=${line//"<div class=\"t m0 x10 ha ya ff2 fs3 fc0 sc0 ls0 ws0\">11:30</div></div>"/}
                    old_program_time=""
                    skips=(
                        "4:sunday"
                        "6:weekday sunday"
                        "8:saturday sunday"
                        "10:saturday sunday"
                        "11:weekday"
                        "12:weekday saturday"
                        "13:saturday sunday"
                        "15:weekday"
                        "16:saturday sunday"
                        "17:saturday sunday"
                        "18:weekday"
                        "19:saturday sunday"
                        "24:saturday sunday"
                        "25:weekday saturday"
                        "26:sunday"
                        "27:sunday"
                        "28:saturday"
                        "29:weekday sunday"
                        "30:saturday"
                        "31:sunday"
                        "32:weekday sunday"
                        "33:saturday"
                        "34:sunday"
                        "36:saturday sunday"
                        "37:weekday"
                        "38:sunday"
                        "39:weekday saturday"
                        "40:sunday"
                        "41:saturday"
                        "42:weekday sunday"
                        "43:saturday sunday"
                        "44:saturday sunday"
                        "46:weekday sunday"
                        "47:weekday"
                        "48:saturday sunday"
                        "50:saturday sunday"
                        "51:weekday"
                        "52:saturday sunday"
                        "53:weekday"
                        "54:saturday sunday"
                        "56:saturday"
                        "57:sunday"
                        "58:saturday"
                        "59:weekday sunday"
                        "60:saturday"
                        "61:sunday"
                        "62:weekday"
                        "63:saturday sunday"
                        "64:weekday"
                        "65:saturday sunday"
                        "66:saturday sunday"
                    )
                    loop=1
                    count=0
                    day="weekday"
                    while true 
                    do
                        class=${line%%\">*}
                        class=${class#*<div class=\"}
                        line=${line#*>}
                        content=${line%%<*}

                        case $content in
                            ""|" "|"AM"|"PM"|"東岸"|"西岸"|"星期日"|"星期一"|"星期二至六"|"日期"|"Next Day") continue
                            ;;
                            *"夏令時間"*) continue
                            ;;
                            *"將時鐘"*) continue
                            ;;
                            "高清台") 
                                if [[ -n ${program_title:-} ]] 
                                then
                                    if [[ -n ${program_start_date:-} ]] 
                                    then
                                        program_title="$program_title $program_start_date"
                                    fi
                                    program_title=${program_title//amp;/}
                                    program_title=${program_title//&#039;/\'}
                                    if [ "$day" == "weekday" ] 
                                    then
                                        if [[ -n $old_program_time ]] 
                                        then
                                            weekday_program_title+=("$program_title")
                                            weekday_program_time+=("$old_program_time")
                                        else
                                            index=${#weekday_program_title[@]}
                                            index=$((index-1))
                                            weekday_program_title[index]="${weekday_program_title[index]} $program_title"
                                        fi
                                    elif [ "$day" == "saturday" ] 
                                    then
                                        if [[ -n $old_program_time ]] 
                                        then
                                            saturday_program_title+=("$program_title")
                                            saturday_program_time+=("$old_program_time")
                                        else
                                            index=${#saturday_program_title[@]}
                                            index=$((index-1))
                                            saturday_program_title[index]="${saturday_program_title[index]} $program_title"
                                        fi
                                    elif [ "$day" == "sunday" ] 
                                    then
                                        if [[ -n $old_program_time ]] 
                                        then
                                            sunday_program_title+=("$program_title")
                                            sunday_program_time+=("$old_program_time")
                                        else
                                            index=${#sunday_program_title[@]}
                                            index=$((index-1))
                                            sunday_program_title[index]="${sunday_program_title[index]} $program_title"
                                        fi
                                    fi
                                    program_title=""
                                    old_program_time=""
                                    program_sys_time=""
                                    program_start_date=""
                                fi
                                break
                            ;;
                            *) 
                                if [[ ${content:1:1} == "/" ]] && [[ ! ${content:0:1} == *[!0-9]* ]] && [[ ! ${content:2} == *[!0-9]* ]] 
                                then
                                    program_start_date=$content
                                elif [[ ${content:2:1} == "/" ]] && [[ ! ${content:0:2} == *[!0-9]* ]] && [[ ! ${content:3} == *[!0-9]* ]] 
                                then
                                    program_start_date=$content
                                elif [[ ${content:1:1} == ":" ]] 
                                then
                                    if [[ ! ${content:0:1} == *[!0-9]* ]] && [[ ! ${content:2} == *[!0-9]* ]] 
                                    then
                                        [ -n "${program_time:-}" ] && program_time=""
                                        if [[ -z ${program_time_east:-} ]] 
                                        then
                                            program_time_east=$content
                                        else
                                            program_time=$content
                                            program_time_east=""
                                        fi
                                    fi
                                elif [[ ${content:2:1} == ":" ]] 
                                then
                                    if [[ ! ${content:0:2} == *[!0-9]* ]] && [[ ! ${content:3} == *[!0-9]* ]] 
                                    then
                                        [ -n "${program_time:-}" ] && program_time=""
                                        if [[ -z ${program_time_east:-} ]] 
                                        then
                                            program_time_east=$content
                                        else
                                            program_time=$content
                                            program_time_east=""
                                        fi
                                    fi
                                else
                                    old_day=$day

                                    if [ "$count" -gt 0 ] 
                                    then
                                        if [ "$old_day" == "sunday" ] 
                                        then
                                            day="weekday"
                                        elif [ "$old_day" == "weekday" ] 
                                        then
                                            day="saturday"
                                        elif [ "$old_day" == "saturday" ] 
                                        then
                                            day="sunday"
                                        fi
                                    fi

                                    count=$((count+1))
                                    if [[ $((count % 3)) -eq 0 ]] 
                                    then
                                        loop=$((count/3))
                                    else
                                        loop=$((count/3 + 1))
                                    fi

                                    redo=1
                                    while [ "$redo" -eq 1 ] 
                                    do
                                        redo=0
                                        for skip in "${skips[@]}"
                                        do
                                            if [ "${skip%:*}" == "$loop" ] 
                                            then
                                                redo=1
                                                IFS=" " read -ra days <<< "${skip#*:}"
                                                for ele in "${days[@]}"
                                                do
                                                    if [ "$ele" == "$day" ] 
                                                    then
                                                        count=$((count+1))
                                                        if [ "$day" == "sunday" ] 
                                                        then
                                                            day="weekday"
                                                        elif [ "$day" == "weekday" ] 
                                                        then
                                                            day="saturday"
                                                        elif [ "$day" == "saturday" ] 
                                                        then
                                                            day="sunday"
                                                        fi
                                                    fi
                                                done
                                                if [[ $((count % 3)) -eq 0 ]] 
                                                then
                                                    new_loop=$((count/3))
                                                else
                                                    new_loop=$((count/3 + 1))
                                                fi
                                                if [ "$new_loop" == "$loop" ] 
                                                then
                                                    redo=0
                                                else
                                                    loop=$new_loop
                                                fi
                                                break
                                            fi
                                        done
                                    done

                                    case $((count%3)) in
                                        0) day="sunday"
                                        ;;
                                        1) day="weekday"
                                        ;;
                                        2) day="saturday"
                                        ;;
                                    esac

                                    if [[ -n ${program_title:-} ]] 
                                    then
                                        if [[ -n ${program_start_date:-} ]] 
                                        then
                                            program_title="$program_title $program_start_date"
                                        fi
                                        program_title=${program_title//amp;/}
                                        program_title=${program_title//&#039;/\'}
                                        if [ "$old_day" == "weekday" ] 
                                        then
                                            if [[ -n $old_program_time ]] 
                                            then
                                                weekday_program_title+=("$program_title")
                                                weekday_program_time+=("$old_program_time")
                                            else
                                                index=${#weekday_program_title[@]}
                                                index=$((index-1))
                                                weekday_program_title[index]="${weekday_program_title[index]} $program_title"
                                            fi
                                        elif [ "$old_day" == "saturday" ] 
                                        then
                                            if [[ -n $old_program_time ]] 
                                            then
                                                saturday_program_title+=("$program_title")
                                                saturday_program_time+=("$old_program_time")
                                            else
                                                index=${#saturday_program_title[@]}
                                                index=$((index-1))
                                                saturday_program_title[index]="${saturday_program_title[index]} $program_title"
                                            fi
                                        elif [ "$old_day" == "sunday" ] 
                                        then
                                            if [[ -n $old_program_time ]] 
                                            then
                                                sunday_program_title+=("$program_title")
                                                sunday_program_time+=("$old_program_time")
                                            else
                                                index=${#sunday_program_title[@]}
                                                index=$((index-1))
                                                sunday_program_title[index]="${sunday_program_title[index]} $program_title"
                                            fi
                                        fi
                                        program_title=""
                                        old_program_time=""
                                        program_start_date=""
                                    fi

                                    if [ -n "${program_time_east:-}" ] 
                                    then
                                        program_time=$program_time_east
                                        program_time_east=""
                                    fi

                                    program_title=$content

                                    if [ -n "$program_time" ] 
                                    then
                                        old_program_time=$program_time
                                        program_time=""
                                    fi
                                fi
                            ;;
                        esac
                    done
                    break
                fi
            done < "./tvb_hd.html"
            weekday=$(printf '%(%u)T')
            if [ "$weekday" == 1 ] 
            then
                p_title=("${sunday_program_title[@]}")
                p_time=("${sunday_program_time[@]}")
            elif [ "$weekday" == 0 ] 
            then
                p_title=("${saturday_program_title[@]}")
                p_time=("${saturday_program_time[@]}")
            else
                p_title=("${weekday_program_title[@]}")
                p_time=("${weekday_program_time[@]}")
            fi

            if [ ! -s "$SCHEDULE_JSON" ] 
            then
                printf '{"%s":[]}' "tvbhd" > "$SCHEDULE_JSON"
            fi

            schedule=""
            change=0
            date=$yesterday
            for((i=0;i<${#p_time[@]};i++));
            do
                [ -n "${program_time:-}" ] && program_time_old=$program_time

                program_time=${p_time[i]}

                if [ -n "${program_time_old:-}" ] &&[ "${program_time%:*}" -lt "${program_time_old%:*}" ]
                then
                    change=$((change+1))
                fi

                if [ "$change" == 1 ] 
                then
                    hour=${program_time%:*}
                    hour=$((hour+12))
                    if [ "$hour" -eq 24 ] 
                    then
                        hour="0"
                        date=$today
                    fi
                    new_program_time="$hour:${program_time#*:}"
                elif [ "$change" == 2 ] 
                then
                    date=$today
                    new_program_time=$program_time
                else
                    new_program_time=$program_time
                fi

                if [[ ${new_program_time:1:1} == ":" ]] 
                then
                    new_program_time="0$new_program_time"
                else
                    new_program_time=$new_program_time
                fi

                program_sys_time=$(date -d "${date}T$new_program_time-08:00" +%s)
                new_program_time=$(printf '%(%H:%M)T' "$program_sys_time")

                program_title=${p_title[i]}

                [ -n "$schedule" ] && schedule="$schedule,"
                schedule=$schedule'{
                    "title":"'"$program_title"'",
                    "time":"'"$new_program_time"'",
                    "sys_time":"'"$program_sys_time"'"
                }'
            done

            if [ -n "$schedule" ] 
            then
                JQ replace "$SCHEDULE_JSON" "tvbhd" "[$schedule]"
            fi
        ;;
        *) 
            found=0
            for chnl in "${chnls[@]}" ; do
                chnl_id=${chnl%%:*}
                if [ "$chnl_id" == "$2" ] 
                then
                    found=1
                    GenerateSchedule "$2"
                    break
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
                        GenerateScheduleNiotv "$chnl_niotv_num"
                        break
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
                        GenerateScheduleNowtv "$chnl_nowtv_num"
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
                    /usr/local/bin/imgcat --half-height "$IMG_FILE"
                    rm -rf "${IMG_FILE:-notfound}"
                    echo && echo -e "$info 输入图片验证码："
                    read -p "(默认: 刷新验证码): " pincode
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
                /usr/local/bin/imgcat --half-height "$IMG_FILE"
                rm -rf "${IMG_FILE:-notfound}"
                echo && echo -e "$info 输入图片验证码："
                read -p "(默认: 刷新验证码): " pincode
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
        echo && echo -e "$error 缺少 imgcat ,是否现在安装? [y/N]"
        read -p "(默认: 取消): " imgcat_yn
        imgcat_yn=${imgcat_yn:-N}
        if [[ $imgcat_yn == [Yy] ]] 
        then
            Progress &
            progress_pid=$!
            CheckRelease
            if [ "$release" == "rpm" ] 
            then
                yum -y install gcc gcc-c++ ncurses-devel >/dev/null 2>&1
                echo -n "...50%..."
            else
                apt-get -y update >/dev/null 2>&1
                apt-get -y install debconf-utils libncurses5-dev >/dev/null 2>&1
                echo '* libraries/restart-without-asking boolean true' | debconf-set-selections
                apt-get -y install software-properties-common pkg-config build-essential >/dev/null 2>&1
                echo -n "...50%..."
            fi

            cd ~

            if [ ! -e "./imgcat-master" ] 
            then
                wget --timeout=10 --tries=3 --no-check-certificate "$FFMPEG_MIRROR_LINK/imgcat.zip" -qO "imgcat.zip"
                unzip "imgcat.zip" >/dev/null 2>&1
            fi

            cd "./imgcat-master"
            autoconf >/dev/null 2>&1
            ./configure >/dev/null 2>&1
            make >/dev/null 2>&1
            make install >/dev/null 2>&1
            kill $progress_pid
            echo -n "...100%" && echo && echo -e "$info imgcat 安装完成"
        else
            echo && echo "已取消..." && echo && exit 1
        fi
    fi
    not_unique=1
    while [ "$not_unique" != 0 ] 
    do
        echo && echo -e "$info 输入账号："
        read -p "(默认: 取消): " account
        [ -z "$account" ] && echo && echo "已取消..." && echo && exit 1
        if [ -z "${ts_array[unique_url]:-}" ] 
        then
            not_unique=0
        else
            TsIsUnique
        fi
    done

    echo && echo -e "$info 输入密码："
    read -p "(默认: 取消): " password
    [ -z "$password" ] && echo && echo "已取消..." && echo && exit 1

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
                    read -p "(默认: 取消): " smscode
                    [ -z "$smscode" ] && echo && echo "已取消..." && echo && exit 1

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
                        printf -v timestamp '%(%s)T'
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
                            echo && echo -e "$info 是否登录账号? [y/N]"
                            read -p "(默认: N): " login_yn
                            login_yn=${login_yn:-N}
                            if [[ $login_yn == [Yy] ]]
                            then
                                TsLogin
                            else
                                echo && echo "已取消..." && echo && exit 1
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
            echo && echo -e "$info 是否登录账号? [y/N]"
            read -p "(默认: N): " login_yn
            login_yn=${login_yn:-N}
            if [[ $login_yn == [Yy] ]]
            then
                TsLogin
            else
                echo && echo "已取消..." && echo && exit 1
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
        read -p "(默认: 取消): " account
        [ -z "$account" ] && echo && echo "已取消..." && echo && exit 1
    fi

    if [ -z "${password:-}" ] 
    then
        echo && echo -e "$info 输入密码："
        read -p "(默认: 取消): " password
        [ -z "$password" ] && echo && echo "已取消..." && echo && exit 1
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
        printf -v timestamp '%(%s)T'
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
        echo && echo -e "$info 是否注册账号? [y/N]"
        read -p "(默认: N): " register_yn
        register_yn=${register_yn:-N}
        if [[ $register_yn == [Yy] ]]
        then
            TsRegister
        else
            echo && echo "已取消..." && echo && exit 1
        fi
    else
        while :; do
            echo && echo -e "$info 输入需要转换的频道号码："
            read -p "(默认: 取消): " programid
            [ -z "$programid" ] && echo && echo "已取消..." && echo && exit 1
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
                    TS_LINK="${ts_array[play_url]}?playtype=live&protocol=http&accesstoken=${login_array[access_token]}&playtoken=$playtoken&verifycode=${login_array[device_id]}&rate=org&programid=$programid"
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
            TS_LINK="${ts_array[play_url]}?playtype=live&protocol=http&accesstoken=${login_array[access_token]}&playtoken=ABCDEFGH&verifycode=${login_array[device_id]}&rate=org&programid=$programid"
        fi

        echo && echo -e "$info ts链接：\n$TS_LINK"

        stream_link=$($JQ_FILE -r --arg a "programid=$programid" '[.channels[].stream_link] | map(select(test($a)))[0]' "$CHANNELS_FILE")
        if [ "${stream_link:-}" != null ]
        then
            echo && echo -e "$info 检测到此频道原有链接，是否替换成新的ts链接? [Y/n]"
            read -p "(默认: Y): " change_yn
            change_yn=${change_yn:-Y}
            if [[ $change_yn == [Yy] ]]
            then
                JQ update "$CHANNELS_FILE" '(.channels[]|select(.stream_link=="'"$stream_link"'")|.stream_link)="'"$TS_LINK"'"'
                echo && echo -e "$info 修改成功 !" && echo
            else
                echo && echo "已取消..." && echo && exit 1
            fi
        fi
    fi
}

TsMenu()
{
    GetDefault

    echo && echo -e "$info 是否使用默认频道文件? 默认链接: $DEFAULT_CHANNELS_LINK [Y/n]"
    read -p "(默认: Y): " use_default_channels_yn
    use_default_channels_yn=${use_default_channels_yn:-Y}
    if [[ $use_default_channels_yn == [Yy] ]]
    then
        TS_CHANNELS_LINK=$DEFAULT_CHANNELS_LINK
    else
        if [ -n "$d_sync_file" ] && [[ -n $($JQ_FILE '.data[] | select(.reg_url != null)' "${d_sync_file%% *}") ]] 
        then
            echo && echo -e "$info 是否使用本地频道文件? 本地路径: ${d_sync_file%% *} [Y/n]"
            read -p "(默认: Y): " use_local_channels_yn
            use_local_channels_yn=${use_local_channels_yn:-Y}
            if [[ $use_local_channels_yn == [Yy] ]] 
            then
                TS_CHANNELS_FILE=${d_sync_file%% *}
            fi
        fi
        if [ -z "${TS_CHANNELS_FILE:-}" ]
        then
            echo && echo -e "$info 请输入使用的频道文件链接或本地路径: " && echo
            read -p "(默认: 取消): " TS_CHANNELS_LINK_OR_FILE
            [ -z "$TS_CHANNELS_LINK_OR_FILE" ] && echo && echo "已取消..." && echo && exit 1
            if [ "${TS_CHANNELS_LINK_OR_FILE:0:4}" == "http" ] 
            then
                TS_CHANNELS_LINK=$TS_CHANNELS_LINK_OR_FILE
            else
                [ ! -e "$TS_CHANNELS_LINK_OR_FILE" ] && echo && echo "文件不存在，已取消..." && echo && exit 1
                TS_CHANNELS_FILE=$TS_CHANNELS_LINK_OR_FILE
            fi
        fi
    fi

    if [ -z "${TS_CHANNELS_LINK:-}" ] 
    then
        ts_channels=$(< "$TS_CHANNELS_FILE")
    else
        ts_channels=$(wget --no-check-certificate "$TS_CHANNELS_LINK" -qO-)

        [ -z "$ts_channels" ] && echo && echo -e "$error 无法连接文件地址，已取消..." && echo && exit 1
    fi

    ts_channels_desc=()
    while IFS='' read -r desc 
    do
        ts_channels_desc+=("$desc")
    done < <($JQ_FILE -r '.data[] | select(.reg_url != null) | .desc | @sh' <<< "$ts_channels")
    
    count=${#ts_channels_desc[@]}

    echo && echo -e "$info 选择需要操作的直播源" && echo
    for((i=0;i<count;i++));
    do
        desc=${ts_channels_desc[i]//\"/}
        desc=${desc//\'/}
        desc=${desc//\\/\'}
        echo -e "$green$((i+1)).$plain $desc"
    done
    
    while :; do
        echo && read -p "(默认: 取消): " channel_id
        [ -z "$channel_id" ] && echo && echo "已取消..." && echo && exit 1
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
                read -p "(默认: 取消): " jxtvnet_lane
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
                    *) echo && echo "已取消..." && echo && exit 1
                    ;;
                esac
            fi

            echo && echo -e "$info 选择操作

  ${green}1.$plain 登录以获取ts链接
  ${green}2.$plain 注册账号"
            echo && read -p "(默认: 取消): " channel_act
            [ -z "$channel_act" ] && echo && echo "已取消..." && echo && exit 1
            
            case $channel_act in
                1) TsLogin
                ;;
                2) TsRegister
                ;;
                *) echo && echo "已取消..." && echo && exit 1
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
    trap '' HUP INT TERM QUIT
    trap 'MonitorError $LINENO' ERR
    printf '%s' "$BASHPID" > "$IP_PID"

    ips=()
    jail_time=()

    if [ -s "$IP_DENY" ]  
    then
        while IFS= read -r line
        do
            if [[ $line == *:* ]] 
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
            printf -v now '%(%s)T'

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

                printf '%s' "" > "$IP_DENY"

                for((i=0;i<${#ips[@]};i++));
                do
                    printf '%s\n' "${ips[i]}:${jail_time[i]}" >> "$IP_DENY"
                done
            fi
        else
            printf '%s' "" > "$IP_DENY"
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
            map_seg_count=${map_seg_count%\"}

            chnls_output_dir_name+=("$map_output_dir_name")
            chnls_seg_length+=("$map_seg_length")
            chnls_seg_count+=("$map_seg_count")
        done < <($JQ_FILE '.channels | to_entries | map("output_dir_name: \(.value.output_dir_name), seg_length: \(.value.seg_length), seg_count: \(.value.seg_count)") | .[]' "$CHANNELS_FILE")

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
        
        printf -v now '%(%s)T'
        jail=$((now + anti_ddos_seconds))

        while IFS=' ' read -r counts ip access_file
        do
            if [[ $access_file == *".ts" ]] 
            then
                seg_name=${access_file##*/}
                access_file=${access_file%/*}
                dir_name=${access_file##*/}
                access_file=${access_file%/*}
                to_ban=0

                if [ -e "$LIVE_ROOT/$dir_name/$seg_name" ] 
                then
                    output_dir_name=$dir_name
                    to_ban=1
                elif [ -e "$LIVE_ROOT/${access_file##*/}/$dir_name/$seg_name" ] 
                then
                    output_dir_name=${access_file##*/}
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
                            printf -v date_now '%(%m-%d %H:%M:%S)T'
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
            printf -v now '%(%s)T'

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

                printf '%s' "" > "$IP_DENY"

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
        read -p "(默认: Y): " anti_ddos
        anti_ddos=${anti_ddos:-Y}
        if [[ $anti_ddos == [Yy] ]] 
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
            while read -p "(默认: $d_anti_ddos_port): " anti_ddos_port
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
            while read -p "(默认: $d_anti_ddos_seconds秒): " anti_ddos_seconds
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
            while read -p "(默认: $d_anti_ddos_level): " anti_ddos_level
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

            JQ update "$CHANNELS_FILE" '(.default|.anti_ddos_port)='"$anti_ddos_port"'|(.default|.anti_ddos_seconds)='"$anti_ddos_seconds"'|(.default|.anti_ddos_level)='"$anti_ddos_level"''

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
    printf -v date_now '%(%m-%d %H:%M:%S)T'
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
                        if [[ $line == *:* ]] 
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
                        printf -v now '%(%s)T'

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

                            printf '%s' "" > "$IP_DENY"

                            for((i=0;i<${#ips[@]};i++));
                            do
                                printf '%s\n' "${ips[i]}:${jail_time[i]}" >> "$IP_DENY"
                            done
                        fi
                    else
                        printf '%s' "" > "$IP_DENY"
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
    printf -v date_now '%(%m-%d %H:%M:%S)T'
    printf '%s\n' "$date_now [LINE:$1] ERROR" >> "$MONITOR_LOG"
}

MonitorTryAccounts()
{
    if [[ $chnl_stream_link == *http://*/*/*/* ]] && [ -s "$XTREAM_CODES" ] 
    then
        chnl_domain=${chnl_stream_link#*http://}
        chnl_domain=${chnl_domain%%/*}

        if [[ $chnl_stream_link == *"/live/"* ]] 
        then
            chnl_account=${chnl_stream_link#*/live/}
            chnl_account=${chnl_account%/*}
            chnl_account=${chnl_account//\//:}
        else
            chnl_account=${chnl_stream_link#*http://}
            chnl_account=${chnl_account#*/}
            chnl_account=${chnl_account%/*}
            chnl_account=${chnl_account//\//:}
        fi

        accounts=()
        if [ "${#accounts[@]}" == 0 ] 
        then
            while IFS= read -r line 
            do
                if [[ $line == *"$chnl_domain"* ]] 
                then
                    line=${line#* }
                    account_line=${line#* }
                    new_account_line=""
                    while [[ $account_line == *" "* ]] 
                    do
                        [ -n "$new_account_line" ] && new_account_line=" $new_account_line"
                        new_account_line="${account_line%% *}$new_account_line"
                        account_line=${account_line#* }
                    done
                    new_account_line=${new_account_line:-$account_line}
                    IFS=" " read -ra accounts <<< "$new_account_line"
                    break
                fi
            done < "$XTREAM_CODES"
        fi

        accounts+=("$chnl_account")

        if [ "${#accounts[@]}" -gt 1 ] 
        then
            chnls=()
            while IFS= read -r line 
            do
                if [[ $line == *\"status\":* ]] 
                then
                    line=${line#*: \"}
                    status=${line%\",*}
                elif [[ $line == *\"stream_link\":* ]] && [[ $line == *http://*/*/*/* ]]
                then
                    line=${line#*: \"http://}
                    domain=${line%%/*}
                    line=${line#*/}
                    username=${line%%/*}
                    if [ "$username" == "live" ] 
                    then
                        line=${line#*/}
                        username=${line%%/*}
                    fi
                    line=${line#*/}
                    password=${line%%/*}
                elif [[ $line == *\"flv_status\":* ]] 
                then
                    line=${line#*: \"}
                    flv_status=${line%\",*}
                    if [ -n "${domain:-}" ] 
                    then
                        if [ "$status" == "on" ] || [ "$flv_status" == "on" ]
                        then
                            if [ "$domain/$username:$password" != "$chnl_domain/$chnl_account" ] 
                            then
                                chnls+=("$domain/$username/$password")
                            fi
                        fi
                    fi
                    domain=""
                fi
            done < "$CHANNELS_FILE"

            for account in "${accounts[@]}"
            do
                if [[ $chnl_stream_link == *"/live/"* ]] 
                then
                    chnl_stream_link="http://$chnl_domain/live/${account//:/\/}/${chnl_stream_link##*/}"
                else
                    chnl_stream_link="http://$chnl_domain/${account//:/\/}/${chnl_stream_link##*/}"
                fi

                found=0
                for chnl in "${chnls[@]}"
                do
                    if [ "$chnl" == "$chnl_domain/${account//:/\/}" ] 
                    then
                        found=1
                        break
                    fi
                done

                valid=0
                if [ "$found" == 0 ] 
                then
                    audio=0
                    video=0
                    while IFS= read -r line 
                    do
                        if [[ $line == *"codec_type=audio"* ]] 
                        then
                            audio=1
                        elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]] 
                        then
                            audio=0
                        elif [[ $line == *"codec_type=video"* ]] 
                        then
                            video=1
                        fi
                    done < <($FFPROBE -i "$chnl_stream_link" -timeout 5000000 -show_streams -loglevel quiet || true)

                    if [ "$audio" == 1 ] && [ "$video" == 1 ]
                    then
                        valid=1
                    fi
                fi

                if [ "$valid" == 1 ] 
                then
                    action="skip"
                    StopChannel > /dev/null 2>&1

                    if [[ $chnl_stream_links == *" "* ]] 
                    then
                        chnl_stream_links="$chnl_stream_link ${chnl_stream_links#* }"
                    else
                        chnl_stream_links=$chnl_stream_link
                    fi

                    if [ "$anti_leech_yn" == "yes" ] && [ "$anti_leech_restart_hls_changes_yn" == "yes" ] 
                    then
                        chnl_playlist_name=$(RandStr)
                        chnl_seg_name=$chnl_playlist_name
                        if [ "$chnl_encrypt_yn" == "yes" ] 
                        then
                            mkdir -p "$chnl_output_dir_root"
                            chnl_key_name=$(RandStr)
                            openssl rand 16 > "$chnl_output_dir_root/$chnl_key_name.key"
                            echo -e "$chnl_key_name.key\n$chnl_output_dir_root/$chnl_key_name.key\n$(openssl rand -hex 16)" > "$chnl_output_dir_root/$chnl_keyinfo_name.keyinfo"
                        fi
                    fi

                    StartChannel > /dev/null 2>&1
                    sleep 15
                    GetChannelInfo

                    if [ -n "${kind:-}" ] 
                    then
                        audio=0
                        video=0
                        while IFS= read -r line 
                        do
                            if [[ $line == *"codec_type=audio"* ]] 
                            then
                                audio=1
                            elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]]
                            then
                                audio=0
                            elif [[ $line == *"codec_type=video"* ]] 
                            then
                                video=1
                            fi
                        done < <($FFPROBE -i "${chnl_flv_pull_link:-$chnl_flv_push_link}" -timeout 5000000 -show_streams -loglevel quiet || true)

                        if [ "$audio" == 1 ] && [ "$video" == 1 ]
                        then
                            try_success=1
                            printf -v date_now '%(%m-%d %H:%M:%S)T'
                            printf '%s\n' "$date_now $chnl_channel_name 重启成功" >> "$MONITOR_LOG"
                            break
                        fi
                    elif ls -A "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*.ts > /dev/null 2>&1 
                    then
                        if [ "$chnl_encrypt_yn" == "yes" ] && [ -e "$LIVE_ROOT/$output_dir_name/$chnl_keyinfo_name.keyinfo" ] && [ -e "$LIVE_ROOT/$output_dir_name/$chnl_key_name.key" ]
                        then
                            line_no=0
                            while IFS= read -r line 
                            do
                                line_no=$((line_no+1))
                                if [ "$line_no" == 3 ] 
                                then
                                    iv_hex=$line
                                fi
                            done < "$LIVE_ROOT/$output_dir_name/$chnl_keyinfo_name.keyinfo"

                            encrypt_key=$(hexdump -e '16/1 "%02x"' < "$LIVE_ROOT/$output_dir_name/$chnl_key_name.key")
                            encrypt_command="-key $encrypt_key -iv $iv_hex"
                        else
                            encrypt_command=""
                        fi

                        audio=0
                        video=0
                        video_bitrate=0
                        bitrate_check=0

                        f_count=1
                        for f in "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*.ts
                        do
                            ((f_count++))
                        done

                        f_num=$((f_count/2))
                        f_count=1

                        for f in "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*.ts
                        do
                            if [ "$f_count" -lt "$f_num" ] 
                            then
                                ((f_count++))
                                continue
                            fi
                            [ -n "$encrypt_command" ] && f="crypto:$f"
                            while IFS= read -r line 
                            do
                                if [[ $line == *"codec_type=video"* ]] 
                                then
                                    video=1
                                elif [ "$bitrate_check" == 0 ] && [ "$video" == 1 ] && [[ $line == *"bit_rate="* ]] 
                                then
                                    line=${line#*bit_rate=}
                                    video_bitrate=${line//N\/A/$hls_min_bitrates}
                                    bitrate_check=1
                                elif [[ $line == *"codec_type=audio"* ]] 
                                then
                                    audio=1
                                elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]] 
                                then
                                    audio=0
                                fi
                            done < <($FFPROBE $encrypt_command -i "$f" -show_streams -loglevel quiet || true)
                            break
                        done

                        if [ "$audio" == 1 ] && [ "$video" == 1 ] && [[ $video_bitrate -ge $hls_min_bitrates ]]
                        then
                            try_success=1
                            printf -v date_now '%(%m-%d %H:%M:%S)T'
                            printf '%s\n' "$date_now $chnl_channel_name 重启成功" >> "$MONITOR_LOG"
                            break
                        fi
                    fi
                fi
            done
        fi
    fi
}

MonitorHlsRestartChannel()
{
    hls_restart_nums=${hls_restart_nums:-20}
    for((i=0;i<hls_restart_nums;i++))
    do
        if [ "$i" -gt 0 ] && [[ $chnl_stream_links == *" "* ]] 
        then
            chnl_stream_links="${chnl_stream_links#* } $chnl_stream_link"
            chnl_stream_link=${chnl_stream_links%% *}
        fi
        if [ "$i" == 3 ] 
        then
            try_success=0
            MonitorTryAccounts
            if [ "$try_success" == 1 ] 
            then
                break
            fi
        fi
        action="skip"
        StopChannel > /dev/null 2>&1
        if [ "$anti_leech_yn" == "yes" ] && [ "$anti_leech_restart_hls_changes_yn" == "yes" ] 
        then
            chnl_playlist_name=$(RandStr)
            chnl_seg_name=$chnl_playlist_name
            if [ "$chnl_encrypt_yn" == "yes" ] 
            then
                mkdir -p "$chnl_output_dir_root"
                chnl_key_name=$(RandStr)
                openssl rand 16 > "$chnl_output_dir_root/$chnl_key_name.key"
                echo -e "$chnl_key_name.key\n$chnl_output_dir_root/$chnl_key_name.key\n$(openssl rand -hex 16)" > "$chnl_output_dir_root/$chnl_keyinfo_name.keyinfo"
            fi
        fi
        StartChannel > /dev/null 2>&1
        sleep 15
        GetChannelInfo
        if ls -A "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*.ts > /dev/null 2>&1 
        then
            if [ "$chnl_encrypt_yn" == "yes" ] && [ -e "$LIVE_ROOT/$output_dir_name/$chnl_keyinfo_name.keyinfo" ] && [ -e "$LIVE_ROOT/$output_dir_name/$chnl_key_name.key" ]
            then
                line_no=0
                while IFS= read -r line 
                do
                    line_no=$((line_no+1))
                    if [ "$line_no" == 3 ] 
                    then
                        iv_hex=$line
                    fi
                done < "$LIVE_ROOT/$output_dir_name/$chnl_keyinfo_name.keyinfo"
                # xxd -p $KEY_FILE
                encrypt_key=$(hexdump -e '16/1 "%02x"' < "$LIVE_ROOT/$output_dir_name/$chnl_key_name.key")
                encrypt_command="-key $encrypt_key -iv $iv_hex"
            else
                encrypt_command=""
            fi

            audio=0
            video=0
            video_bitrate=0
            bitrate_check=0

            f_count=1
            for f in "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*.ts
            do
                ((f_count++))
            done

            f_num=$((f_count/2))
            f_count=1


            for f in "$LIVE_ROOT/$output_dir_name/$chnl_seg_dir_name/"*.ts
            do
                if [ "$f_count" -lt "$f_num" ] 
                then
                    ((f_count++))
                    continue
                fi
                [ -n "$encrypt_command" ] && f="crypto:$f"
                while IFS= read -r line 
                do
                    if [[ $line == *"codec_type=video"* ]] 
                    then
                        video=1
                    elif [ "$bitrate_check" == 0 ] && [ "$video" == 1 ] && [[ $line == *"bit_rate="* ]] 
                    then
                        line=${line#*bit_rate=}
                        video_bitrate=${line//N\/A/$hls_min_bitrates}
                        bitrate_check=1
                    elif [[ $line == *"codec_type=audio"* ]] 
                    then
                        audio=1
                    elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]] 
                    then
                        audio=0
                    fi
                done < <($FFPROBE $encrypt_command -i "$f" -show_streams -loglevel quiet || true)
                break
            done

            if [ "$audio" == 1 ] && [ "$video" == 1 ] && [[ $video_bitrate -ge $hls_min_bitrates ]]
            then
                printf -v date_now '%(%m-%d %H:%M:%S)T'
                printf '%s\n' "$date_now $chnl_channel_name 重启成功" >> "$MONITOR_LOG"
                break
            fi
        elif [[ $i -eq $((hls_restart_nums - 1)) ]] 
        then
            try_success=0
            MonitorTryAccounts
            if [ "$try_success" == 0 ] 
            then
                StopChannel > /dev/null 2>&1
                printf -v date_now '%(%m-%d %H:%M:%S)T'
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
    trap '' HUP INT TERM QUIT
    trap 'MonitorError $LINENO' ERR
    printf '%s' "$BASHPID" > "$MONITOR_PID"
    mkdir -p "$LIVE_ROOT"
    printf '%s\n' "$date_now 监控启动成功 PID $BASHPID !" >> "$MONITOR_LOG"
    echo -e "$info 监控启动成功 !"
    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFPROBE="$FFMPEG_ROOT/ffprobe"
    while true; do
        if [ "$anti_leech_yn" == "yes" ] && [ "$anti_leech_restart_nums" -gt 0 ] && [ "${rand_restart_flv_done:-}" != 0 ] && [ "${rand_restart_hls_done:-}" != 0 ] 
        then
            current_minute_old=${current_minute:-}
            current_hour_old=${current_hour:-25}
            printf -v current_time '%(%H:%M)T'
            current_hour=${current_time%:*}
            current_minute=${current_time#*:}
            if [ "${current_hour:0:1}" == 0 ] 
            then
                current_hour=${current_hour:1}
            fi
            if [ "${current_minute:0:1}" == 0 ] 
            then
                current_minute=${current_minute:1}
            fi

            if [ "$current_hour" != "$current_hour_old" ] 
            then
                minutes=()
                skip_hour=""
            fi

            if [ "${#minutes[@]}" -gt 0 ] && [ "$current_minute" -gt "$current_minute_old" ]
            then
                declare -a new_array
                for minute in "${minutes[@]}"
                do
                    if [ "$minute" -gt "$current_minute" ] 
                    then
                        new_array+=("$minute")
                    fi

                    if [ "$minute" -eq "$current_minute" ] 
                    then
                        rand_restart_flv_done=0
                        rand_restart_hls_done=0
                    fi
                done
                minutes=("${new_array[@]}")
                unset new_array
                [ "${#minutes[@]}" -eq 0 ] && skip_hour=$current_hour
            fi

            if [ "${#minutes[@]}" -eq 0 ] && [ "$current_minute" -lt 59 ] && [ "$current_hour" != "${skip_hour:-}" ]
            then
                rand_restart_flv_done=""
                rand_restart_hls_done=""
                minutes_left=$((59 - current_minute))
                restart_nums=$anti_leech_restart_nums
                [ "$restart_nums" -gt "$minutes_left" ] && restart_nums=$minutes_left
                minute_gap=$((minutes_left / anti_leech_restart_nums / 2))
                [ "$minute_gap" -eq 0 ] && minute_gap=1
                for((i=0;i<restart_nums;i++));
                do
                    while true 
                    do
                        rand_minute=$((RANDOM % 60))
                        if [ "$rand_minute" -gt "$current_minute" ] 
                        then
                            valid=1
                            for minute in "${minutes[@]}"
                            do
                                if [ "$minute" -eq "$rand_minute" ] 
                                then
                                    valid=0
                                    break
                                elif [ "$minute" -gt "$rand_minute" ] && [ "$((minute-rand_minute))" -lt "$minute_gap" ]
                                then
                                    valid=0
                                    break
                                elif [ "$rand_minute" -gt "$minute" ] && [ "$((rand_minute-minute))" -lt "$minute_gap" ]
                                then
                                    valid=0
                                    break
                                fi
                            done
                            if [ "$valid" == 1 ] 
                            then
                                break
                            fi
                        fi
                    done
                    minutes+=("$rand_minute")
                done
                printf '%s\n' "$current_time 计划重启时间 ${minutes[*]}" >> "$MONITOR_LOG"
            fi
        fi

        if [ -n "${flv_nums:-}" ] 
        then
            kind="flv"
            rand_found=0
            if [ -n "${flv_all:-}" ] 
            then
                if [ "$flv_count" -eq 0 ] && [ "${rand_restart_flv_done:-}" == 0 ]
                then
                    rand_restart_flv_done=1
                    rand_found=1
                fi
                for((i=0;i<flv_count;i++));
                do
                    chnl_flv_pull_link=${monitor_flv_pull_links[i]}
                    chnl_flv_push_link=${monitor_flv_push_links[i]}
                    audio=0
                    video=0
                    while IFS= read -r line 
                    do
                        if [[ $line == *"codec_type=audio"* ]] 
                        then
                            audio=1
                        elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]] 
                        then
                            audio=0
                        elif [[ $line == *"codec_type=video"* ]] 
                        then
                            video=1
                        fi
                    done < <($FFPROBE -i "${chnl_flv_pull_link:-$chnl_flv_push_link}" -timeout 5000000 -show_streams -loglevel quiet || true)

                    if [ "$audio" == 0 ] || [ "$video" == 0 ]
                    then
                        GetChannelInfo

                        if [ "${flv_restart_count:-}" == 3 ] 
                        then
                            try_success=0
                            MonitorTryAccounts
                            if [ "$try_success" == 1 ] 
                            then
                                flv_first_fail=""
                                flv_restart_count=1
                                continue
                            fi
                        fi

                        if [ "${flv_restart_count:-1}" -gt "${flv_restart_nums:-20}" ] 
                        then
                            try_success=0
                            MonitorTryAccounts
                            if [ "$try_success" == 1 ] 
                            then
                                flv_first_fail=""
                                flv_restart_count=1
                                continue
                            fi
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

                            printf -v date_now '%(%m-%d %H:%M:%S)T'
                            printf '%s\n' "$date_now $chnl_channel_name flv 重启超过${flv_restart_nums:-20}次关闭" >> "$MONITOR_LOG"
                            break 1
                        fi

                        if [ "${flv_restart_count:-1}" -gt 1 ] && [[ $chnl_stream_links == *" "* ]] 
                        then
                            chnl_stream_links="${chnl_stream_links#* } $chnl_stream_link"
                            chnl_stream_link=${chnl_stream_links%% *}
                        fi

                        if [ "$anti_leech_yn" == "yes" ] && [ "$anti_leech_restart_flv_changes_yn" == "yes" ] 
                        then
                            stream_name=${chnl_flv_push_link##*/}
                            new_stream_name=$(RandStr)
                            while [[ -n $($JQ_FILE '.channels[]|select(.flv_push_link=="'"${chnl_flv_push_link%/*}/$new_stream_name"'")' "$CHANNELS_FILE") ]] 
                            do
                                new_stream_name=$(RandStr)
                            done
                            chnl_flv_push_link="${chnl_flv_push_link%/*}/$new_stream_name"
                            monitor_flv_push_links[i]=$chnl_flv_push_link
                            if [ -n "$chnl_flv_pull_link" ] 
                            then
                                chnl_flv_pull_link=${chnl_flv_pull_link//stream=$stream_name/stream=$new_stream_name}
                                monitor_flv_pull_links[i]=$chnl_flv_pull_link
                            fi
                        fi

                        if [ -n "${flv_first_fail:-}" ]
                        then
                            printf -v flv_fail_date '%(%s)T'
                            if [ $((flv_fail_date - flv_first_fail)) -gt "$flv_delay_seconds" ] 
                            then
                                action="skip"
                                StopChannel > /dev/null 2>&1
                                StartChannel > /dev/null 2>&1
                                flv_restart_count=${flv_restart_count:-1}
                                ((flv_restart_count++))
                                flv_first_fail=""
                                printf -v date_now '%(%m-%d %H:%M:%S)T'
                                printf '%s\n' "$date_now $chnl_channel_name flv 超时重启" >> "$MONITOR_LOG"
                                sleep 10
                            fi
                        else
                            if [ "$chnl_flv_status" == "off" ] 
                            then
                                StartChannel > /dev/null 2>&1
                                flv_restart_count=${flv_restart_count:-1}
                                ((flv_restart_count++))
                                flv_first_fail=""
                                printf -v date_now '%(%m-%d %H:%M:%S)T'
                                printf '%s\n' "$date_now $chnl_channel_name flv 恢复启动" >> "$MONITOR_LOG"
                                sleep 10
                            else
                                printf -v flv_first_fail '%(%s)T'
                            fi

                            new_array=("$chnl_flv_push_link")
                            for element in "${monitor_flv_push_links[@]}"
                            do
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

                        if [ "${rand_restart_flv_done:-}" == 0 ]
                        then
                            rand_found=1
                            if [ "${flv_restart_count:-1}" -gt 1 ] && [[ $chnl_stream_links == *" "* ]] 
                            then
                                chnl_stream_links="${chnl_stream_links#* } $chnl_stream_link"
                                chnl_stream_link=${chnl_stream_links%% *}
                            fi

                            if [ "$anti_leech_restart_flv_changes_yn" == "yes" ] 
                            then
                                stream_name=${chnl_flv_push_link##*/}
                                new_stream_name=$(RandStr)
                                while [[ -n $($JQ_FILE '.channels[]|select(.flv_push_link=="'"${chnl_flv_push_link%/*}/$new_stream_name"'")' "$CHANNELS_FILE") ]] 
                                do
                                    new_stream_name=$(RandStr)
                                done
                                chnl_flv_push_link="${chnl_flv_push_link%/*}/$new_stream_name"
                                monitor_flv_push_links[i]=$chnl_flv_push_link
                                if [ -n "$chnl_flv_pull_link" ] 
                                then
                                    chnl_flv_pull_link=${chnl_flv_pull_link//stream=$stream_name/stream=$new_stream_name}
                                    monitor_flv_pull_links[i]=$chnl_flv_pull_link
                                fi
                            fi
                            action="skip"
                            StopChannel > /dev/null 2>&1
                            StartChannel > /dev/null 2>&1
                            printf -v date_now '%(%m-%d %H:%M:%S)T'
                            printf '%s\n' "$date_now $chnl_channel_name flv 随机重启" >> "$MONITOR_LOG"
                            sleep 10
                        fi
                    fi
                done
            else
                if [ "${rand_restart_flv_done:-}" == 0 ] && [ "${#flv_nums_arr[@]}" -eq 0 ]
                then
                    rand_restart_flv_done=1
                    rand_found=1
                fi
                for flv_num in "${flv_nums_arr[@]}"
                do
                    chnl_flv_pull_link=${monitor_flv_pull_links[$((flv_num-1))]}
                    chnl_flv_push_link=${monitor_flv_push_links[$((flv_num-1))]}
                    audio=0
                    video=0
                    while IFS= read -r line 
                    do
                        if [[ $line == *"codec_type=audio"* ]] 
                        then
                            audio=1
                        elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]] 
                        then
                            audio=0
                        elif [[ $line == *"codec_type=video"* ]] 
                        then
                            video=1
                        fi
                    done < <($FFPROBE -i "${chnl_flv_pull_link:-$chnl_flv_push_link}" -timeout 5000000 -show_streams -loglevel quiet || true)

                    if [ "$audio" == 0 ] || [ "$video" == 0 ]
                    then
                        GetChannelInfo

                        if [ "${flv_restart_count:-}" == 1 ] 
                        then
                            try_success=0
                            MonitorTryAccounts
                            if [ "$try_success" == 1 ] 
                            then
                                flv_first_fail=""
                                flv_restart_count=1
                                continue
                            fi
                        fi

                        if [ "${flv_restart_count:-1}" -gt "${flv_restart_nums:-20}" ] 
                        then
                            if [ "$chnl_flv_status" == "on" ] 
                            then
                                StopChannel > /dev/null 2>&1
                                printf -v date_now '%(%m-%d %H:%M:%S)T'
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

                        if [ "${flv_restart_count:-1}" -gt 1 ] && [[ $chnl_stream_links == *" "* ]] 
                        then
                            chnl_stream_links="${chnl_stream_links#* } $chnl_stream_link"
                            chnl_stream_link=${chnl_stream_links%% *}
                        fi

                        if [ "$anti_leech_yn" == "yes" ] && [ "$anti_leech_restart_flv_changes_yn" == "yes" ] 
                        then
                            stream_name=${chnl_flv_push_link##*/}
                            new_stream_name=$(RandStr)
                            while [[ -n $($JQ_FILE '.channels[]|select(.flv_push_link=="'"${chnl_flv_push_link%/*}/$new_stream_name"'")' "$CHANNELS_FILE") ]] 
                            do
                                new_stream_name=$(RandStr)
                            done
                            chnl_flv_push_link="${chnl_flv_push_link%/*}/$new_stream_name"
                            monitor_flv_push_links[i]=$chnl_flv_push_link
                            if [ -n "$chnl_flv_pull_link" ] 
                            then
                                chnl_flv_pull_link=${chnl_flv_pull_link//stream=$stream_name/stream=$new_stream_name}
                                monitor_flv_pull_links[i]=$chnl_flv_pull_link
                            fi
                        fi

                        if [ -n "${flv_first_fail:-}" ] 
                        then
                            printf -v flv_fail_date '%(%s)T'
                            if [ $((flv_fail_date - flv_first_fail)) -gt "$flv_delay_seconds" ] 
                            then
                                action="skip"
                                StopChannel > /dev/null 2>&1
                                StartChannel > /dev/null 2>&1
                                flv_restart_count=${flv_restart_count:-1}
                                ((flv_restart_count++))
                                flv_first_fail=""
                                printf -v date_now '%(%m-%d %H:%M:%S)T'
                                printf '%s\n' "$date_now $chnl_channel_name flv 超时重启" >> "$MONITOR_LOG"
                                sleep 10
                            fi
                        else
                            if [ "$chnl_flv_status" == "off" ] 
                            then
                                StartChannel > /dev/null 2>&1
                                flv_restart_count=${flv_restart_count:-1}
                                ((flv_restart_count++))
                                flv_first_fail=""
                                printf -v date_now '%(%m-%d %H:%M:%S)T'
                                printf '%s\n' "$date_now $chnl_channel_name flv 恢复启动" >> "$MONITOR_LOG"
                                sleep 10
                            else
                                printf -v flv_first_fail '%(%s)T'
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

                        if [ "${rand_restart_flv_done:-}" == 0 ]
                        then
                            rand_found=1
                            if [ "${flv_restart_count:-1}" -gt 1 ] && [[ $chnl_stream_links == *" "* ]] 
                            then
                                chnl_stream_links="${chnl_stream_links#* } $chnl_stream_link"
                                chnl_stream_link=${chnl_stream_links%% *}
                            fi

                            if [ "$anti_leech_restart_flv_changes_yn" == "yes" ] 
                            then
                                stream_name=${chnl_flv_push_link##*/}
                                new_stream_name=$(RandStr)
                                while [[ -n $($JQ_FILE '.channels[]|select(.flv_push_link=="'"${chnl_flv_push_link%/*}/$new_stream_name"'")' "$CHANNELS_FILE") ]] 
                                do
                                    new_stream_name=$(RandStr)
                                done
                                chnl_flv_push_link="${chnl_flv_push_link%/*}/$new_stream_name"
                                monitor_flv_push_links[i]=$chnl_flv_push_link
                                if [ -n "$chnl_flv_pull_link" ] 
                                then
                                    chnl_flv_pull_link=${chnl_flv_pull_link//stream=$stream_name/stream=$new_stream_name}
                                    monitor_flv_pull_links[i]=$chnl_flv_pull_link
                                fi
                            fi
                            action="skip"
                            StopChannel > /dev/null 2>&1
                            StartChannel > /dev/null 2>&1
                            printf -v date_now '%(%m-%d %H:%M:%S)T'
                            printf '%s\n' "$date_now $chnl_channel_name flv 随机重启" >> "$MONITOR_LOG"
                            sleep 10
                        fi
                    fi
                done
            fi
            if [ "$rand_found" == 1 ] 
            then
                rand_restart_flv_done=1
            fi
        else
            rand_restart_flv_done=1
        fi

        kind=""

        if ls -A $LIVE_ROOT/* > /dev/null 2>&1
        then
            exclude_command=""
            for exclude_path in "${exclude_paths[@]}"
            do
                exclude_command="$exclude_command -not \( -path $exclude_path -prune \)"
            done

            if [ -n "${hls_max_seg_size:-}" ] 
            then
                
                largest_file=$(find "$LIVE_ROOT" $exclude_command -type f -printf "%s %p\n" | sort -n | tail -1 || true)
                if [ -n "${largest_file:-}" ] 
                then
                    largest_file_size=${largest_file%% *}
                    largest_file_path=${largest_file#* }
                    output_dir_name=${largest_file_path#*$LIVE_ROOT/}
                    output_dir_name=${output_dir_name%%/*}
                    if [ "$largest_file_size" -gt $(( hls_max_seg_size * 1000000)) ]
                    then
                        GetChannelInfo
                        if [ -n "$chnl_live" ] 
                        then
                            printf '%s\n' "$chnl_channel_name 文件过大重启" >> "$MONITOR_LOG"
                            MonitorHlsRestartChannel
                        else
                            exclude_paths+=("$LIVE_ROOT/$output_dir_name")
                        fi
                    fi
                fi
            fi

            if [ -n "${hls_nums:-}" ] 
            then
                if [ -z "${loop:-}" ] || [ "$loop" -eq 10 ]
                then
                    loop=1
                else
                    ((loop++))
                fi
                while IFS= read -r old_file_path
                do
                    if [[ $old_file_path == *"_master.m3u8" ]] || [[ $old_file_path == *".key" ]] || [[ $old_file_path == *".keyinfo" ]]
                    then
                        continue
                    fi
                    output_dir_name=${old_file_path#*$LIVE_ROOT/}
                    output_dir_name=${output_dir_name%%/*}
                    if [ "${monitor_all}" == 1 ] 
                    then
                        GetChannelInfo
                        if [ -n "$chnl_live" ] 
                        then
                            printf '%s\n' "$chnl_channel_name 超时重启" >> "$MONITOR_LOG"
                            MonitorHlsRestartChannel
                            break 1
                        else
                            exclude_paths+=("$LIVE_ROOT/$output_dir_name")
                        fi
                    else
                        for dir_name in "${monitor_dir_names_chosen[@]}"
                        do
                            if [ "$dir_name" == "$output_dir_name" ] 
                            then
                                GetChannelInfo
                                if [ -n "$chnl_live" ] 
                                then
                                    printf '%s\n' "$chnl_channel_name 超时重启" >> "$MONITOR_LOG"
                                    MonitorHlsRestartChannel
                                    break 2
                                else
                                    exclude_paths+=("$LIVE_ROOT/$output_dir_name")
                                fi
                            fi
                        done  
                    fi
                done < <(find "$LIVE_ROOT/"* $exclude_command \! -newermt "-$hls_delay_seconds seconds" || true)

                rand_found=0
                if [ "${#monitor_dir_names_chosen[@]}" -eq 0 ] 
                then
                    rand_found=1
                else
                    GetChannelsInfo
                fi

                for output_dir_name in "${monitor_dir_names_chosen[@]}"
                do
                    found=0
                    for((i=0;i<chnls_count;i++));
                    do
                        if [ "${chnls_output_dir_name[i]}" == "$output_dir_name" ] 
                        then
                            found=1

                            if [ "${chnls_status[i]}" == "off" ] 
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
                                    break 2
                                fi
                                if [ "$chnl_status" == "off" ] 
                                then
                                    printf '%s\n' "$chnl_channel_name 开启" >> "$MONITOR_LOG"
                                    MonitorHlsRestartChannel
                                    break 2
                                fi
                            fi

                            if [ "$loop" -gt 1 ]
                            then
                                break 1
                            fi

                            if [ "${chnls_encrypt[i]}" == "yes" ] && [ -e "$LIVE_ROOT/$output_dir_name/${chnls_keyinfo_name[i]}.keyinfo" ] && [ -e "$LIVE_ROOT/$output_dir_name/${chnls_key_name[i]}.key" ]
                            then
                                line_no=0
                                while IFS= read -r line 
                                do
                                    line_no=$((line_no+1))
                                    if [ "$line_no" == 3 ] 
                                    then
                                        iv_hex=$line
                                    fi
                                done < "$LIVE_ROOT/$output_dir_name/${chnls_keyinfo_name[i]}.keyinfo"

                                encrypt_key=$(hexdump -e '16/1 "%02x"' < "$LIVE_ROOT/$output_dir_name/${chnls_key_name[i]}.key")
                                encrypt_command="-key $encrypt_key -iv $iv_hex"
                            else
                                encrypt_command=""
                            fi

                            audio=0
                            video=0
                            video_bitrate=0
                            bitrate_check=0
                            f_count=1
                            for f in "$LIVE_ROOT/$output_dir_name/${chnls_seg_dir_name[i]}/"*.ts
                            do
                                ((f_count++))
                            done

                            f_num=$((f_count/2))
                            f_count=1

                            for f in "$LIVE_ROOT/$output_dir_name/${chnls_seg_dir_name[i]}/"*.ts
                            do
                                if [ "$f_count" -lt "$f_num" ] 
                                then
                                    ((f_count++))
                                    continue
                                fi
                                [ -n "$encrypt_command" ] && f="crypto:$f"
                                while IFS= read -r line 
                                do
                                    if [[ $line == *"codec_type=video"* ]] 
                                    then
                                        video=1
                                    elif [ "$bitrate_check" == 0 ] && [ "$video" == 1 ] && [[ $line == *"bit_rate="* ]] 
                                    then
                                        line=${line#*bit_rate=}
                                        video_bitrate=${line//N\/A/$hls_min_bitrates}
                                        bitrate_check=1
                                    elif [[ $line == *"codec_type=audio"* ]] 
                                    then
                                        audio=1
                                    elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]] 
                                    then
                                        audio=0
                                    fi
                                done < <($FFPROBE $encrypt_command -i "$f" -show_streams -loglevel quiet || true)
                                break
                            done

                            if [ "$audio" == 0 ] || [ "$video" == 0 ] || [[ $video_bitrate -lt $hls_min_bitrates ]]
                            then
                                [ -n "$encrypt_command" ] && f="crypto:$f"
                                fail_count=1
                                f_count=1
                                for f in "$LIVE_ROOT/$output_dir_name/${chnls_seg_dir_name[i]}/"*.ts
                                do
                                    if [ "$f_count" -lt "$f_num" ] 
                                    then
                                        ((f_count++))
                                        continue
                                    fi
                                    [ ! -e "$f" ] && continue
                                    audio=0
                                    video=0
                                    video_bitrate=0
                                    bitrate_check=0
                                    while IFS= read -r line 
                                    do
                                        if [[ $line == *"codec_type=video"* ]] 
                                        then
                                            video=1
                                        elif [ "$bitrate_check" == 0 ] && [ "$video" == 1 ] && [[ $line == *"bit_rate="* ]] 
                                        then
                                            line=${line#*bit_rate=}
                                            video_bitrate=${line//N\/A/$hls_min_bitrates}
                                            bitrate_check=1
                                        elif [[ $line == *"codec_type=audio"* ]] 
                                        then
                                            audio=1
                                        elif [[ $line == *"sample_fmt=unknown"* ]] || [[ $line == *"sample_rate=0"* ]] || [[ $line == *"channels=0"* ]] 
                                        then
                                            audio=0
                                        fi
                                    done < <($FFPROBE $encrypt_command -i "$f" -show_streams -loglevel quiet || true)

                                    if [ "$audio" == 0 ] || [ "$video" == 0 ] || [[ $video_bitrate -lt $hls_min_bitrates ]]
                                    then
                                        ((fail_count++))
                                    fi
                                    if [ "$fail_count" -gt 3 ] 
                                    then
                                        GetChannelInfo
                                        printf '%s\n' "$chnl_channel_name 比特率过低重启" >> "$MONITOR_LOG"
                                        MonitorHlsRestartChannel
                                        break 2
                                    fi
                                done
                            fi

                            if [ "${rand_restart_hls_done:-}" == 0 ]
                            then
                                rand_found=1
                                GetChannelInfo
                                printf '%s\n' "$chnl_channel_name HLS 随机重启" >> "$MONITOR_LOG"
                                MonitorHlsRestartChannel
                            fi
                            break 1
                        fi
                    done

                    if [ "$found" == 0 ] 
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
                done

                if [ "$rand_found" == 1 ] 
                then
                    rand_restart_hls_done=1
                fi
            else
                rand_restart_hls_done=1
            fi
        else
            rand_restart_hls_done=1
        fi

        sleep 10
    done
}

AntiLeech()
{
    echo && echo -e "是否开启防盗链? [y/N]"
    read -p "(默认: ${d_anti_leech}): " anti_leech_yn
    anti_leech_yn=${anti_leech_yn:-$d_anti_leech}
    if [[ $anti_leech_yn == [Yy] ]] 
    then
        anti_leech_yn="yes"

        echo && echo "请输入每小时随机重启次数 (大于等于0)"
        while read -p "(默认: $d_anti_leech_restart_nums): " anti_leech_restart_nums
        do
            case $anti_leech_restart_nums in
                "") anti_leech_restart_nums=$d_anti_leech_restart_nums && break
                ;;
                *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
                ;;
                *) 
                    if [ "$anti_leech_restart_nums" -ge 0 ]
                    then
                        break
                    else
                        echo && echo -e "$error 请输入正确的数字(大于等于0)" && echo
                    fi
                ;;
            esac
        done


        if [ -n "${flv_nums:-}" ] 
        then
            echo && echo "是否每当重启 FLV 频道更改成随机的推流和拉流地址？[y/N]"
            read -p "(默认: $d_anti_leech_restart_flv_changes): " anti_leech_restart_flv_changes_yn
            anti_leech_restart_flv_changes_yn=${anti_leech_restart_flv_changes_yn:-$d_anti_leech_restart_flv_changes}
            if [[ $anti_leech_restart_flv_changes_yn == [Yy] ]] 
            then
                anti_leech_restart_flv_changes_yn="yes"
            else
                anti_leech_restart_flv_changes_yn="no"
            fi
        else
            anti_leech_restart_flv_changes_yn=$d_anti_leech_restart_flv_changes_yn
        fi

        if [ -n "$hls_nums" ] 
        then
            echo && echo "是否每当重启 HLS 频道更改成随机的 m3u8 名称, 段名称, key 名称 ? [y/N]"
            read -p "(默认: $d_anti_leech_restart_hls_changes): " anti_leech_restart_hls_changes_yn
            anti_leech_restart_hls_changes_yn=${anti_leech_restart_hls_changes_yn:-$d_anti_leech_restart_hls_changes}
            if [[ $anti_leech_restart_hls_changes_yn == [Yy] ]] 
            then
                anti_leech_restart_hls_changes_yn="yes"
            else
                anti_leech_restart_hls_changes_yn="no"
            fi
        else
            anti_leech_restart_hls_changes_yn=$d_anti_leech_restart_hls_changes_yn
        fi

    else
        anti_leech_yn="no"
        anti_leech_restart_nums=$d_anti_leech_restart_nums
        anti_leech_restart_flv_changes_yn=$d_anti_leech_restart_flv_changes_yn
        anti_leech_restart_hls_changes_yn=$d_anti_leech_restart_hls_changes_yn
    fi
}

MonitorSet()
{
    monitor=1
    flv_count=0
    monitor_channel_names=()
    monitor_stream_links=()
    monitor_flv_push_links=()
    monitor_flv_pull_links=()
    GetChannelsInfo
    for((i=0;i<chnls_count;i++));
    do
        if [ "${chnls_flv_status[i]}" == "on" ] && [ "${chnls_live[i]}" == "yes" ]
        then
            flv_count=$((flv_count+1))
            monitor_channel_names+=("${chnls_channel_name[i]}")
            monitor_stream_links+=("${chnls_stream_link[i]}")
            monitor_flv_push_links+=("${chnls_flv_push_link[i]}")
            monitor_flv_pull_links+=("${chnls_flv_pull_link[i]}")
        fi
    done
    
    if [ "$flv_count" -gt 0 ] 
    then
        GetDefault
        echo && echo "请选择需要监控的 FLV 推流频道(多个频道用空格分隔 比如: 5 7 9-11)" && echo

        for((i=0;i<flv_count;i++));
        do
            if [ "$i" -lt 9 ] 
            then
                blank=" "
            else
                blank=""
            fi
            flv_pull_link=${monitor_flv_pull_links[i]}
            echo -e "  $green$((i+1)).$plain $blank${monitor_channel_names[i]}\n      源: ${monitor_stream_links[i]}\n      pull: ${flv_pull_link:-无}\n"
        done

        echo && echo -e "  $green$((i+1)).$plain 全部"
        echo -e "  $green$((i+2)).$plain 不设置" && echo
        while read -p "(默认: 不设置): " flv_nums
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
                while read -p "(默认: $d_flv_delay_seconds秒): " flv_delay_seconds
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
                    *"-"*)
                        flv_num_start=${flv_num%-*}
                        flv_num_end=${flv_num#*-}
                        if [[ $flv_num_start == *[!0-9]* ]] || [[ $flv_num_end == *[!0-9]* ]] || [ "$flv_num_start" -eq 0 ] || [ "$flv_num_end" -eq 0 ] || [ "$flv_num_end" -gt "$flv_count" ] || [ "$flv_num_start" -ge "$flv_num_end" ]
                        then
                            error_no=3
                        fi
                    ;;
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
                1|2|3)
                    echo -e "$error 请输入正确的数字或直接回车 " && echo
                ;;
                *)
                    declare -a new_array
                    for element in "${flv_nums_arr[@]}"
                    do
                        if [[ $element == *"-"* ]] 
                        then
                            start=${element%-*}
                            end=${element#*-}
                            for((i=start;i<=end;i++));
                            do
                                new_array+=("$i")
                            done
                        else
                            new_array+=("$element")
                        fi
                    done
                    flv_nums_arr=("${new_array[@]}")
                    unset new_array

                    echo && echo "设置超时多少秒自动重启频道"
                    while read -p "(默认: $d_flv_delay_seconds秒): " flv_delay_seconds
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

        if [ -n "$flv_nums" ] 
        then
            echo && echo "请输入尝试重启的次数"
            while read -p "(默认: $d_flv_restart_nums次): " flv_restart_nums
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
    fi

    if ! ls -A $LIVE_ROOT/* > /dev/null 2>&1
    then
        if [ "$flv_count" == 0 ] 
        then
            echo && echo -e "$error 没有开启的频道！" && echo && exit 1
        elif [ -z "${flv_delay_seconds:-}" ] 
        then
            echo && echo "已取消..." && echo && exit 1
        else
            AntiLeech
            JQ update "$CHANNELS_FILE" '(.default|.flv_delay_seconds)='"$flv_delay_seconds"'
            |(.default|.flv_restart_nums)='"$flv_restart_nums"'
            |(.default|.anti_leech)="'"$anti_leech_yn"'"
            |(.default|.anti_leech_restart_nums)='"$anti_leech_restart_nums"'
            |(.default|.anti_leech_restart_flv_changes)="'"$anti_leech_restart_flv_changes_yn"'"
            |(.default|.anti_leech_restart_hls_changes)="'"$anti_leech_restart_hls_changes_yn"'"'
            return 0
        fi
    fi
    echo && echo "请选择需要监控超时和低比特率重启的 HLS 频道(多个频道用空格分隔 比如 5 7 9-11)" && echo
    monitor_count=0
    monitor_dir_names=()
    exclude_paths=()
    [ -z "${d_hls_delay_seconds:-}" ] && GetDefault
    for((i=0;i<chnls_count;i++));
    do
        if [ -e "$LIVE_ROOT/${chnls_output_dir_name[i]}" ] && [ "${chnls_live[i]}" == "yes" ] && [ "${chnls_seg_count[i]}" != 0 ]
        then
            monitor_count=$((monitor_count + 1))
            monitor_dir_names+=("${chnls_output_dir_name[i]}")
            echo -e "  $green$monitor_count.$plain ${chnls_channel_name[i]}"
        fi
    done
    
    echo && echo -e "  $green$((monitor_count+1)).$plain 全部"
    echo -e "  $green$((monitor_count+2)).$plain 不设置" && echo
    
    while read -p "(默认: 不设置): " hls_nums
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
            while read -p "(默认: $d_hls_delay_seconds秒): " hls_delay_seconds
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
                *"-"*)
                    hls_num_start=${hls_num%-*}
                    hls_num_end=${hls_num#*-}
                    if [[ $hls_num_start == *[!0-9]* ]] || [[ $hls_num_end == *[!0-9]* ]] || [ "$hls_num_start" -eq 0 ] || [ "$hls_num_end" -eq 0 ] || [ "$hls_num_end" -gt "$monitor_count" ] || [ "$hls_num_start" -ge "$hls_num_end" ]
                    then
                        error_no=3
                    fi
                ;;
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
                declare -a new_array
                for element in "${hls_nums_arr[@]}"
                do
                    if [[ $element == *"-"* ]] 
                    then
                        start=${element%-*}
                        end=${element#*-}
                        for((i=start;i<=end;i++));
                        do
                            new_array+=("$i")
                        done
                    else
                        new_array+=("$element")
                    fi
                done
                hls_nums_arr=("${new_array[@]}")
                unset new_array

                for hls_num in "${hls_nums_arr[@]}"
                do
                    monitor_dir_names_chosen+=("${monitor_dir_names[((hls_num - 1))]}")
                done

                echo && echo "设置超时多少秒自动重启频道"
                echo -e "$tip 必须大于 段时长*段数目" && echo
                while read -p "(默认: $d_hls_delay_seconds秒): " hls_delay_seconds
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
        while read -p "(默认: $d_hls_min_bitrates): " hls_min_bitrates
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

    echo && echo "请输入允许的最大片段"
    while read -p "(默认: ${d_hls_max_seg_size}M): " hls_max_seg_size
    do
        case $hls_max_seg_size in
            "") hls_max_seg_size=$d_hls_max_seg_size && break
            ;;
            *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
            ;;
            *) 
                if [ "$hls_max_seg_size" -gt 0 ]
                then
                    break
                else
                    echo && echo -e "$error 请输入正确的数字(大于0)" && echo
                fi
            ;;
        esac
    done

    echo && echo "请输入尝试重启的次数"
    while read -p "(默认: $d_hls_restart_nums次): " hls_restart_nums
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

    AntiLeech

    flv_delay_seconds=${flv_delay_seconds:-$d_flv_delay_seconds}
    flv_restart_nums=${flv_restart_nums:-$d_flv_restart_nums}
    hls_delay_seconds=${hls_delay_seconds:-$d_hls_delay_seconds}
    hls_min_bitrates=${hls_min_bitrates:-$d_hls_min_bitrates}
    JQ update "$CHANNELS_FILE" '(.default|.flv_delay_seconds)='"$flv_delay_seconds"'
    |(.default|.flv_restart_nums)='"$flv_restart_nums"'
    |(.default|.hls_delay_seconds)='"$hls_delay_seconds"'
    |(.default|.hls_min_bitrates)='"$((hls_min_bitrates / 1000))"'
    |(.default|.hls_max_seg_size)='"$hls_max_seg_size"'
    |(.default|.hls_restart_nums)='"$hls_restart_nums"'
    |(.default|.anti_leech)="'"$anti_leech_yn"'"
    |(.default|.anti_leech_restart_nums)='"$anti_leech_restart_nums"'
    |(.default|.anti_leech_restart_flv_changes)="'"$anti_leech_restart_flv_changes_yn"'"
    |(.default|.anti_leech_restart_hls_changes)="'"$anti_leech_restart_hls_changes_yn"'"'
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
    echo && echo -e "$info 检查依赖，耗时可能会很长..."
    Progress &
    progress_pid=$!
    CheckRelease
    if [ "$release" == "rpm" ] 
    then
        yum -y install gcc gcc-c++ >/dev/null 2>&1
        timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1
        systemctl restart crond >/dev/null 2>&1
    else
        apt-get -y update >/dev/null 2>&1
        locale-gen zh_CN.UTF-8 >/dev/null 2>&1
        timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1
        systemctl restart cron >/dev/null 2>&1
        apt-get -y install debconf-utils >/dev/null 2>&1
        echo '* libraries/restart-without-asking boolean true' | debconf-set-selections
        apt-get -y install software-properties-common pkg-config libssl-dev libghc-zlib-dev libcurl4-gnutls-dev libexpat1-dev unzip gettext build-essential >/dev/null 2>&1
    fi

    echo -n "...40%..."

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
        if [[ $line == *"/download/"* ]] 
        then
            nginx_name=${line#*/download/}
            nginx_name=${nginx_name%%.tar.gz*}
        fi
    done < <( wget --timeout=10 --tries=3 --no-check-certificate "https://nginx.org/en/download.html" -qO- )

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
    read -p "(默认: N): " nginx_uninstall_yn
    nginx_uninstall_yn=${nginx_uninstall_yn:-N}

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
        read -p "(默认: Y): " nginx_start_yn
        nginx_start_yn=${nginx_start_yn:-Y}
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
            read -p "(默认: Y): " nginx_stop_yn
            nginx_stop_yn=${nginx_stop_yn:-Y}
            if [[ $nginx_stop_yn == [Yy] ]] 
            then
                nginx -s stop
                echo && echo -e "$info Nginx 已关闭" && echo
            else
                echo && echo "已取消..." && echo && exit 1
            fi
        else
            echo && echo "nginx 未运行，是否开启？[Y/n]"
            read -p "(默认: Y): " nginx_start_yn
            nginx_start_yn=${nginx_start_yn:-Y}
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
            if [[ $line == *"location / "* ]] && [ "$found" == 0 ]
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

ListXtreamCodes()
{
    ips=()
    new_domains=()
    new_accounts=()
    while IFS= read -r line 
    do
        if [[ $line == *"username="* ]] 
        then
            domain=${line#*http://}
            domain=${domain%%/*}
            username=${line#*username=}
            username=${username%%&*}
            password=${line#*password=}
            password=${password%%&*}
            ip=$(getent ahosts "${domain%%:*}" | awk '{ print $1 ; exit }')
            account="$username:$password"
        elif [[ $line == *http://*/*/*/* ]] 
        then
            tmp_line=${line#*http://}
            domain=${tmp_line%%/*}
            tmp_line=${tmp_line#*/}
            username=${tmp_line%%/*}
            tmp_line=${tmp_line#*/}
            password=${tmp_line%%/*}
            ip=$(getent ahosts "${domain%%:*}" | awk '{ print $1 ; exit }')
            account="$username:$password"
        else
            ip=${line%% *}
            tmp_line=${line#* }
            domain_line=${tmp_line%% *}
            account_line=${tmp_line#* }
            IFS="|" read -ra domains <<< "$domain_line"
            IFS=" " read -ra accounts <<< "$account_line"

            found=0
            for((i=0;i<${#ips[@]};i++));
            do
                IFS='|' read -ra ips_index_arr <<< "${ips[i]}"
                for ips_index_ip in "${ips_index_arr[@]}"
                do
                    if [ "$ips_index_ip" == "$ip" ] 
                    then
                        found=1
                        for domain in "${domains[@]}"
                        do
                            if [[ ${new_domains[i]} != *"$domain"* ]] 
                            then
                                new_domains[i]="${new_domains[i]}|$domain"
                            fi
                        done
                        
                        for account in "${accounts[@]}"
                        do
                            if [[ ${new_accounts[i]} != *"$account"* ]] 
                            then
                                new_accounts[i]="${new_accounts[i]} $account"
                            fi
                        done
                    fi
                done

                if [ "$found" == 0 ] 
                then
                    for domain in "${domains[@]}"
                    do
                        if [[ ${new_domains[i]} == *"$domain"* ]] 
                        then
                            found=1
                            ips[i]="${ips[i]}|$ip"

                            for account in "${accounts[@]}"
                            do
                                if [[ ${new_accounts[i]} != *"$account"* ]] 
                                then
                                    new_accounts[i]="${new_accounts[i]} $account"
                                fi
                            done
                        fi
                    done
                fi
            done
            
            if [ "$found" == 0 ] 
            then
                ips+=("$ip")
                new_domains+=("$domain_line")
                new_accounts+=("$account_line")
            fi
            
            continue
        fi

        found=0
        for((i=0;i<${#ips[@]};i++));
        do
            if [ "${ips[i]}" == "$ip" ] 
            then
                found=1
                if [[ ${new_domains[i]} != *"$domain"* ]] 
                then
                    new_domains[i]="${new_domains[i]}|$domain"
                fi
                
                if [[ ${new_accounts[i]} != *"$account"* ]] 
                then
                    new_accounts[i]="${new_accounts[i]} $account"
                fi
            fi
        done
        
        if [ "$found" == 0 ] 
        then
            ips+=("$ip")
            new_domains+=("$domain")
            new_accounts+=("$account")
        fi
    done < "$XTREAM_CODES"

    ip_count=${#ips[@]}

    if [ "$ip_count" -gt 0 ] 
    then
        printf "" > "$XTREAM_CODES"

        echo

        for((i=0;i<ip_count;i++));
        do
            printf '%s\n' "${ips[i]} ${new_domains[i]} ${new_accounts[i]}" >> "$XTREAM_CODES"
            echo -e "$green$((i+1)).$plain IP: $green${ips[i]//|/, }$plain 域名: $green${new_domains[i]//|/, }$plain" && echo
            echo -e "$green账号:$plain"
            IFS=" " read -ra accounts <<< "${new_accounts[i]}"
            for account in "${accounts[@]}"
            do
                echo "${account//:/    }"
            done
            echo
        done
    else
        echo && echo -e "$error 没有账号！" && echo && exit 1
    fi
}

TestXtreamCodes()
{
    echo && echo "请输入测试的序号"
    while read -p "(默认: 取消): " test_num
    do
        case $test_num in
            "") echo && echo "已取消..." && echo && exit 1
            ;;
            *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
            ;;
            *) 
                if [ "$test_num" -gt 0 ] && [ ! "$test_num" -gt "$ip_count" ]
                then
                    break
                else
                    echo && echo -e "$error 请输入正确的序号" && echo
                fi
            ;;
        esac
    done

    echo && echo "请输入测试的频道ID"
    while read -p "(默认: 取消): " channel_id
    do
        case $channel_id in
            "") echo && echo "已取消..." && echo && exit 1
            ;;
            *[!0-9]*) echo && echo -e "$error 请输入正确的数字" && echo
            ;;
            *) 
                if [ "$channel_id" -gt 0 ]
                then
                    break
                else
                    echo && echo -e "$error 请输入正确的频道ID(大于0)" && echo
                fi
            ;;
        esac
    done

    if [ -e "$CHANNELS_FILE" ] 
    then
        chnls=()
        while IFS= read -r line 
        do
            if [[ $line == *\"status\":* ]] 
            then
                line=${line#*: \"}
                status=${line%\",*}
            elif [[ $line == *\"stream_link\":* ]] && [[ $line == *http://*/*/*/* ]]
            then
                line=${line#*: \"http://}
                chnl_domain=${line%%/*}
                line=${line#*/}
                chnl_username=${line%%/*}
                if [ "$chnl_username" == "live" ] 
                then
                    line=${line#*/}
                    chnl_username=${line%%/*}
                fi
                line=${line#*/}
                chnl_password=${line%%/*}
            elif [[ $line == *\"flv_status\":* ]] 
            then
                line=${line#*: \"}
                flv_status=${line%\",*}
                if [ -n "${chnl_domain:-}" ] 
                then
                    if [ "$status" == "on" ] || [ "$flv_status" == "on" ]
                    then
                        chnls+=("$chnl_domain/$chnl_username/$chnl_password")
                    fi
                fi
                chnl_domain=""
            fi
        done < "$CHANNELS_FILE"
    fi

    index=$((test_num-1))
    IFS="|" read -ra domains <<< "${new_domains[index]}"
    IFS=" " read -ra accounts <<< "${new_accounts[index]}"
    echo && echo -e "IP: $green${ips[index]}$plain 域名: $green${new_domains[index]//|/ }$plain" && echo
    echo -e "$green账号:$plain"

    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFPROBE="$FFMPEG_ROOT/ffprobe"

    for account in "${accounts[@]}"
    do
        username=${account%%:*}
        account=${account#*:}
        password=${account%%:*}

        found=0
        for domain in "${domains[@]}"
        do
            for chnl in "${chnls[@]}"
            do
                if [ "$domain/$username/$password" == "$chnl" ] 
                then
                    found=1
                    break 2
                fi
            done
        done

        if [ "$found" == 1 ] 
        then
            echo -e "${green}[使用中]$plain $username    $password"
        else
            for domain in "${domains[@]}"
            do
                if $FFPROBE -i "http://$domain/$username/$password/$channel_id" -timeout 3000000 -show_streams -select_streams a -loglevel quiet > /dev/null # curl --output /dev/null -m 3 --silent --fail -r 0-0
                then
                    echo -e "${green}[成功]$plain $username    $password    $green$domain$plain"
                    echo "http://$domain/$username/$password/$channel_id" && echo
                elif $FFPROBE -i "http://$domain/live/$username/$password/$channel_id.ts" -timeout 3000000 -show_streams -select_streams a -loglevel quiet > /dev/null 
                then
                    echo -e "${green}[成功]$plain $username    $password    $green$domain$plain"
                    echo "http://$domain/live/$username/$password/$channel_id.ts" && echo
                else
                    echo -e "${red}[失败]$plain $username    $password    ${red}$domain$plain"
                fi
            done
        fi
    done
    echo
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
        可以是视频路径
        可以输入不同链接地址(监控按顺序尝试使用)，用空格分隔
    -s  段时长(秒)(默认：6)
    -o  输出目录名称(默认：随机名称)

    -p  m3u8名称(前缀)(默认：随机)
    -c  m3u8里包含的段数目(默认：5)
    -S  段所在子目录名称(默认：不使用子目录)
    -t  段名称(前缀)(默认：跟m3u8名称相同)
    -a  音频编码(默认：aac) (不需要转码时输入 copy)
    -v  视频编码(默认：libx264) (不需要转码时输入 copy)
    -f  画面或声音延迟(格式如： v_3 画面延迟3秒，a_2 声音延迟2秒
        使用此功能*暂时*会忽略部分参数，画面声音不同步时使用)
    -q  crf视频质量(如果同时设置了输出视频比特率，则优先使用crf视频质量)(数值0~63 越大质量越差)
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
    -T  设置推流地址，比如 rtmp://127.0.0.1/flv/xxx
    -L  输入拉流(播放)地址(可省略)，比如 http://domain.com/flv?app=flv&stream=xxx

    -m  ffmpeg 额外的 INPUT FLAGS
        (默认：-reconnect 1 -reconnect_at_eof 1 
        -reconnect_streamed 1 -reconnect_delay_max 2000 
        -timeout 2000000000 -y -nostats -nostdin -hide_banner -loglevel fatal)
        如果是 hls 链接，需去除 -reconnect_at_eof 1
    -n  ffmpeg 额外的 OUTPUT FLAGS, 可以输入 omit 省略此选项
        (默认：-g 25 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main)

举例:
    使用crf值控制视频质量: 
        tv -i http://xxx.com/xxx.ts -s 6 -o hbo1 -p hbo1 -q 15 -b 1500-1280x720 -z 'hbo直播1'
    使用比特率控制视频质量[默认]: 
        tv -i http://xxx.com/xxx.ts -s 6 -o hbo2 -p hbo2 -b 900-1280x720 -z 'hbo直播2'

    不需要转码的设置: -a copy -v copy -n omit

    不输出 HLS, 推流 flv :
        tv -i http://xxx/xxx.ts -a aac -v libx264 -b 3000 -k flv -T rtmp://127.0.0.1/flv/xxx

EOM

exit

}

UpdateSelf()
{
    GetDefault
    if [ "$d_version" != "$sh_ver" ] 
    then
        major_ver=${d_version%%.*}
        minor_ver=${d_version#*.}
        minor_ver=${minor_ver%%.*}
        if [ "$major_ver" == 1 ] && [ "$minor_ver" -lt 9 ]
        then
            if [[ -n $($JQ_FILE '.channels[]|select(.status=="on")' "$CHANNELS_FILE") ]] || [[ -n $($JQ_FILE '.channels[]|select(.flv_status=="on")' "$CHANNELS_FILE") ]]
            then
                echo && echo -e "$info 需要先关闭所有频道，请稍等..." && echo
                while IFS= read -r chnl_pid
                do
                    GetChannelInfo
                    if [ "$chnl_flv_status" == "on" ] 
                    then
                        kind="flv"
                        StopChannel
                    elif [ "$chnl_status" == "on" ]
                    then
                        kind=""
                        StopChannel
                    fi
                done < <($JQ_FILE '.channels[].pid' $CHANNELS_FILE)
            fi
        fi
        echo && echo -e "$info 更新中，请稍等..." && echo
        printf -v update_date '%(%m-%d)T'
        cp -f "$CHANNELS_FILE" "${CHANNELS_FILE}_$update_date"

        GetChannelsInfo

        default=$(
        $JQ_FILE -n --arg playlist_name "$d_playlist_name" --arg seg_dir_name "$d_seg_dir_name" \
            --arg seg_name "$d_seg_name" --arg seg_length "$d_seg_length" \
            --arg seg_count "$d_seg_count" --arg video_codec "$d_video_codec" \
            --arg audio_codec "$d_audio_codec" --arg video_audio_shift "$d_video_audio_shift" \
            --arg quality "$d_quality" --arg bitrates "$d_bitrates" \
            --arg const "$d_const_yn" --arg encrypt "$d_encrypt_yn" \
            --arg keyinfo_name "$d_keyinfo_name" --arg key_name "$d_key_name" \
            --arg input_flags "$d_input_flags" \
            --arg output_flags "$d_output_flags" --arg sync "$d_sync_yn" \
            --arg sync_file "$d_sync_file" --arg sync_index "$d_sync_index" \
            --arg sync_pairs "$d_sync_pairs" --arg schedule_file "$d_schedule_file" \
            --arg flv_delay_seconds "$d_flv_delay_seconds" --arg flv_restart_nums "$d_flv_restart_nums" \
            --arg hls_delay_seconds "$d_hls_delay_seconds" --arg hls_min_bitrates "$d_hls_min_bitrates" \
            --arg hls_max_seg_size "$d_hls_max_seg_size" --arg hls_restart_nums "$d_hls_restart_nums" \
            --arg anti_ddos_port "$d_anti_ddos_port" --arg anti_ddos_seconds "$d_anti_ddos_seconds" \
            --arg anti_ddos_level "$d_anti_ddos_level" --arg anti_leech "$d_anti_leech_yn" \
            --arg anti_leech_restart_nums "$d_anti_leech_restart_nums" --arg anti_leech_restart_flv_changes "$d_anti_leech_restart_flv_changes_yn" \
            --arg anti_leech_restart_hls_changes "$d_anti_leech_restart_hls_changes_yn" --arg version "$sh_ver" \
            '{
                playlist_name: $playlist_name,
                seg_dir_name: $seg_dir_name,
                seg_name: $seg_name,
                seg_length: $seg_length | tonumber,
                seg_count: $seg_count | tonumber,
                video_codec: $video_codec,
                audio_codec: $audio_codec,
                video_audio_shift: $video_audio_shift,
                quality: $quality,
                bitrates: $bitrates,
                const: $const,
                encrypt: $encrypt,
                keyinfo_name: $keyinfo_name,
                key_name: $key_name,
                input_flags: $input_flags,
                output_flags: $output_flags,
                sync: $sync,
                sync_file: $sync_file,
                sync_index: $sync_index,
                sync_pairs: $sync_pairs,
                schedule_file: $schedule_file,
                flv_delay_seconds: $flv_delay_seconds | tonumber,
                flv_restart_nums: $flv_restart_nums | tonumber,
                hls_delay_seconds: $hls_delay_seconds | tonumber,
                hls_min_bitrates: $hls_min_bitrates | tonumber,
                hls_max_seg_size: $hls_max_seg_size | tonumber,
                hls_restart_nums: $hls_restart_nums | tonumber,
                anti_ddos_port: $anti_ddos_port | tonumber,
                anti_ddos_seconds: $anti_ddos_seconds | tonumber,
                anti_ddos_level: $anti_ddos_level | tonumber,
                anti_leech: $anti_leech,
                anti_leech_restart_nums: $anti_leech_restart_nums | tonumber,
                anti_leech_restart_flv_changes: $anti_leech_restart_flv_changes,
                anti_leech_restart_hls_changes: $anti_leech_restart_hls_changes,
                version: $version
            }'
        )

        JQ replace "$CHANNELS_FILE" default "$default"

        new_channels=""

        for((i=0;i<chnls_count;i++));
        do
            [ -n "$new_channels" ] && new_channels="$new_channels,"

            new_channel=$(
            $JQ_FILE -n --arg pid "${chnls_pid[i]}" --arg status "${chnls_status[i]}" \
                --arg stream_link "${chnls_stream_links[i]}" --arg live "${chnls_live[i]}" \
                --arg output_dir_name "${chnls_output_dir_name[i]}" --arg playlist_name "${chnls_playlist_name[i]}" \
                --arg seg_dir_name "${chnls_seg_dir_name[i]}" --arg seg_name "${chnls_seg_name[i]}" \
                --arg seg_length "${chnls_seg_length[i]}" --arg seg_count "${chnls_seg_count[i]}" \
                --arg video_codec "${chnls_video_codec[i]}" --arg audio_codec "${chnls_audio_codec[i]}" \
                --arg video_audio_shift "${chnls_video_audio_shift[i]}" --arg quality "${chnls_quality[i]}" \
                --arg bitrates "${chnls_bitrates[i]}" --arg const "${chnls_const[i]}" \
                --arg encrypt "${chnls_encrypt[i]}" --arg key_name "${chnls_key_name[i]}" \
                --arg keyinfo_name "${chnls_keyinfo_name[i]}" \
                --arg input_flags "${chnls_input_flags[i]}" --arg output_flags "${chnls_output_flags[i]}" \
                --arg channel_name "${chnls_channel_name[i]}" --arg sync "${chnls_sync[i]}" \
                --arg sync_file "${chnls_sync_file[i]}" --arg sync_index "${chnls_sync_index[i]}" \
                --arg sync_pairs "${chnls_sync_pairs[i]}" --arg flv_status "${chnls_flv_status[i]}" \
                --arg flv_push_link "${chnls_flv_push_link[i]}" --arg flv_pull_link "${chnls_flv_pull_link[i]}" \
                '{
                    pid: $pid | tonumber,
                    status: $status,
                    stream_link: $stream_link,
                    live: $live,
                    output_dir_name: $output_dir_name,
                    playlist_name: $playlist_name,
                    seg_dir_name: $seg_dir_name,
                    seg_name: $seg_name,
                    seg_length: $seg_length | tonumber,
                    seg_count: $seg_count | tonumber,
                    video_codec: $video_codec,
                    audio_codec: $audio_codec,
                    video_audio_shift: $video_audio_shift,
                    quality: $quality,
                    bitrates: $bitrates,
                    const: $const,
                    encrypt: $encrypt,
                    keyinfo_name: $keyinfo_name,
                    key_name: $key_name,
                    input_flags: $input_flags,
                    output_flags: $output_flags,
                    channel_name: $channel_name,
                    sync: $sync,
                    sync_file: $sync_file,
                    sync_index: $sync_index,
                    sync_pairs: $sync_pairs,
                    flv_status: $flv_status,
                    flv_push_link: $flv_push_link,
                    flv_pull_link: $flv_pull_link
                }'
            )

            new_channels="$new_channels$new_channel"
        done

        JQ replace "$CHANNELS_FILE" channels "[$new_channels]"
    fi
    printf '%s' "" > ${LOCK_FILE}
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
                    if [[ $line == *"port"* ]] 
                    then
                        port=${line#*: }
                        port=${port%,*}
                    elif [[ $line == *"id"* ]] 
                    then
                        id=${line#*: \"}
                        id=${id%\"*}
                    elif [[ $line == *"path"* ]] 
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
                if [[ $line == *"port"* ]] 
                then
                    port=${line#*: }
                    port=${port%,*}
                elif [[ $line == *"id"* ]] 
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
                if [[ $line == *"port"* ]] 
                then
                    port=${line#*: }
                    port=${port%,*}
                elif [[ $line == *"id"* ]] 
                then
                    id=${line#*: \"}
                    id=${id%\"*}
                elif [[ $line == *"path"* ]] 
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
                read -p "(默认: Y): " v2ray_stop_yn
                v2ray_stop_yn=${v2ray_stop_yn:-Y}
                if [[ $v2ray_stop_yn == [Yy] ]] 
                then
                    service v2ray  stop
                    echo && echo -e "$info v2ray 已关闭" && echo
                else
                    echo && echo "已取消..." && echo && exit 1
                fi
            else
                echo && echo "v2ray 未运行，是否开启？[Y/n]"
                read -p "(默认: Y): " v2ray_start_yn
                v2ray_start_yn=${v2ray_start_yn:-Y}
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
                    if [[ $line == *"port"* ]] 
                    then
                        port=${line#*: }
                        port=${port%,*}
                    elif [[ $line == *"id"* ]] 
                    then
                        id=${line#*: \"}
                        id=${id%\"*}
                    elif [[ $line == *"path"* ]] 
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
            read -p "(默认: 取消): " domain
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
        *) echo && echo -e "$error 请输入正确的数字 [1-6]" && echo
        ;;
    esac
    exit 0
elif [ "${0##*/}" == "cx" ] 
then
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1

    echo && echo -e "  Xtream Codes 面板 $plain

${green}1.$plain 查看账号
${green}2.$plain 添加账号
${green}3.$plain 更新账号
${green}4.$plain 检测账号
${green}5.$plain 网络获取账号
${green}6.$plain 替换频道账号
" && echo
    read -p "请输入数字 [1-6]：" xtream_codes_num

    case $xtream_codes_num in
        1) 
            [ ! -s "$XTREAM_CODES" ] && echo && echo -e "$error 没有账号 !" && echo && exit 1
            ListXtreamCodes
        ;;
        2) 
            echo && read -p "请输入账号(需包含服务器地址)：" xtream_codes_input
            [ -z "$xtream_codes_input" ] && echo && echo "已取消..." && echo && exit 1

            if [[ $xtream_codes_input == *"username="* ]] 
            then
                domain=${xtream_codes_input#*http://}
                domain=${domain%%/*}
                username=${xtream_codes_input#*username=}
                username=${username%%&*}
                password=${xtream_codes_input#*password=}
                password=${password%%&*}
                ip=$(getent ahosts "${domain%%:*}" | awk '{ print $1 ; exit }' || true)
            elif [[ $xtream_codes_input == *http://*/*/*/* ]] 
            then
                xtream_codes_input=${xtream_codes_input#*http://}
                domain=${xtream_codes_input%%/*}
                xtream_codes_input=${xtream_codes_input#*/}
                username=${xtream_codes_input%%/*}
                if [ "$username" == "live" ] 
                then
                    xtream_codes_input=${xtream_codes_input#*/}
                    username=${xtream_codes_input%%/*}
                fi
                xtream_codes_input=${xtream_codes_input#*/}
                password=${xtream_codes_input%%/*}
                ip=$(getent ahosts "${domain%%:*}" | awk '{ print $1 ; exit }' || true)
            else
                echo && echo -e "$error 输入错误 !" && echo && exit 1
            fi

            [ -z "${ip:-}" ] && echo && echo -e "$error 无法解析域名 !" && echo && exit 1
            printf '%s\n' "$ip $domain $username:$password" >> "$XTREAM_CODES"

            if [ -e "$CHANNELS_FILE" ] 
            then
                while IFS= read -r line 
                do
                    if [[ $line == *\"stream_link\":* ]] && [[ $line == *http://*/*/*/* ]]
                    then
                        line=${line#*: \"http://}
                        chnl_domain=${line%%/*}
                        if [ "$chnl_domain" == "$domain" ] 
                        then
                            line=${line#*/}
                            username=${line%%/*}
                            if [ "$username" == "live" ] 
                            then
                                line=${line#*/}
                                username=${line%%/*}
                            fi
                            line=${line#*/}
                            password=${line%%/*}
                            printf '%s\n' "$ip $chnl_domain $username:$password" >> "$XTREAM_CODES"
                        fi
                    fi
                done < "$CHANNELS_FILE"
            fi

            echo && echo -e "$info 账号添加成功 !" && echo

            ListXtreamCodes
        ;;
        3) 
            [ ! -s "$XTREAM_CODES" ] && echo && echo -e "$error 没有账号 !" && echo && exit 1
            echo && echo -e "$info 更新中..." && echo
            result=""
            while IFS= read -r line 
            do
                line=${line#* }
                domain_line=${line%% *}
                account_line=${line#* }
                IFS="|" read -ra domains <<< "$domain_line"
                IFS=" " read -ra accounts <<< "$account_line"
                for account in "${accounts[@]}"
                do
                    for domain in "${domains[@]}"
                    do
                        ip=$(getent ahosts "${domain%%:*}" | awk '{ print $1 ; exit }' || true)
                        if [ -n "${ip:-}" ] 
                        then
                            [ -n "$result" ] && result="$result\n"
                            result="$result$ip $domain $account"
                        fi
                    done
                done
            done < "$XTREAM_CODES"
            echo -e "$result" >> "$XTREAM_CODES"
            ListXtreamCodes
            echo && echo -e "$info 账号更新成功" && echo
        ;;
        4) 
            [ ! -s "$XTREAM_CODES" ] && echo && echo -e "$error 没有账号 !" && echo && exit 1
            ListXtreamCodes
            TestXtreamCodes
        ;;
        5) 
            echo && echo -e "$info 稍等..." && echo
            result=""
            while IFS= read -r line 
            do
                line=${line#* }
                domain_line=${line%% *}
                account_line=${line#* }
                IFS="|" read -ra domains <<< "$domain_line"
                IFS=" " read -ra accounts <<< "$account_line"
                for account in "${accounts[@]}"
                do
                    for domain in "${domains[@]}"
                    do
                        ip=$(getent ahosts "${domain%%:*}" | awk '{ print $1 ; exit }' || true)
                        if [ -n "${ip:-}" ] 
                        then
                            [ -n "$result" ] && result="$result\n"
                            result="$result$ip $domain $account"
                        fi
                    done
                done
            done < <(wget --tries=3 --no-check-certificate $XTREAM_CODES_LINK -qO-)
            echo -e "$result" >> "$XTREAM_CODES"
            ListXtreamCodes
            echo && echo -e "$info 账号添加成功" && echo
        ;;
        6) 
            echo && echo -e "$error not ready~" && echo
        ;;
        *) echo && echo -e "$error 请输入正确的数字 [1-6]" && echo
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

            cmd=${2:-}

            case $cmd in
                "s"|"stop") 
                    MonitorStop
                ;;
                "l"|"log")
                    if [ -s "$MONITOR_LOG" ] 
                    then
                        echo -e "$info 监控日志: "
                        count=0
                        log=""
                        last_line=""
                        printf -v this_hour '%(%H)T'
                        while IFS= read -r line 
                        do
                            if [ "$count" -lt "${3:-10}" ] 
                            then
                                message=${line#* }
                                message=${message#* }
                                if [ -z "$last_line" ] 
                                then
                                    count=$((count+1))
                                    log=$line
                                    last_line=$message
                                elif [ "$message" != "$last_line" ] 
                                then
                                    count=$((count+1))
                                    log="$line\n$log"
                                    last_line="$message"
                                fi
                            fi

                            if [ "${line:2:1}" == "-" ] 
                            then
                                hour=${line:6:2}
                            elif [ "${line:2:1}" == ":" ] 
                            then
                                hour=${line:0:2}
                            fi

                            if [ -n "${hour:-}" ] && [ "$hour" != "$this_hour" ] && [ "$count" -eq "${3:-10}" ] 
                            then
                                break
                            elif [ -n "${hour:-}" ] && [ "$hour" == "$this_hour" ] && [[ $line == *"计划重启时间"* ]]
                            then
                                [ -z "${found_line:-}" ] && found_line=$line
                            fi
                        done < <(awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--] }' "$MONITOR_LOG")
                        echo -e "$log"
                        [ -n "${found_line:-}" ] && echo && echo -e "$green${found_line#* }$plain"
                    fi
                    if [ -s "$IP_LOG" ] 
                    then
                        echo && echo -e "$info AntiDDoS 日志: "
                        tail -n 10 "$IP_LOG"
                    fi
                    if [ ! -s "$MONITOR_LOG" ] && [ ! -s "$IP_LOG" ]
                    then
                        echo -e "$error 无日志"
                    fi
                ;;
                *) 
                    if [ ! -s "$MONITOR_PID" ] 
                    then
                        printf -v date_now '%(%m-%d %H:%M:%S)T'
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
                            printf -v date_now '%(%m-%d %H:%M:%S)T'
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
        *)
        ;;
    esac
fi

use_menu=1

while getopts "i:l:o:p:S:t:s:c:v:a:f:q:b:k:K:m:n:z:T:L:Ce" flag
do
    use_menu=0
    case "$flag" in
        i) stream_link="$OPTARG";;
        l) live_yn="no";;
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
        vi "${d_sync_file%% *}" && exit 0
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
        JQ add "$CHANNELS_FILE" channels "$channels"
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

        wget --no-check-certificate "https://www.johnvansickle.com/ffmpeg/index.html" -qO "$FFMPEG_MIRROR_ROOT/index.html_tmp"
        mv "$FFMPEG_MIRROR_ROOT/index.html_tmp" "$FFMPEG_MIRROR_ROOT/index.html"
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

        while IFS= read -r line
        do
            if [[ $line == *"latest stable release is"* ]] 
            then
                line=${line#*<a href=\"}
                poppler_name=${line%%.tar.xz*}
                poppler_name="poppler-0.81.0"
                if [ ! -e "$FFMPEG_MIRROR_ROOT/$poppler_name.tar.xz" ] 
                then
                    rm -rf "$FFMPEG_MIRROR_ROOT/poppler-"*.tar.xz
                    wget --timeout=10 --tries=3 --no-check-certificate "https://poppler.freedesktop.org/$poppler_name.tar.xz" -qO "$FFMPEG_MIRROR_ROOT/$poppler_name.tar.xz_tmp"
                    mv "$FFMPEG_MIRROR_ROOT/$poppler_name.tar.xz_tmp" "$FFMPEG_MIRROR_ROOT/$poppler_name.tar.xz"
                fi
            elif [[ $line == *"poppler encoding data"* ]] 
            then
                line=${line#*<a href=\"}
                poppler_data_name=${line%%.tar.gz*}
                if [ ! -e "$FFMPEG_MIRROR_ROOT/$poppler_data_name.tar.gz" ] 
                then
                    rm -rf "$FFMPEG_MIRROR_ROOT/poppler-data-"*.tar.gz
                    wget --timeout=10 --tries=3 --no-check-certificate "https://poppler.freedesktop.org/$poppler_data_name.tar.gz" -qO "$FFMPEG_MIRROR_ROOT/$poppler_data_name.tar.gz_tmp"
                    mv "$FFMPEG_MIRROR_ROOT/$poppler_data_name.tar.gz_tmp" "$FFMPEG_MIRROR_ROOT/$poppler_data_name.tar.gz"
                fi
                break
            fi
        done < <( wget --timeout=10 --tries=3 --no-check-certificate "https://poppler.freedesktop.org/" -qO- )

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

        wget --timeout=10 --tries=3 --no-check-certificate "https://github.com/winshining/nginx-http-flv-module/archive/master.zip" -qO "$FFMPEG_MIRROR_ROOT/nginx-http-flv-module.zip_tmp"
        mv "$FFMPEG_MIRROR_ROOT/nginx-http-flv-module.zip_tmp" "$FFMPEG_MIRROR_ROOT/nginx-http-flv-module.zip"
        wget --timeout=10 --tries=3 --no-check-certificate "https://github.com/eddieantonio/imgcat/archive/master.zip" -qO "$FFMPEG_MIRROR_ROOT/imgcat.zip_tmp"
        mv "$FFMPEG_MIRROR_ROOT/imgcat.zip_tmp" "$FFMPEG_MIRROR_ROOT/imgcat.zip"
        wget --timeout=10 --tries=3 --no-check-certificate "https://api.github.com/repos/stedolan/jq/releases/latest" -qO "$FFMPEG_MIRROR_ROOT/jq.json_tmp"
        mv "$FFMPEG_MIRROR_ROOT/jq.json_tmp" "$FFMPEG_MIRROR_ROOT/jq.json"

        if [ ! -e "$FFMPEG_MIRROR_ROOT/fontforge-20190413.tar.gz" ] 
        then
            wget --timeout=10 --tries=3 --no-check-certificate "https://github.com/fontforge/fontforge/releases/download/20190413/fontforge-20190413.tar.gz" -qO "$FFMPEG_MIRROR_ROOT/fontforge-20190413.tar.gz_tmp"
            mv "$FFMPEG_MIRROR_ROOT/fontforge-20190413.tar.gz_tmp" "$FFMPEG_MIRROR_ROOT/fontforge-20190413.tar.gz"
        fi

        if [ ! -e "$FFMPEG_MIRROR_ROOT/pdf2htmlEX-0.18.7-poppler-0.81.0.zip" ] 
        then
            wget --timeout=10 --tries=3 --no-check-certificate "https://github.com/pdf2htmlEX/pdf2htmlEX/archive/v0.18.7-poppler-0.81.0.zip" -qO "$FFMPEG_MIRROR_ROOT/pdf2htmlEX-0.18.7-poppler-0.81.0.zip_tmp"
            mv "$FFMPEG_MIRROR_ROOT/pdf2htmlEX-0.18.7-poppler-0.81.0.zip_tmp" "$FFMPEG_MIRROR_ROOT/pdf2htmlEX-0.18.7-poppler-0.81.0.zip"
        fi
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
        chnls_flv_pull_link=()
        while IFS= read -r flv_channel
        do
            flv_count=$((flv_count+1))
            map_channel_name=${flv_channel#*channel_name: }
            map_channel_name=${map_channel_name%, stream_link:*}
            map_stream_link=${flv_channel#*, stream_link: }
            map_stream_link=${map_stream_link%, flv_pull_link:*}
            map_flv_pull_link=${flv_channel#*, flv_pull_link: }
            map_flv_pull_link=${map_flv_pull_link%\"}

            chnls_channel_name+=("$map_channel_name")
            chnls_stream_link+=("${map_stream_link// /, }")
            chnls_flv_pull_link+=("${map_flv_pull_link}")
        done < <($JQ_FILE '.channels | to_entries | map(select(.value.flv_status=="on")) | map("channel_name: \(.value.channel_name), stream_link: \(.value.stream_link), flv_pull_link: \(.value.flv_pull_link)") | .[]' "$CHANNELS_FILE")

        if [ "$flv_count" -gt 0 ] 
        then

            echo && echo "FLV 频道" && echo

            for((i=0;i<flv_count;i++));
            do
                if [ "$i" -lt 9 ] 
                then
                    blank=" "
                else
                    blank=""
                fi
                chnl_flv_pull_link=${chnls_flv_pull_link[i]}
                echo -e "  $green$((i+1)).$plain $blank$green${chnls_channel_name[i]}$plain\n      源: ${chnls_stream_link[i]}\n      pull: ${chnl_flv_pull_link:-无}\n"
            done
        fi


        hls_count=0
        chnls_channel_name=()
        chnls_stream_link=()
        chnls_output_dir_name=()
        while IFS= read -r hls_channel
        do
            hls_count=$((hls_count+1))
            map_channel_name=${hls_channel#*channel_name: }
            map_channel_name=${map_channel_name%, stream_link:*}
            map_stream_link=${hls_channel#*stream_link: }
            map_stream_link=${map_stream_link%, output_dir_name:*}
            map_output_dir_name=${hls_channel#*output_dir_name: }
            map_output_dir_name=${map_output_dir_name%\"}

            chnls_channel_name+=("$map_channel_name")
            chnls_stream_link+=("${map_stream_link// /, }")
            chnls_output_dir_name+=("$map_output_dir_name")
        done < <($JQ_FILE '.channels | to_entries | map(select(.value.status=="on")) | map("channel_name: \(.value.channel_name), stream_link: \(.value.stream_link), output_dir_name: \(.value.output_dir_name)") | .[]' "$CHANNELS_FILE")

        if [ "$hls_count" -gt 0 ] 
        then
            echo && echo "HLS 频道" && echo

            for((i=0;i<hls_count;i++));
            do
                if [ "$i" -lt 9 ] 
                then
                    blank=" "
                else
                    blank=""
                fi
                echo -e "  $green$((i+1)).$plain $blank$green${chnls_channel_name[i]}$plain\n      源: ${chnls_stream_link[i]}\n"
            done
        fi

        echo 

        for((i=0;i<hls_count;i++));
        do
            echo -e "  $green$((i+1)).$plain ${chnls_channel_name[i]} ${chnls_stream_link[i]}"
            if [ -e "$LIVE_ROOT/${chnls_output_dir_name[i]}" ] 
            then
                if ls -A "$LIVE_ROOT/${chnls_output_dir_name[i]}"/* > /dev/null 2>&1 
                then
                    ls "$LIVE_ROOT/${chnls_output_dir_name[i]}"/* -lght && echo
                else
                    echo -e "$error 无" && echo
                fi
            else
                echo -e "$error 目录不存在" && echo
            fi
        done
        

        if ls -A $LIVE_ROOT/* > /dev/null 2>&1 
        then
            for output_dir_root in "$LIVE_ROOT"/* ; do
                found=0
                output_dir_name=${output_dir_root#*$LIVE_ROOT/}
                for((i=0;i<hls_count;i++));
                do
                    if [ "$output_dir_name" == "${chnls_output_dir_name[i]}" ] 
                    then
                        found=1
                    fi
                done
                if [ "$found" == 0 ] 
                then
                    echo && echo -e "$error 未知目录 $output_dir_name" && echo
                    if ls -A "$output_dir_root"/* > /dev/null 2>&1 
                    then
                        ls "$output_dir_root"/* -lght
                    fi
                fi
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
  ${green}4.$plain 状态
  ${green}5.$plain 开关
  ${green}6.$plain 重启
————————————
  ${green}7.$plain 配置域名和目录
  ${green}8.$plain flv 配置
  ${green}9.$plain 日志切割
————————————
  ${green}10.$plain 安装 pdf2htmlEX
  ${green}11.$plain 安装 tesseract
 " && echo
        read -p "请输入数字 [1-11]：" nginx_num
        case "$nginx_num" in
            1) 
                if [ -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 已经存在 !" && echo && exit 1
                fi

                echo && echo "因为是编译 nginx，耗时会很长，是否继续？[y/N]"
                read -p "(默认: N): " nginx_install_yn
                nginx_install_yn=${nginx_install_yn:-N}
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
            4) 
                if [ ! -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 未安装 !" && echo
                else
                    if [ ! -s "/usr/local/nginx/logs/nginx.pid" ] 
                    then
                        echo && echo -e "nginx 状态: $red关闭$plain" && echo
                    else
                        PID=$(< "/usr/local/nginx/logs/nginx.pid")
                        if kill -0  "$PID" 2> /dev/null
                        then
                            echo && echo -e "nginx 状态: $green开启$plain" && echo
                        else
                            echo && echo -e "nginx 状态: $red开启$plain" && echo
                        fi
                    fi

                    domain=""
                    flv=0
                    while IFS= read -r line 
                    do
                        if [ -z "$domain" ] && [[ $line == *"server_name"* ]] 
                        then
                            line=${line#*server_name  }
                            domain=${line%;*}
                        elif [[ $line == *"location /flv"* ]] 
                        then
                            flv=1
                        fi
                    done < "/usr/local/nginx/conf/nginx.conf"

                    if [ "$domain" == "localhost" ] 
                    then
                        echo -e "域名: $red未设置$plain" && echo
                    else
                        echo -e "域名: $green${domain// /, }$plain" && echo
                    fi

                    if [ "$flv" == 0 ]
                    then
                        echo -e "flv 配置: $red未设置$plain" && echo
                    else
                        echo -e "flv 配置: $green已设置$plain flv 推流地址为 rtmp://127.0.0.1/flv/xxx" && echo
                    fi
                fi
            ;;
            5) ToggleNginx
            ;;
            6) 
                RestartNginx
                echo && echo -e "$info Nginx 已重启" && echo
            ;;
            7) 
                if [ ! -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 未安装 !" && echo && exit 1
                fi

                echo && echo "输入指向本机的域名"
                echo -e "$tip 多个域名用空格分隔" && echo
                read -p "(默认: 不设置域名): " domain

                echo && echo "设置公开的根目录" && echo
                while read -p "(默认: /usr/local/nginx/html): " root 
                do
                    if [ -z "$root" ] 
                    then
                        root="/usr/local/nginx/html"
                        break
                    elif [ "${root:0:1}" != "/" ] 
                    then
                        echo && echo -e "$error 输入错误" && echo
                    else
                        if [ "${root: -1}" == "/" ] 
                        then
                            root=${root:0:-1}
                        fi

                        mkdir -p "$root"
                        break
                    fi
                done

                if [ -e "$IPTV_ROOT" ] 
                then
                    echo && echo "设置公开目录下的(live目录 - HLS输出目录)位置" && echo
                    while read -p "(默认: $root/): " live 
                    do
                        if [ -z "$live" ] 
                        then
                            live=$root
                            ln -sf "$LIVE_ROOT" "$live/"
                            break
                        elif [ "${live:0:1}" != "/" ] 
                        then
                            echo && echo -e "$error 输入错误" && echo
                        else
                            if [ "${live: -1}" == "/" ] 
                            then
                                live=${live:0:-1}
                            fi

                            mkdir -p "$live"
                            ln -sf "$LIVE_ROOT" "$live/"
                            break
                        fi
                    done
                fi

                nginx_conf=$(< "/usr/local/nginx/conf/nginx.conf")
                if ! grep -q "allow all" <<< "$nginx_conf"
                then
                    echo && echo "是否屏蔽所有阿里云ip段 [y/N]"
                    read -p "(默认: N): " block
                    block=${block:-N}
                    if [[ $block == [Yy] ]] 
                    then
                        echo && echo "输入本机IP"
                        echo -e "$tip 多个IP用空格分隔" && echo

                        while read -p "(默认: 自动检测): " server_ip
                        do
                            [ -z "$server_ip" ] && server_ip=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
                            [ -z "$server_ip" ] && server_ip=$(curl --silent ipv4.icanhazip.com)
                            [ -z "$server_ip" ] && server_ip=$(curl --silent api.ip.sb/ip)
                            [ -z "$server_ip" ] && server_ip=$(curl --silent ipinfo.io/ip)
                            if [ -z "$server_ip" ]
                            then
                                echo && echo -e "$error 无法获取本机IP，请手动输入" && echo
                            else
                                break
                            fi
                        done

                        start=0
                        deny="            location ${live#*$root}/${LIVE_ROOT##*/} {"

                        IFS=" " read -ra server_ips <<< "$server_ip"
                        for ip in "${server_ips[@]}"
                        do
                            deny="$deny\n                allow $ip;"
                        done

                        while IFS= read -r line 
                        do
                            if [[ $line == *"ipTabContent"* ]] 
                            then
                                start=1
                            elif [ "$start" == 1 ] && [[ $line == *"AS45102"* ]] 
                            then
                                line=${line#*AS45102\/}
                                ip=${line%\"*}
                                deny="$deny\n                deny $ip;"
                            elif [ "$start" == 1 ] && [[ $line == *"</tbody>"* ]] 
                            then
                                break
                            fi
                        done < <(wget --no-check-certificate https://ipinfo.io/AS45102 -qO-)
                        deny="$deny\n                allow all;"
                        deny="$deny\n            }"
                    fi
                fi

                conf=""
                done=0
                while IFS= read -r line 
                do
                    if [ "$done" == 0 ] && [ -n "$domain" ] && [[ $line == *"server_name"* ]] 
                    then
                        line="        server_name  $domain;"
                    elif [ "$done" == 0 ] && [ -n "${deny:-}" ] && [[ $line == *"location / {"* ]]
                    then
                        line="$line\n\n$deny\n"
                    elif [ "$done" == 0 ] && [[ $line == *"root "* ]] 
                    then
                        line="            root   ${root#*/usr/local/nginx/};"
                        done=1
                    fi
                    [ -n "$conf" ] && conf="$conf\n"
                    conf="$conf$line"
                done < "/usr/local/nginx/conf/nginx.conf"

                echo -e "$conf" > "/usr/local/nginx/conf/nginx.conf"
                echo && echo -e "$info 配置成功" && echo
            ;;
            8) 
                if [ ! -e "/usr/local/nginx" ] 
                then
                    echo && echo -e "$error Nginx 未安装 !" && echo
                else
                    NginxConfigFlv
                    if [ -z "${conf:-}" ]
                    then
                        echo && echo -e "$error flv 配置已存在! flv 推流地址为 rtmp://127.0.0.1/flv/xxx" && echo
                    else
                        echo && echo -e "$info flv 配置已添加，是否重启 Nginx ？[Y/n]"
                        read -p "(默认: Y): " restart_yn
                        restart_yn=${restart_yn:-Y}
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
            9) 
                if [ ! -e "$IPTV_ROOT" ] 
                then
                    echo && echo -e "$error 请先安装脚本 !" && echo && exit 1
                fi

                if [ -e "/usr/local/nginx" ] 
                then
                    chown nobody:root /usr/local/nginx/logs/*.log
                    chmod 660 /usr/local/nginx/logs/*.log
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
    [ ! -f /usr/local/nginx/logs/nginx.pid ] || /bin/kill -USR1 `cat /usr/local/nginx/logs/nginx.pid`
  endscript
}
'
                    fi

                    logrotate="$logrotate
$IPTV_ROOT/*.log {
  monthly
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
            10)
                if [[ ! -x $(command -v pdf2htmlEX) ]] 
                then
                    echo && echo -e "$info 检查依赖，耗时可能会很长..."
                    CheckRelease
                    echo && echo "因为是编译 pdf2htmlEX，耗时会很长，是否继续？[y/N]"
                    read -p "(默认: N): " pdf2html_install_yn
                    pdf2html_install_yn=${pdf2html_install_yn:-N}
                    if [[ $pdf2html_install_yn == [Yy] ]] 
                    then
                        InstallPdf2html
                        echo && echo -e "$info pdf2htmlEX 安装完成，输入 source /etc/profile 可立即使用" && echo
                    else
                        echo && echo "已取消..." && echo && exit 1
                    fi
                else
                    echo && echo -e "$error pdf2htmlEX 已存在!" && echo
                fi
            ;;
            11)
                if [[ ! -x $(command -v tesseract) ]] 
                then
                    echo && echo -e "$info 检查依赖，耗时可能会很长..."
                    CheckRelease
                    echo
                    if [ "$release" == "ubu" ] 
                    then
                        add-apt-repository ppa:alex-p/tesseract-ocr
                        apt-get -y update
                        apt-get -y install tesseract
                    elif [ "$release" == "ubu" ] 
                    then
                        echo && echo -e "$info 参考 https://notesalexp.org/tesseract-ocr/ ..." && echo
                    else
                        echo && echo -e "$info 参考 https://tesseract-ocr.github.io/tessdoc/Home.html ..." && echo
                    fi
                else
                    echo && echo -e "$error tesseract 已存在!" && echo
                fi
            ;;
            *) echo && echo -e "$error 请输入正确的数字 [1-11]" && echo
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
    [ ! -e "$XC_FILE" ] && ln -s "$SH_FILE" "$XC_FILE"
    echo && echo -e "  IPTV 一键管理脚本（mpegts / flv => hls / flv 推流）${red}[v$sh_ver]$plain
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
  ${green}9.$plain 查看日志
 ${green}10.$plain 删除频道

 $tip 输入: tv 打开 HLS 面板, tv f 打开 FLV 面板" && echo
    echo && read -p "请输入数字 [1-10]：" menu_num
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
        9) ViewChannelLog
        ;;
        10) DelChannel
        ;;
        *) echo && echo -e "$error 请输入正确的数字 [1-10]" && echo
        ;;
    esac
else
    if [ -z "${stream_link:-}" ]
    then
        Usage
    else
        CheckRelease
        FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
        FFMPEG="$FFMPEG_ROOT/ffmpeg"
        if [ ! -e "$FFMPEG" ]
        then
            echo && read -p "尚未安装,是否现在安装？[y/N] (默认: N): " install_yn
            install_yn=${install_yn:-N}
            if [[ $install_yn == [Yy] ]]
            then
                Install
            else
                echo && echo "已取消..." && echo && exit 1
            fi
        else
            GetDefault
            export FFMPEG
            live_yn=${live_yn:-yes}
            output_dir_name=${output_dir_name:-$(RandOutputDirName)}
            output_dir_root="$LIVE_ROOT/$output_dir_name"
            playlist_name=${playlist_name:-$(RandPlaylistName)}
            export SEGMENT_DIRECTORY=${seg_dir_name:-}
            seg_name=${seg_name:-$playlist_name}
            seg_length=${seg_length:-$d_seg_length}
            seg_count=${seg_count:-$d_seg_count}
            export AUDIO_CODEC=${audio_codec:-$d_audio_codec}
            export VIDEO_CODEC=${video_codec:-$d_video_codec}
            
            video_audio_shift=${video_audio_shift:-}
            v_or_a=${video_audio_shift%_*}
            if [ "$v_or_a" == "v" ] 
            then
                video_shift=${video_audio_shift#*_}
            elif [ "$v_or_a" == "a" ] 
            then
                audio_shift=${video_audio_shift#*_}
            fi

            quality=${quality:-$d_quality}
            bitrates=${bitrates:-$d_bitrates}
            quality_command=""
            bitrates_command=""

            if [ -z "${kind:-}" ] && [ "$VIDEO_CODEC" == "copy" ] && [ "$AUDIO_CODEC" == "copy" ]
            then
                quality=""
                bitrates=""
                const=""
                const_yn="no"
                master=0
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

                if [ -n "$quality" ] 
                then
                    const=""
                    const_yn="no"
                fi

                if [ -n "$bitrates" ] 
                then
                    if [[ $bitrates != *"-"* ]] && [[ $bitrates == *"x"* ]]
                    then
                        master=0
                    else
                        master=1
                    fi
                else
                    master=0
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

            keyinfo_name=${keyinfo_name:-$d_keyinfo_name}
            keyinfo_name=${keyinfo_name:-$(RandStr)}
            key_name=${key_name:-$d_key_name}
            key_name=${key_name:-$(RandStr)}

            if [ "${stream_link:0:4}" == "rtmp" ] || [ "${stream_link:0:1}" == "/" ]
            then
                d_input_flags=${d_input_flags//-timeout 2000000000/}
                d_input_flags=${d_input_flags//-reconnect 1/}
                d_input_flags=${d_input_flags//-reconnect_at_eof 1/}
                d_input_flags=${d_input_flags//-reconnect_streamed 1/}
                d_input_flags=${d_input_flags//-reconnect_delay_max 2000/}
                lead=${d_input_flags%%[^[:blank:]]*}
                d_input_flags=${d_input_flags#${lead}}
            elif [[ $stream_link == *".m3u8"* ]]
            then
                d_input_flags=${d_input_flags//-reconnect_at_eof 1/}
            fi

            input_flags=${input_flags:-$d_input_flags}
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

            channel_name=${channel_name:-$playlist_name}
            sync_yn=$d_sync_yn

            [ ! -e $FFMPEG_LOG_ROOT ] && mkdir $FFMPEG_LOG_ROOT
            from="command"

            if [ -n "${kind:-}" ] 
            then
                if [ "$kind" == "flv" ] 
                then
                    if [ -z "${flv_push_link:-}" ] 
                    then
                        echo && echo -e "$error 未设置推流地址..." && echo && exit 1
                    else
                        flv_pull_link=${flv_pull_link:-}
                        ( FlvStreamCreatorWithShift ) > /dev/null 2>/dev/null </dev/null &
                    fi
                else
                    echo && echo -e "$error 暂不支持输出 $kind ..." && echo && exit 1
                fi
            elif [ -n "${video_audio_shift:-}" ] || [ "$encrypt_yn" == "yes" ]
            then
                ( HlsStreamCreatorPlus ) > /dev/null 2>/dev/null </dev/null &
            else
                ( HlsStreamCreator ) > /dev/null 2>/dev/null </dev/null &
            fi

            echo -e "$info 添加频道成功..." && echo
        fi
    fi
fi