#!/bin/bash

set -euo pipefail

sh_ver="0.1.3"
SH_FILE="/usr/local/bin/tv"
IPTV_ROOT="/usr/local/iptv"
LIVE_ROOT="$IPTV_ROOT/live"
CREATOR_FILE="$IPTV_ROOT/HLS-Stream-Creator.sh"
JQ_FILE="$IPTV_ROOT/jq"
CHANNELS_FILE="$IPTV_ROOT/channels.json"
CHANNELS_TMP="$IPTV_ROOT/channels.tmp"
DEFAULT_FILE="http://hbo.epub.fun/default.json"
LOCK_FILE="$IPTV_ROOT/lock"
green="\033[32m"
red="\033[31m"
plain="\033[0m"
info="${green}[信息]$plain"
error="${red}[错误]$plain"
tip="${green}[注意]$plain"

[ $EUID -ne 0 ] && echo -e "[$error] 当前账号非ROOT(或没有ROOT权限),无法继续操作,请使用$green sudo su $plain来获取临时ROOT权限（执行后会提示输入当前账号的密码）." && exit 1

default='
{
    "seg_dir_name":"",
    "seg_length":6,
    "seg_count":5,
    "video_codec":"h264",
    "audio_codec":"aac",
    "quality":"",
    "bitrates":"900-1280x720",
    "const":"no",
    "encrypt":"no",
    "input_flags":"-reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -timeout 2000000000 -y -thread_queue_size 55120 -nostats -nostdin -hide_banner -loglevel fatal -probesize 65536",
    "output_flags":"-g 30 -sc_threshold 0 -sn -preset superfast -pix_fmt yuv420p -profile:v main",
    "sync_file":"",
    "sync_index":"data:0:channels",
    "sync_pairs":"chnl_name:channel_name,chnl_id:output_dir_name,chnl_pid:pid,chnl_cat=港澳台,url=http://xxx.com/live",
    "schedule_file":"",
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
            if [ -n "$($JQ_FILE '.channels[] | select(.pid=='"$chnl_pid"')' $CHANNELS_FILE)" ]
            then
                GetChannelInfo
            fi
        ;;
        *)
            echo -e "$error $action ???" && exit 1
        ;;
    esac

    new_pid=${new_pid:-""}
    d_sync_file=${d_sync_file:-""}
    d_sync_index=${d_sync_index:-""}
    d_sync_pairs=${d_sync_pairs:-""}
    if [ -n "$d_sync_file" ] && [ -n "$d_sync_index" ] && [ -n "$d_sync_pairs" ]
    then
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
            if [ -n "$($JQ_FILE "$jq_index"'[]|select(.chnl_pid=="'"$chnl_pid"'")' "$d_sync_file")" ] 
            then
                $JQ_FILE "$jq_index"' -= ['"$jq_index"'[]|select(.chnl_pid=="'"$chnl_pid"'")]' "$d_sync_file" > "$CHANNELS_TMP"
                mv "$CHANNELS_TMP" "$d_sync_file"
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
                                key=$(echo "$b" | cut -d= -f1)
                                value=$(echo "$b" | cut -d= -f2)
                                if [[ $value == *"http"* ]]  
                                then
                                    value="$value/$chnl_output_dir_name/${chnl_playlist_name}_master.m3u8"
                                fi
                                if [ -z "$jq_channel_edit" ] 
                                then
                                    jq_channel_edit="$jq_channel_edit(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key)=\"${value}\""
                                else
                                    jq_channel_edit="$jq_channel_edit|(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key)=\"${value}\""
                                fi
                            else
                                key=$(echo "$b" | cut -d: -f1)
                                value=$(echo "$b" | cut -d: -f2)
                                value="chnl_$value"

                                if [ "$value" == "chnl_pid" ] 
                                then
                                    if [ -n "$new_pid" ] 
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
            done <<< "$d_sync_pairs"
            if [ "$action" == "add" ] || [ -z "$($JQ_FILE "$jq_index"'[]|select(.chnl_pid=="'"$chnl_pid"'")' "$d_sync_file")" ]
            then
                jq_channel_add="${jq_channel_add}}]"
                $JQ_FILE "$jq_index"' += '"$jq_channel_add"'' "$d_sync_file" > "$CHANNELS_TMP"
                mv "$CHANNELS_TMP" "$d_sync_file"
            else
                jq_channel_edit="$jq_channel_edit|(${jq_index}[]|select(.chnl_pid==\"$chnl_pid\")|.$key_last)=\"${value_last}\""
                $JQ_FILE "${jq_channel_edit}" "$d_sync_file" > "$CHANNELS_TMP"
                mv "$CHANNELS_TMP" "$d_sync_file"
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
        wget --no-check-certificate "https://johnvansickle.com/ffmpeg/builds/$ffmpeg_package" --show-progress -qO "$FFMPEG_PACKAGE_FILE"
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
            wget --no-check-certificate "https://github.com/stedolan/jq/releases/download/$jq_ver/jq-linux$release_bit" --show-progress -qO "$JQ_FILE"
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
        printf "[]" > "$CHANNELS_FILE"
        default='
{
    "default":'"$default"',
    "channels":[]
}'
        $JQ_FILE '(.)='"$default"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        echo -e "$info 安装完成..."
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
        pids=$($JQ_FILE '.channels[].pid' $CHANNELS_FILE)
        for chnl_pid in $pids
        do
            chnl_status=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').status' "$CHANNELS_FILE")
            if [ "$chnl_status" == "on" ]
            then
                StopChannel
            fi
        done
        rm -rf "${IPTV_ROOT:-'notfound'}"
        echo && echo -e "$info 卸载完成 !" && echo
    else
        echo && echo -e "$info 卸载已取消..." && echo
    fi
}

Update()
{
    sh_new_ver=$(wget --no-check-certificate -qO- -t1 -T3 "https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
    [ -z "$sh_new_ver" ] && echo -e "$error 无法链接到 Github !" && exit 1
    if [ "$sh_new_ver" != "$sh_ver" ] 
    then
        rm -rf "${LOCK_FILE:-'notfound'}"
    fi
    wget --no-check-certificate "https://raw.githubusercontent.com/woniuzfb/iptv/master/iptv.sh" -qO "$SH_FILE" && chmod +x "$SH_FILE"
    echo -e "脚本已更新为最新版本[ $sh_new_ver ] !(输入: tv 使用)" && exit 0
}

UpdateSelf()
{
    sh_old_ver=$($JQ_FILE '.default.version' $CHANNELS_FILE)
    if [ "$sh_old_ver" != "$sh_ver" ] 
    then
        $JQ_FILE '(.default)='"$default"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"

        pids=$($JQ_FILE '.channels[].pid' $CHANNELS_FILE)
        for chnl_pid in $pids
        do
            chnl_status=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').status' "$CHANNELS_FILE")
            chnl_stream_link=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').stream_link' "$CHANNELS_FILE")
            chnl_output_dir_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').output_dir_name' "$CHANNELS_FILE")
            chnl_playlist_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').playlist_name' "$CHANNELS_FILE")
            chnl_seg_dir_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').seg_dir_name' "$CHANNELS_FILE")
            chnl_seg_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').seg_name' "$CHANNELS_FILE")
            chnl_seg_length=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').seg_length' "$CHANNELS_FILE")
            chnl_seg_count=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').seg_count' "$CHANNELS_FILE")
            chnl_video_codec=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').video_codec' "$CHANNELS_FILE")
            chnl_audio_codec=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').audio_codec' "$CHANNELS_FILE")
            chnl_quality=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').quality' "$CHANNELS_FILE")
            chnl_bitrates=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').bitrates' "$CHANNELS_FILE")
            chnl_const=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').const' "$CHANNELS_FILE")
            chnl_encrypt=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').encrypt' "$CHANNELS_FILE")
            chnl_key_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').key_name' "$CHANNELS_FILE")
            chnl_input_flags=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').input_flags' "$CHANNELS_FILE")
            chnl_output_flags=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').output_flags' "$CHANNELS_FILE")
            chnl_channel_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').channel_name' "$CHANNELS_FILE")

            $JQ_FILE '.channels -= [.channels[]|select(.pid=='"$chnl_pid"')]' "$CHANNELS_FILE" > "$CHANNELS_TMP"
            mv "$CHANNELS_TMP" "$CHANNELS_FILE"

            if [ "$chnl_const" == "yes" ]
            then
                chnl_const_yn="yes"
            else
                chnl_const_yn="no"
            fi
            if [ "$chnl_encrypt" == "yes" ]
            then
                chnl_encrypt_yn="yes"
            else
                chnl_encrypt_yn="no"
            fi
            $JQ_FILE '.channels += [
                {
                    "pid":'"$chnl_pid"',
                    "status":"'"$chnl_status"'",
                    "stream_link":"'"$chnl_stream_link"'",
                    "output_dir_name":"'"$chnl_output_dir_name"'",
                    "playlist_name":"'"$chnl_playlist_name"'",
                    "seg_dir_name":"'"$chnl_seg_dir_name"'",
                    "seg_name":"'"$chnl_seg_name"'",
                    "seg_length":'"$chnl_seg_length"',
                    "seg_count":'"$chnl_seg_count"',
                    "video_codec":"'"$chnl_video_codec"'",
                    "audio_codec":"'"$chnl_audio_codec"'",
                    "quality":"'"$chnl_quality"'",
                    "bitrates":"'"$chnl_bitrates"'",
                    "const":"'"$chnl_const_yn"'",
                    "encrypt":"'"$chnl_encrypt_yn"'",
                    "key_name":"'"$chnl_key_name"'",
                    "input_flags":"'"$chnl_input_flags"'",
                    "output_flags":"'"$chnl_output_flags"'",
                    "channel_name":"'"$chnl_channel_name"'"
                }
            ]' "$CHANNELS_FILE" > "$CHANNELS_TMP"
            mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        done
        
    fi
    printf "" > ${LOCK_FILE}
}

GetDefault()
{
    default_array=()
    while IFS='' read -r default_line
    do
        default_array+=("$default_line");
    done < <($JQ_FILE -r '.default[] | @sh' "$CHANNELS_FILE")
    d_seg_dir_name=${default_array[0]//\'/}
    d_seg_dir_name_text=${d_seg_dir_name:-"不使用"}
    d_seg_length=${default_array[1]//\'/}
    d_seg_count=${default_array[2]//\'/}
    d_video_codec=${default_array[3]//\'/}
    d_audio_codec=${default_array[4]//\'/}
    d_quality=${default_array[5]//\'/}
    d_quality_text=${d_quality:-"不设置"}
    d_bitrates=${default_array[6]//\'/}
    d_const_yn=${default_array[7]//\'/}
    if [ "$d_const_yn" == "no" ] 
    then
        d_const_yn="N"
        d_const=""
    else
        d_const_yn="Y"
        d_const="-C"
    fi
    d_encrypt_yn=${default_array[8]//\'/}
    if [ "$d_encrypt_yn" == "no" ] 
    then
        d_encrypt_yn="N"
        d_encrypt=""
    else
        d_encrypt_yn="Y"
        d_encrypt="-e"
    fi
    d_input_flags=${default_array[9]//\'/}
    d_output_flags=${default_array[10]//\'/}
    d_sync_file=${default_array[11]//\'/}
    d_sync_index=${default_array[12]//\'/}
    d_sync_pairs=${default_array[13]//\'/}
    d_schedule_file=${default_array[14]//\'/}
}

GetChannelsInfo()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    channels_count=$($JQ_FILE -r '.channels | length' $CHANNELS_FILE)
    [ "$channels_count" == 0 ] && echo -e "$error 没有发现 频道，请检查 !" && exit 1
    IFS=" " read -ra chnls_pid <<< "$($JQ_FILE -r '[.channels[].pid] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_status <<< "$($JQ_FILE -r '[.channels[].status] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_output_dir_name <<< "$($JQ_FILE -r '[.channels[].output_dir_name] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_playlist_name <<< "$($JQ_FILE -r '[.channels[].playlist_name] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_video_codec <<< "$($JQ_FILE -r '[.channels[].video_codec] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_audio_codec <<< "$($JQ_FILE -r '[.channels[].audio_codec] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_quality <<< "$($JQ_FILE -r '[.channels[].quality] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_bitrates <<< "$($JQ_FILE -r '[.channels[].bitrates] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_const <<< "$($JQ_FILE -r '[.channels[].const] | @sh' $CHANNELS_FILE)"
    IFS=" " read -ra chnls_name <<< "$($JQ_FILE -r '[.channels[].channel_name] | @sh' $CHANNELS_FILE)"
}

ListChannels()
{
    GetChannelsInfo
    chnls_list=""
    for((index = 0; index < "$channels_count"; index++)); do
        chnls_status_index=${chnls_status[index]//\'/}
        chnls_pid_index=${chnls_pid[index]//\'/}
        chnls_output_dir_name_index=${chnls_output_dir_name[index]//\'/}
        chnls_output_dir_root="$LIVE_ROOT/$chnls_output_dir_name_index"
        chnls_video_codec_index=${chnls_video_codec[index]//\'/}
        chnls_audio_codec_index=${chnls_audio_codec[index]//\'/}
        chnls_quality_index=${chnls_quality[index]//\'/}
        chnls_playlist_name_index=${chnls_playlist_name[index]//\'/}
        chnls_const_index=${chnls_const[index]//\'/}
        if [ "$chnls_const_index" == "no" ] 
        then
            chnls_const_index_text=" 固定频率:否"
        else
            chnls_const_index_text=" 固定频率:是"
        fi
        chnls_bitrates_index=${chnls_bitrates[index]//\'/}
        if [ -z "$chnls_bitrates_index" ] 
        then
            if [ -z "$d_bitrates" ] 
            then
                d_bitrates="900-1280x720"
            fi
            $JQ_FILE '(.channels[]|select(.pid=='"$chnls_pid_index"')|.bitrates)='"$d_bitrates"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
            mv "$CHANNELS_TMP" "$CHANNELS_FILE"
            chnls_bitrates_index=$d_bitrates
        fi
        chnls_bitrates_index_arr=${chnls_bitrates_index//,/$'\n'}
        chnls_quality_text=""
        chnls_bitrates_text=""
        chnls_playlist_file_text=""
        for chnls_br in $chnls_bitrates_index_arr
        do
            if [[ "$chnls_br" == *"-"* ]]
            then
                chnls_br_a=$(echo "$chnls_br" | cut -d- -f1)
                chnls_br_b=" 分辨率: "$(echo "$chnls_br" | cut -d- -f2)
                chnls_quality_text="${chnls_quality_text}[ -maxrate ${chnls_br_a}k -bufsize ${chnls_br_a}k${chnls_br_b} ] "
                chnls_bitrates_text="${chnls_bitrates_text}[ 比特率 ${chnls_br_a}k${chnls_const_index_text} ] "
                chnls_playlist_file_text="$chnls_playlist_file_text$green$chnls_output_dir_root/${chnls_playlist_name_index}_$chnls_br_a.m3u8$plain "
            else
                chnls_quality_text="${chnls_quality_text}[ -maxrate ${chnls_br}k -bufsize ${chnls_br}k ] "
                chnls_bitrates_text="${chnls_bitrates_text}[ 比特率 ${chnls_br}k${chnls_const_index_text} ] "
                chnls_playlist_file_text="$chnls_playlist_file_text$green$chnls_output_dir_root/${chnls_playlist_name_index}_$chnls_br.m3u8$plain "
            fi
        done
        
        chnls_name_index=${chnls_name[index]//\'/}
        if [ "$chnls_status_index" == "on" ]
        then
            creator_pids=$(pgrep -P "$chnls_pid_index" || true)
            if [ -z "$creator_pids" ] 
            then
                chnls_status_text=$red"关闭"$plain
                $JQ_FILE '(.channels[]|select(.pid=='"$chnls_pid_index"')|.status)="off"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
                mv "$CHANNELS_TMP" "$CHANNELS_FILE"
                chnl_pid=$chnls_pid_index
                StopChannel
            else
                chnls_status_text=$green"开启"$plain
            fi
        else
            chnls_status_text=$red"关闭"$plain
        fi

        if [ -n "$chnls_quality_index" ] 
        then
            chnls_video_quality_text="crf值$chnls_quality_index $chnls_quality_text"
        else
            chnls_video_quality_text="比特率值 $chnls_bitrates_text"
        fi
        chnls_list=$chnls_list"#$((index+1)) 进程ID: $green${chnls_pid_index}$plain 状态: $chnls_status_text 频道名称: $green${chnls_name_index}$plain 编码: $green$chnls_video_codec_index:$chnls_audio_codec_index$plain 视频质量: $green$chnls_video_quality_text$plain m3u8位置: $chnls_playlist_file_text\n\n"
    done
    echo && echo -e "=== 频道总数 $green $channels_count $plain"
    echo -e "$chnls_list\n"
}

GetChannelInfo(){
    d_sync_file=${d_sync_file:-""}
    if [ -z "$d_sync_file" ] 
    then
        GetDefault
    fi
    chnl_info_array=()
    while IFS='' read -r chnl_line
    do
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
    chnl_stream_link=${chnl_info_array[2]//\'/}
    chnl_output_dir_name=${chnl_info_array[3]//\'/}
    chnl_output_dir_root="$LIVE_ROOT/$chnl_output_dir_name"
    chnl_playlist_name=${chnl_info_array[4]//\'/}
    chnl_seg_dir_name=${chnl_info_array[5]//\'/}
    chnl_seg_dir_name_text=${chnl_seg_dir_name:-"不使用"}
    chnl_seg_name=${chnl_info_array[6]//\'/}
    chnl_seg_length=${chnl_info_array[7]//\'/}
    chnl_seg_length_text=$chnl_seg_length"s"
    chnl_seg_count=${chnl_info_array[8]//\'/}
    chnl_video_codec=${chnl_info_array[9]//\'/}
    chnl_audio_codec=${chnl_info_array[10]//\'/}
    chnl_quality=${chnl_info_array[11]//\'/}
    chnl_const=${chnl_info_array[13]//\'/}
    if [ "$chnl_const" == "no" ]
    then
        chnl_const=""
        chnl_const_text=" 固定频率:否"
    else
        chnl_const="-C"
        chnl_const_text=" 固定频率:是"
    fi
    chnl_bitrates=${chnl_info_array[12]//\'/}
    if [ -z "$chnl_bitrates" ] 
    then
        if [ -z "$d_bitrates" ] 
        then
            d_bitrates="900-1280x720"
        fi
        $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.bitrates)='"$d_bitrates"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        chnl_bitrates=$d_bitrates
    fi
    chnl_bitrates_arr=${chnl_bitrates//,/$'\n'}
    chnl_crf_text=""
    chnl_nocrf_text=""
    chnl_playlist_file_text=""
    for chnl_br in $chnl_bitrates_arr
    do
        if [[ "$chnl_br" == *"-"* ]]
        then
            chnl_br_a=$(echo "$chnl_br" | cut -d- -f1)
            chnl_br_b=" 分辨率: "$(echo "$chnl_br" | cut -d- -f2)
            chnl_crf_text="${chnl_crf_text}[ -maxrate ${chnl_br_a}k -bufsize ${chnl_br_a}k${chnl_br_b} ] "
            chnl_nocrf_text="${chnl_nocrf_text}[ 比特率 ${chnl_br_a}k${chnl_const_text} ] "
            chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}_$chnl_br_a.m3u8$plain "
        else
            chnl_crf_text="${chnl_crf_text}[ -maxrate ${chnl_br}k -bufsize ${chnl_br}k ] "
            chnl_nocrf_text="${chnl_nocrf_text}[ 比特率 ${chnl_br}k${chnl_const_text} ] "
            chnl_playlist_file_text="$chnl_playlist_file_text$green$chnl_output_dir_root/${chnl_playlist_name}_$chnl_br.m3u8$plain "
        fi
    done

    if [ -n "$d_sync_file" ] && [ -n "$d_sync_index" ] && [ -n "$d_sync_pairs" ] && [[ $d_sync_pairs == *"=http"* ]] 
    then
        d_sync_pairs_arr=(${d_sync_pairs//=http/ })
        chnl_playlist_link="http$(echo "${d_sync_pairs_arr[1]}" | cut -d, -f1)/$chnl_output_dir_name/${chnl_playlist_name}_master.m3u8"
        chnl_playlist_link_text="$green$chnl_playlist_link$plain"
    else
        chnl_playlist_link_text="$red请先设置 sync$plain"
    fi

    chnl_encrypt=${chnl_info_array[14]//\'/}
    chnl_key_name=${chnl_info_array[15]//\'/}
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
    chnl_input_flags=${chnl_info_array[16]}
    chnl_output_flags=${chnl_info_array[17]}
    chnl_channel_name=${chnl_info_array[18]//\'/}

    if [ -n "$chnl_quality" ] 
    then
        chnl_video_quality_text="crf值$chnl_quality $chnl_crf_text"
    else
        chnl_video_quality_text="比特率值 $chnl_nocrf_text"
    fi
}

ViewChannelInfo()
{
    echo "===================================================" && echo
    echo -e " 频道 [$chnl_channel_name] 的配置信息：" && echo
    echo -e " 进程ID\t    : $green$chnl_pid$plain"
    echo -e " 状态\t    : $chnl_status_text"
    echo -e " 视频源\t    : $green$chnl_stream_link$plain"
    #echo -e " 目录\t    : $green$chnl_output_dir_root$plain"
    echo -e " m3u8名称   : $green$chnl_playlist_name$plain"
    echo -e " m3u8位置   : $chnl_playlist_file_text"
    echo -e " m3u8链接   : $chnl_playlist_link_text"
    echo -e " 段子目录   : $green$chnl_seg_dir_name_text$plain"
    echo -e " 段名称\t    : $green$chnl_seg_name$plain"
    echo -e " 段时长\t    : $green$chnl_seg_length_text$plain"
    echo -e " m3u8包含段数目 : $green$chnl_seg_count$plain"
    echo -e " 视频编码   : $green$chnl_video_codec$plain"
    echo -e " 音频编码   : $green$chnl_audio_codec$plain"
    echo -e " 视频质量   : $green$chnl_video_quality_text$plain"
    echo -e " 加密\t    : $chnl_encrypt_text"
    if [ -n "$chnl_encrypt" ] 
    then
        echo -e " key名称    : $chnl_key_name_text"
    fi
    echo -e " input flags    : $green$chnl_input_flags$plain"
    echo -e " output flags   : $green$chnl_output_flags$plain"
    echo
}

InputChannelsPids()
{
    echo -e "请输入频道的进程ID "
    echo -e "$tip 多个进程ID用空格分隔 "
    while read -p "(默认: 取消):" chnls_pids
    do
        error=0
        IFS=" " read -ra chnls_pids_arr <<< "$chnls_pids"
        [ -z "$chnls_pids" ] && echo "已取消..." && exit 1
        for chnl_pid in "${chnls_pids_arr[@]}"
        do
            case "$chnl_pid" in
                (*[!0-9]*)
                    error=1
                ;;
                (*)
                    if [ -z "$($JQ_FILE '.channels[] | select(.pid=='"$chnl_pid"')' $CHANNELS_FILE)" ]
                    then
                        error=2
                    fi
                ;;
            esac
        done

        case $error in
            1) echo -e "$error 请输入正确的数字！"
            ;;
            2) echo -e "$error 请输入正确的进程ID！"
            ;;
            *) break;
            ;;
        esac
    done
}

ViewChannelMenu(){
    ListChannels
    InputChannelsPids
    for chnl_pid in "${chnls_pids_arr[@]}"
    do
        GetChannelInfo
        ViewChannelInfo
    done
}

SetStreamLink()
{
    echo "请输入直播源(只支持mpegts)"
    read -p "(默认: 取消):" stream_link
    [ -z "$stream_link" ] && echo "已取消..." && exit 1
    echo && echo -e "	直播源: $green $stream_link $plain" && echo
}

SetOutputDirName()
{
    echo "请输入频道输出目录名称"
    echo -e "$tip 是名称不是路径"
    while read -p "(默认: 随机名称):" output_dir_name
    do
        output_dir_name=${output_dir_name:-$(RandOutputDirName)}
        output_dir_root="$LIVE_ROOT/$output_dir_name"
        if [ -e "$output_dir_root" ] 
        then
            echo -e "$error 目录已存在！ "
        else
            break
        fi
    done
    echo && echo -e "	目录名称: $green $output_dir_name $plain" && echo
}

SetPlaylistName()
{
    echo "请输入m3u8名称(前缀)"
    read -p "(默认: 随机名称):" playlist_name
    playlist_name=${playlist_name:-$(RandPlaylistName)}
    echo && echo -e "	m3u8名称: $green $playlist_name $plain" && echo
}

SetSegDirName()
{
    echo "请输入段所在子目录名称"
    read -p "(默认: $d_seg_dir_name_text):" seg_dir_name
    seg_dir_name=${seg_dir_name:-$d_seg_dir_name}
    seg_dir_name_text=${seg_dir_name:-"不使用"}
    echo && echo -e "	段子目录名: $green $seg_dir_name_text $plain" && echo
}

SetSegName()
{
    echo "请输入段名称"
    read -p "(默认: 跟m3u8名称相同):" seg_name
    seg_name=${seg_name:-$playlist_name}
    echo && echo -e "	段名称: $green $seg_name $plain" && echo 
}

SetSegLength()
{
    echo -e "请输入段的时长(单位：s)"
    while read -p "(默认: $d_seg_length):" seg_length
    do
        case "$seg_length" in
            ("")
                seg_length=$d_seg_length
                break
            ;;
            (*[!0-9]*)
                echo -e "$error 请输入正确的数字(大于0) "
            ;;
            (*)
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
    echo "请输入分割段的数目"
    echo -e "$tip 如果填0就是无限"
    while read -p "(默认: $d_seg_count):" seg_count
    do
        case "$seg_count" in
            ("")
                seg_count=$d_seg_count
                break
            ;;
            (*[!0-9]*)
                echo -e "$error 请输入正确的数字(大于等于0) "
            ;;
            (*)
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
    echo "请输入视频编码"
    read -p "(默认: $d_video_codec):" video_codec
    video_codec=${video_codec:-$d_video_codec}
    echo && echo -e "	视频编码: $green $video_codec $plain" && echo
}

SetAudioCodec()
{
    echo "请输入音频编码"
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
            ("")
                quality=$d_quality
                break
            ;;
            (*[!0-9]*)
                echo -e "$error 请输入正确的数字(大于0,小于等于63)或直接回车 "
            ;;
            (*)
                if [ "$quality" -gt 0 ] && [ "$quality" -lt 63 ]
                then
                    break
                else
                    echo -e "$error 请输入正确的数字(大于0,小于等于63)或直接回车 "
                fi
            ;;
        esac
    done
    quality_text=${quality:-"不设置"}
    echo && echo -e "	crf视频质量: $green $quality_text $plain" && echo
}

SetBitrates()
{
    echo "请输入比特率"
    if [ -z "$quality" ] 
    then
        echo -e "$tip 用于指定输出视频比特率"
    else
        echo -e "$tip 用于 -maxrate 和 -bufsize"
    fi
    echo -e "$tip 多个比特率用逗号分隔(生成自适应码流)
    同时可以指定输出的分辨率(比如：600-600x400,900-1280x720)"
    read -p "(默认: $d_bitrates):" bitrates
    bitrates=${bitrates:-$d_bitrates}
    echo && echo -e "	比特率: $green $bitrates $plain" && echo
}

SetConst()
{
    echo "是否使用固定码率[y/N]"
    read -p "(默认: $d_const_yn):" const_yn
    const_yn=${const_yn:-$d_const_yn}
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
    read -p "(默认: $d_encrypt_yn):" encrypt_yn
    encrypt_yn=${encrypt_yn:-$d_encrypt_yn}
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
    read -p "(默认: 跟m3u8名称相同):" key_name
    key_name=${key_name:-$playlist_name}
    echo && echo -e "	key名称: $green $key_name $plain" && echo 
}

SetInputFlags()
{
    echo "请输入input flags"
    read -p "(默认: $d_input_flags):" input_flags
    input_flags=${input_flags:-$d_input_flags}
    echo && echo -e "	input flags: $green $input_flags $plain" && echo 
}

SetOutputFlags()
{
    echo "请输入output flags"
    read -p "(默认: $d_output_flags):" output_flags
    output_flags=${output_flags:-$d_output_flags}
    echo && echo -e "	output flags: $green $output_flags $plain" && echo 
}

SetChannelName()
{
    echo "请输入频道名称(可以是中文)"
    read -p "(默认: 跟m3u8名称相同):" channel_name
    channel_name=${channel_name:-$playlist_name}
    echo && echo -e "	频道名称: $green $channel_name $plain" && echo
}

AddChannel()
{
    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请检查 !" && exit 1
    GetDefault
    SetStreamLink
    SetOutputDirName
    SetPlaylistName
    SetSegDirName
    SetSegName
    SetSegLength
    SetSegCount
    SetVideoCodec
    SetAudioCodec
    SetQuality
    SetBitrates
    if [ -z "$quality" ] 
    then
        SetConst
    else
        const=$d_const
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

    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFMPEG="$FFMPEG_ROOT/ffmpeg"
    export FFMPEG
    FFMPEG_INPUT_FLAGS=${input_flags//\'/}
    AUDIO_CODEC=$audio_codec
    VIDEO_CODEC=$video_codec
    SEGMENT_DIRECTORY=$seg_dir_name
    FFMPEG_FLAGS=${output_flags//\'/}
    export FFMPEG_INPUT_FLAGS
    export AUDIO_CODEC
    export VIDEO_CODEC
    export SEGMENT_DIRECTORY
    export FFMPEG_FLAGS
    exec "$CREATOR_FILE" -l -i "$stream_link" -s "$seg_length" \
        -o "$output_dir_root" -c "$seg_count" -b "$bitrates" \
        -p "$playlist_name" -t "$seg_name" -K "$key_name" -q "$quality" \
        "$const" "$encrypt" &
    pid=$!
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
            "quality":"'"$quality"'",
            "bitrates":"'"$bitrates"'",
            "const":"'"$const_yn"'",
            "encrypt":"'"$encrypt_yn"'",
            "key_name":"'"$key_name"'",
            "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
            "output_flags":"'"$FFMPEG_FLAGS"'",
            "channel_name":"'"$channel_name"'"
        }
    ]' "$CHANNELS_FILE" > "$CHANNELS_TMP"

    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 频道添加成功 !" && echo
    action="add"
    SyncFile
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

EditChannelAll()
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
    SetStreamLink
    SetOutputDirName
    SetPlaylistName
    SetSegDirName
    SetSegName
    SetSegLength
    SetSegCount
    SetVideoCodec
    SetAudioCodec
    SetQuality
    SetBitrates
    if [ -z "$quality" ] 
    then
        SetConst
    else
        const=$d_const
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
    InputChannelsPids
    for chnl_pid in "${chnls_pids_arr[@]}"
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
    ${green}18.$plain 修改 全部配置
    ————— 组合[常用] —————
    ${green}19.$plain 修改 段名称、m3u8名称 (防盗链/DDoS)
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
                EditChannelAll
            ;;
            19)
                EditForSecurity
            ;;
            *)
                echo "请输入正确序号..." && exit 1
            ;;
        esac

        if [ "$chnl_status" == "on" ] && [ "$edit_channel_num" != "2" ]
        then
            echo "是否重启此频道？[Y/n]"
            read -p "(默认: Y):" restart_yn
            restart_yn=${restart_yn:-"Y"}
            if [[ "$restart_yn" == [Yy] ]] 
            then
                action="skip"
                StopChannel
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
    InputChannelsPids
    for chnl_pid in "${chnls_pids_arr[@]}"
    do
        GetChannelInfo
        if [ "$chnl_status" == "on" ] 
        then
            StopChannel
        else
            StartChannel
        fi
    done
}

StartChannel()
{
    FFMPEG_ROOT=$(dirname "$IPTV_ROOT"/ffmpeg-git-*/ffmpeg)
    FFMPEG="$FFMPEG_ROOT/ffmpeg"
    export FFMPEG
    FFMPEG_INPUT_FLAGS=${chnl_input_flags//\'/}
    AUDIO_CODEC=$chnl_audio_codec
    VIDEO_CODEC=$chnl_video_codec
    SEGMENT_DIRECTORY=$chnl_seg_dir_name
    FFMPEG_FLAGS=${chnl_output_flags//\'/}
    export FFMPEG_INPUT_FLAGS
    export AUDIO_CODEC
    export VIDEO_CODEC
    export SEGMENT_DIRECTORY
    export FFMPEG_FLAGS
    exec "$CREATOR_FILE" -l -i "$chnl_stream_link" -s "$chnl_seg_length" \
        -o "$chnl_output_dir_root" -c "$chnl_seg_count" -b "$chnl_bitrates" \
        -p "$chnl_playlist_name" -t "$chnl_seg_name" -K "$chnl_key_name" -q "$chnl_quality" \
        "$chnl_const" "$chnl_encrypt" &
    new_pid=$!
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.pid)='"$new_pid"'|(.channels[]|select(.pid=='"$new_pid"')|.status)="on"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    echo && echo -e "$info 频道进程已开启 !" && echo
    action=${action:-"start"}
    SyncFile
}

StopChannel()
{
    creator_pids=$(pgrep -P "$chnl_pid" || true)
    for creator_pid in $creator_pids
    do
        ffmpeg_pids=$(pgrep -P "$creator_pid" || true)
        for ffmpeg_pid in $ffmpeg_pids
        do
            kill -9 "$ffmpeg_pid" || true
        done
        #or pkill -TERM -P $creator_pid
    done
    remove_dir_name=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').output_dir_name' "$CHANNELS_FILE")
    $JQ_FILE '(.channels[]|select(.pid=='"$chnl_pid"')|.status)="off"' "$CHANNELS_FILE" > "$CHANNELS_TMP"
    mv "$CHANNELS_TMP" "$CHANNELS_FILE"
    rm -rf "$LIVE_ROOT/${remove_dir_name:-'notfound'}"
    echo && echo -e "$info 频道目录删除成功 !" && echo
    echo -e "$info 频道进程$chnl_pid已停止 !" && echo
    action=${action:-"stop"}
    SyncFile
}

RestartChannel()
{
    ListChannels
    InputChannelsPids
    for chnl_pid in "${chnls_pids_arr[@]}"
    do
        GetChannelInfo
        if [ "$chnl_status" == "on" ] 
        then
            action="skip"
            StopChannel
        fi
        StartChannel
        echo && echo -e "$info 频道重启成功 !" && echo
    done
}

DelChannel()
{
    ListChannels
    InputChannelsPids
    for chnl_pid in "${chnls_pids_arr[@]}"
    do
        chnl_status=$($JQ_FILE -r '.channels[]|select(.pid=='"$chnl_pid"').status' "$CHANNELS_FILE")
        if [ "$chnl_status" == "on" ] 
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
    str_size=8
    str_array=(
        q w e r t y u i o p a s d f g h j k l z x c v b n m Q W E R T Y U I O P A S D
F G H J K L Z X C V B N M
    )
    str_array_size=${#str_array[*]}
    str_len=0
    rand_str=""
    while [ $str_len -lt $str_size ]
    do
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
        if [ -z "$($JQ_FILE '.channels[] | select(.outputDirName=="'"$output_dir_name"'")' $CHANNELS_FILE)" ]
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
        if [ -z "$($JQ_FILE '.channels[] | select(.playListName=="'"$playlist_name"'")' $CHANNELS_FILE)" ]
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
        if [ -z "$($JQ_FILE '.channels[] | select(.segDirName=="'"$seg_dir_name"'")' $CHANNELS_FILE)" ]
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

generateSchedule()
{
    chnl_id=${1%%:*}
    chnl_name=${chnl#*:}
    chnl_name=${chnl_name// /-}
    chnl_name_encode=$(urlencode "$chnl_name")

    date_now=$(date -d now "+%Y-%m-%d")

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
            echo -e "\n\nempty: $1\n"
            rm -rf "${SCHEDULE_FILE:-'notfound'}"
            return
        fi
    fi

    programs_title=()
    while IFS='' read -r program_title
    do
        programs_title+=("$program_title");
    done < <($JQ_FILE -r '.list[] | select(.key=="'"$date_now"'").values | .[].name | @sh' "$SCHEDULE_FILE")

    IFS=" " read -ra programs_time <<< "$($JQ_FILE -r '[.list[] | select(.key=="'"$date_now"'").values | .[].time] | @sh' $SCHEDULE_FILE)"

    if [ -z "$($JQ_FILE '.' $SCHEDULE_JSON)" ] 
    then
        printf '{"%s":[]}' "$chnl_id" > "$SCHEDULE_JSON"
    fi

    $JQ_FILE '.'"$chnl_id"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"
    mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"

    rm -rf "${SCHEDULE_FILE:-'notfound'}"

    for((index = 0; index < "$programs_count"; index++)); do
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

schedule()
{
    CheckRelease

    [ ! -e "$IPTV_ROOT" ] && echo -e "$error 尚未安装，请先安装 !" && exit 1
    GetDefault

    if [ -n "$d_schedule_file" ] 
    then
        SCHEDULE_JSON=$d_schedule_file
    else
        echo "请先设置 schedule_file 位置！" && exit 1
    fi

    chnls=( "hbogq:HBO HD"
            "hbohits:HBO Hits"
            "hbosignature:HBO Signature"
            "hbofamily:HBO Family"
            "hycj:寰宇財經台"
            "hyzh:寰宇HD綜合台"
            "hyxwthd:寰宇新聞台"
            "hyxw2t:寰宇新聞二台"
            "aedzh:愛爾達綜合台"
            "aedyj:愛爾達影劇台"
            "etzht:ETtoday綜合台"
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
            "fgss:時尚頻道"
            "gshd:公視"
            "gs2:公視2台"
            "gs3hd:公視3台"
            "tshd:台視"
            "tszh:台視綜合台"
            "tscj:台視財經台"
            "hshd:華視"
            "hsjytywhhd:華視教育文化"
            "zshd:中視"
            "zsxwhd:中視新聞台"
            "zsjd:中視經典台"
            "yzlythd:亞洲旅遊台"
            "yzms:亞洲美食頻道"
            "yzzh:亞洲綜合台"
            "bsgq1hd:博斯高球一台"
            "bsgq2hd:博斯高球二台"
            "bsmlhd:博斯魅力網"
            "bswxhd:博斯無限台"
            "bswqhd:博斯網球台"
            "bsyd2hd:博斯運動二台"
            "bsyd1hd:博斯運動一台"
            "dwtv:DW(Deutsch)"
            "lifetime:Lifetime"
            "tracesports:TRACE Sport Stars"
            "cinemax:Cinemax"
            "oztyhd:EUROSPORT"
            "animax:Animax HD"
            "mtvhd:MTV綜合電視台"
            "ozxw:Euronews"
            "dwxqhd:動物星球頻道"
            "warnertvhd:Warner TV"
            "foxhd:FOX頻道"
            "axnhd:AXN"
            "luxetv:LUXE TV Channel"
            "mgcdh:DREAMWORKS"
            "elevensportsplus:ELEVEN SPORTS PLUS"
            "elevensports2:ELEVEN SPORTS 2"
            "foxsports3:FOX SPORTS 3"
            "ymjst:影迷數位紀實台"
            "ymdyt:影迷數位電影台"
            "hyyjt:華藝影劇台"
            "catchplaydyt:CatchPlay電影台"
            "ccyjt:采昌影劇台"
            "itvchoice:ITV Choice"
            "ifundmt:i-Fun動漫台"
            "mdrbt:曼迪日本台"
            "msxq:美食星球頻道"
            "smartzst:Smart知識台"
            "babytv:Baby TV"
            "mykids:MY-KIDS TV"
            "lspd:歷史頻道"
            "lspd2:HISTORY 2"
            "tv5monde:TV5MONDE"
            "eltvshyy:ELTV生活英語台"
            "outdoor:Outdoor"
            "eentertainment:E! Entertainment"
            "channelv:Channel V國際娛樂台HD"
            "bbccbeebies:CBeebies"
            "dwxpd:DaVinCi Learning達文西頻道"
            "my101zht:MY101綜合台"
            "nickkt:Nickelodeon Asia(尼克兒童頻道)"
            "blueantextreme:BLUE ANT EXTREME"
            "blueantentertainmet:BLUE ANT EXTREME"
            "eyetvxjt:EYE TV戲劇台"
            "eyetvlyt:EYE TV旅遊台"
            "travelchannel:Travel Channel"
            "cnnnews:CNN International"
            "discoveryasia:Discovery Asia"
            "discoveryhd:Discovery"
            "discoverykxhd:Discovery科學頻道"
            "dmaxhd:DMAX頻道"
            "hitshd:HITS"
            "ydyhd:壹電視電影台"
            "yzh:壹電視資訊綜合台"
            "wltyhd:緯來體育台"
            "wlxjhd:緯來戲劇台"
            "wlrbhd:緯來日本台"
            "wldyhd:緯來電影台"
            "wlzhhd:緯來綜合台"
            "wlylhd:緯來育樂台"
            "wljct:緯來精采台"
            "dszhhd:東森綜合台"
            "dsxjhd:東森戲劇台"
            "dsyyhd:東森幼幼台"
            "dsdyhd:東森電影台"
            "dsyphd:東森洋片台"
            "dsxwhd:東森新聞台"
            "dscjxwhd:東森財經新聞台"
            "dscshd:超級電視台"
            "ztxwhd:中天新聞台"
            "ztylhd:中天娛樂台"
            "ztzhhd:中天綜合台"
            "tvbsjct:TVBS精采台"
            "fxhd:FX"
            "foxcrime:FOXCRIME"
            "foxnews:FOX News Channel"
            "slzh:三立綜合台"
            "slxj:三立戲劇台"
            "tvn:tvN"
            "hgylt:韓國娛樂台KMTV"
            "xfkjjjt:幸福空間居家台"
            "skynews:SKY NEWS HD"
            "nhkworld:NHK新聞資訊台"
            "zltyt:智林體育台"
            "xwhddy:星衛HD電影台"
            "xwyl:星衛娛樂台"
            "mydy:美亞電影台"
            "wdozdy:My Cinema Europe HD我的歐洲電影台"
            "gjdlyr:國家地理高畫質悠人頻道"
            "gjdlys:國家地理高畫質野生頻道"
            "gjdlhd:國家地理高畫質頻道"
            "bbcearth:BBC Earth"
            "bbcworldnews:BBC World News"
            "bbclifestyle:BBC Lifestyle Channel"
            "amcrw:AMC"
            "animaxhd:Animax HD"
            "wakawakajapan:WAKUWAKU JAPAN"
            "boomerangkt:Boomerang"
            "tvbj2:TVB J2"
            "tvbxh:TVB星河頻道"
            "tvbfct:TVB 翡翠台"
            "tvbmzt:TVB Pearl"
            "cinemaworld:CinemaWorld"
            "diva:Diva"
            "bloombergtv:Bloomberg TV"
            "fksjtyy:福斯家庭電影台"  )

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
            date_now=$(date -d now "+%Y-%m-%d")

            chnls=(
                "hbo"
                "hbohd"
                "hits"
                "signature"
                "family" )

            for chnl in "${chnls[@]}" ; do

                if [ "$chnl" == "hbo" ] 
                then
                    SCHEDULE_LINK="https://hboasia.com/HBO/zh-cn/ajax/home_schedule?date=$date_now&channel=$chnl&feed=cn"
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

                IFS=" " read -ra programs_id <<< "$($JQ_FILE -r '[.[].id] | @sh' $SCHEDULE_FILE)"
                IFS=" " read -ra programs_time <<< "$($JQ_FILE -r '[.[].time] | @sh' $SCHEDULE_FILE)"
                IFS=" " read -ra programs_sys_time <<< "$($JQ_FILE -r '[.[].sys_time] | @sh' $SCHEDULE_FILE)"

                if [ -z "$($JQ_FILE '.' $SCHEDULE_JSON)" ] 
                then
                    printf '{"%s":[]}' "$chnl" > "$SCHEDULE_JSON"
                fi

                $JQ_FILE '.'"$chnl"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"
                mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"

                rm -rf "${SCHEDULE_FILE:-'notfound'}"

                for((index = 0; index < "$programs_count"; index++)); do
                    programs_id_index=${programs_id[index]//\'/}
                    programs_title_index=${programs_title[index]//\"/}
                    programs_title_index=${programs_title_index//\'/}
                    programs_title_index=${programs_title_index//\\/\'}
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
            date_now=$(date -d now "+%Y%m%d")
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

            IFS=" " read -ra programs_time <<< "$($JQ_FILE -r '[.schedule[].schedule_items[].time] | @sh' $SCHEDULE_FILE)"
            IFS=" " read -ra programs_sys_time <<< "$($JQ_FILE -r '[.schedule[].schedule_items[].iso8601_utc_time] | @sh' $SCHEDULE_FILE)"

            if [ -z "$($JQ_FILE '.' $SCHEDULE_JSON)" ] 
            then
                printf '{"%s":[]}' "$2" > "$SCHEDULE_JSON"
            fi

            $JQ_FILE '.'"$2"' = []' "$SCHEDULE_JSON" > "$SCHEDULE_TMP"
            mv "$SCHEDULE_TMP" "$SCHEDULE_JSON"

            rm -rf "${SCHEDULE_FILE:-'notfound'}"

            for((index = 0; index < "$programs_count"; index++)); do
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
            date_now=$(date -d now "+%Y-%-m-%-d")
            SCHEDULE_LINK="https://www.fng.tw/foxmovies/program.php?go=$date_now"

            SCHEDULE_FILE="$IPTV_ROOT/$2_schedule_$date_now"
            SCHEDULE_TMP="${SCHEDULE_JSON}_tmp"
            wget --no-check-certificate "$SCHEDULE_LINK" -qO "$SCHEDULE_FILE"

            if [ -z "$($JQ_FILE '.' $SCHEDULE_JSON)" ] 
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

            [ "$found" == 0 ] && echo "no support yet ~"
        ;;
    esac
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

举例:
    使用crf值控制视频质量: tv -i http://xxx.com/xxx.ts -s 6 -o hbo1 -p hbo1 -q 15 -b 1500-1280x720 -z 'hbo直播1'
    使用比特率控制视频质量[默认]: tv -i http://xxx.com/xxx.ts -s 6 -o hbo2 -p hbo2 -b 900-1280x720 -z 'hbo直播2'

EOM

exit

}

if [ -e "$IPTV_ROOT" ] && [ ! -e "$LOCK_FILE" ] 
then
    UpdateSelf
fi

if [[ -n ${1+x} ]]
then
    case $1 in
        "s") 
            schedule "$@"
            exit 0
        ;;
        *)
        ;;
    esac
fi

use_menu=1

while getopts "i:o:p:S:t:s:c:v:a:q:b:K:m:n:z:Ce" flag
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
            q) quality="$OPTARG";;
            b) bitrates="$OPTARG";;
            C) const="-C";;
            e) encrypt="-e";;
            K) key_name="$OPTARG";;
            m) input_flags="$OPTARG";;
            n) output_flags="$OPTARG";;
            z) channel_name="$OPTARG";;
            *) Usage;
        esac
done

cmd=$*
case "$cmd" in
    "e") vi "$CHANNELS_FILE" && exit 0
    ;;
    "d")
        wget "$DEFAULT_FILE" -qO "$CHANNELS_TMP"
        channels=$(< $CHANNELS_TMP)
        $JQ_FILE '.channels += '"$channels"'' "$CHANNELS_FILE" > "$CHANNELS_TMP"
        mv "$CHANNELS_TMP" "$CHANNELS_FILE"
        echo && echo -e "$info 频道添加成功 !" && echo
        exit 0
    ;;
    *)
    ;;
esac

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
    stream_link=${stream_link:-""}
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
            export SEGMENT_DIRECTORY=${seg_dir_name:-""}
            seg_name=${seg_name:-"$playlist_name"}
            seg_length=${seg_length:-"$d_seg_length"}
            seg_count=${seg_count:-"$d_seg_count"}
            export AUDIO_CODEC=${audio_codec:-"$d_audio_codec"}
            export VIDEO_CODEC=${video_codec:-"$d_video_codec"}
            quality=${quality:-"$d_quality"}
            bitrates=${bitrates:-"$d_bitrates"}
            const=${const:-"$d_const"}
            encrypt=${encrypt:-"$d_encrypt"}
            key_name=${key_name:-"$playlist_name"}
            export FFMPEG_INPUT_FLAGS=${input_flags:-"$d_input_flags"}
            export FFMPEG_FLAGS=${output_flags:-"$d_output_flags"}
            channel_name=${channel_name:-"$playlist_name"}

            exec "$CREATOR_FILE" -l -i "$stream_link" -s "$seg_length" \
                -o "$output_dir_root" -c "$seg_count" -b "$bitrates" \
                -p "$playlist_name" -t "$seg_name" -K "$key_name" -q "$quality" \
                "$const" "$encrypt" &
            pid=$!

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
                    "quality":"'"$quality"'",
                    "bitrates":"'"$bitrates"'",
                    "const":"'"$const"'",
                    "encrypt":"'"$encrypt"'",
                    "key_name":"'"$key_name"'",
                    "input_flags":"'"$FFMPEG_INPUT_FLAGS"'",
                    "output_flags":"'"$FFMPEG_FLAGS"'",
                    "channel_name":"'"$channel_name"'"
                }
            ]' "$CHANNELS_FILE" > "$CHANNELS_TMP"

            mv "$CHANNELS_TMP" "$CHANNELS_FILE"

            echo -e "$info 添加频道成功..." && echo
        fi
    fi
fi