#!/bin/bash
# LianHuanHua / Alist / FFmpeg / Nginx / Openresty / V2ray / Xray / Cloudflare / IBM Cloud Foundry / Armbian / Proxmox VE / ...
# Copyright (C) 2019-2024
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
