#!/bin/bash
# Alist / FFmpeg / Nginx / Openresty / V2ray / Xray / Cloudflare / IBM Cloud Foundry / Armbian / Proxmox VE / ...
# Copyright (C) 2019-2023
# Released under GPL Version 3 License

set -euo pipefail

DEV_PATH=$(dirname "$0")

Error()
{
    echo
    exit 1
}

Include()
{
    INCLUDE_PATH="$DEV_PATH"
    include_name="$1"

    while [[ $include_name =~ \/ ]] 
    do
        INCLUDE_PATH="$INCLUDE_PATH/${include_name%%/*}"
        include_name="${include_name#*/}"
    done

    shift

    # shellcheck disable=SC1090
    . "$INCLUDE_PATH/$include_name" "$@" || Error include $?
}

Include ver

Include env

Include core "$@"

Include utils/i18n "$@"

Include build "$@"

if [[ -x $(command -v readlink) ]] && [ -L "$0" ] && alternative=$(readlink "$0") && [ -L "$alternative" ]
then
    self=${alternative##*/}
else
    self=${0##*/}
fi

self=${self%.*}

Include src/$self "$@"

if [ -e "$IPTV_ROOT" ] && [ ! -e "$LOCK_FILE" ] 
then
    Include src/iptv/update_self
fi

if [[ -n ${1+x} ]]
then
    case $1 in
        4g)
            Include src/iptv/menu_4gtv "$@"
        ;;
        s) 
            Include src/iptv/menu_listings "$@"
        ;;
        singtel) 
            Include src/iptv/cmd_singtel "$@"
        ;;
        astro)
            Include src/iptv/cmd_astro "$@"
        ;;
        m) 
            Include src/iptv/cmd_monitor "$@"
        ;;
        e) 
            Include src/iptv/cmd_e "$@"
        ;;
        ee) 
            Include src/iptv/cmd_ee "$@"
        ;;
        d)
            Include src/iptv/cmd_default "$@"
        ;;
        ffmpeg|FFmpeg) 
            Include utils/mirror "$@"
        ;;
        ts) 
            Include src/iptv/menu_ts "$@"
        ;;
        f|flv) 
            [ ! -d "$IPTV_ROOT" ] && Println "$error 尚未安装, 请检查 !\n" && exit 1
            kind="flv"
            color="$blue"
            shift
        ;;
        v|vip) 
            [ ! -d "$IPTV_ROOT" ] && Println "$error 尚未安装, 请检查 !\n" && exit 1
            vip=true
            shift
        ;;
        l|ll) 
            Include src/iptv/cmd_list "$@"
        ;;
        debug)
            Include src/iptv/cmd_debug "$@"
        ;;
        ed|editor)
            Include src/iptv/cmd_ed "$@"
        ;;
        a)
            Include src/iptv/cmd_a "$@"
        ;;
        c)
            Include src/iptv/cmd_c "$@"
        ;;
        color)
            Include src/iptv/menu_color "$@"
        ;;
        curl)
            Include src/iptv/cmd_curl "$@"
        ;;
        b)
            Include src/iptv/cmd_backup "$@"
        ;;
        *)
        ;;
    esac
fi

if [ -z "$*" ]
then
    ShFileCheck
    if [ "${vip:-false}" = true ] 
    then
        VipMenu
    else
        Menu
    fi
else
    Include src/iptv/cmd_add "$@"
fi
