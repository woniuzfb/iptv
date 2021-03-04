#!/bin/bash

set -euo pipefail

green="\033[32m"
red="\033[31m"
normal="\033[0m"
info="${green}[信息]${normal}"
error="${red}[错误]${normal}"

Println()
{
    printf '%b' "\n$1\n"
}

inquirer()
{
    if [[ ! -x $(command -v tput) ]] 
    then
        if apt-get -y install ncurses-bin >/dev/null 2>&1
        then
            Println "$info 依赖 tput 安装成功..."
        else
            Println "$error 依赖 tput 安装失败..."
            exit 1
        fi
    fi
    local arrow checked unchecked red green blue cyan bold normal dim
    arrow=$(echo -e '\xe2\x9d\xaf')
    checked=$(echo -e '\xe2\x97\x89')
    unchecked=$(echo -e '\xe2\x97\xaf')
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    blue=$(tput setaf 4)
    cyan=$(tput setaf 6)
    bold=$(tput bold)
    normal=$(tput sgr0)
    dim=$'\e[2m'

    inquirer:print() {
        echo "$1"
        tput el
    }

    inquirer:join() {
        local IFS=$'\n'
        local var=("$1"[@])
        local _join_list=("${!var}")
        local first=true
        for item in "${_join_list[@]}"
        do
            if [ "$first" = true ]
            then
                printf "%s" "$item"
                first=false
            else
                printf "${2-, }%s" "$item"
            fi
        done
    }

    inquirer:gen_env_from_options() {
        local IFS=$'\n'
        local var=("$1"[@])
        local _indices=("${!var}")
        var=("$2"[@])
        local _env_names=("${!var}")
        local _checkbox_selected

        for i in $(inquirer:gen_index ${#_env_names[@]})
        do
            _checkbox_selected[i]=false
        done

        for i in "${_indices[@]}"
        do
            _checkbox_selected[i]=true
        done

        for i in $(inquirer:gen_index ${#_env_names[@]})
        do
            printf "%s=%s\n" "${_env_names[i]}" "${_checkbox_selected[i]}"
        done
    }

    inquirer:on_default() {
        true;
    }

    inquirer:on_keypress() {
        local OLD_IFS=$IFS
        local key
        local on_up=${1:-inquirer:on_default}
        local on_down=${2:-inquirer:on_default}
        local on_space=${3:-inquirer:on_default}
        local on_enter=${4:-inquirer:on_default}
        local on_left=${5:-inquirer:on_default}
        local on_right=${6:-inquirer:on_default}
        local on_ascii=${7:-inquirer:on_default}
        local on_backspace=${8:-inquirer:on_default}
        local on_not_ascii=${9:-inquirer:on_default}
        _break_keypress=false
        while IFS="" read -rsn1 key
        do
            case "$key" in
                $'\x1b')
                    read -rsn1 key
                    if [[ "$key" == "[" ]]
                    then
                        read -rsn1 key
                        case "$key" in
                        'A') $on_up;;
                        'B') $on_down;;
                        'D') $on_left;;
                        'C') $on_right;;
                        esac
                    fi
                ;;
                $'\x20') $on_space;;
                $'\x7f') $on_backspace $key;;
                '') $on_enter $key;;
                *[$'\x80'-$'\xFF']*) $on_not_ascii $key;;
                # [^ -~]
                *) $on_ascii $key;;
            esac
            if [ "$_break_keypress" = true ]
            then
                break
            fi
        done
        IFS=$OLD_IFS
    }

    inquirer:gen_index() {
        local k=$1
        local l=0
        for((l=0;l<k;l++));
        do
            echo $l
        done
    }

    inquirer:cleanup() {
        # Reset character attributes, make cursor visible, and restore
        # previous screen contents (if possible).
        tput sgr0
        tput cnorm
        stty echo
    }

    inquirer:control_c() {
        inquirer:cleanup
        exit $?
    }

    inquirer:select_indices() {
        local var=("$1"[@])
        local _select_list
        read -r -a _select_list <<< "${!var}"
        var=("$2"[@])
        local _select_indices
        read -r -a _select_indices <<< "${!var}"
        local _select_var_name=$3
        declare -a new_array
        for i in $(inquirer:gen_index ${#_select_indices[@]})
        do
            new_array+=("${_select_list[${_select_indices[i]}]}")
        done
        read -r -a ${_select_var_name?} <<< "${new_array[@]}"
        unset new_array
    }

    inquirer:on_checkbox_input_up() {
        inquirer:remove_checkbox_instructions
        tput cub "$(tput cols)"

        if [ "${_checkbox_selected[$_current_index]}" = true ]
        then
            printf '%s' " ${green}${checked}${normal} ${_checkbox_list[$_current_index]} ${normal}"
        else
            printf '%s' " ${unchecked} ${_checkbox_list[$_current_index]} ${normal}"
        fi
        tput el

        if [ $_current_index = 0 ]
        then
            _current_index=$((${#_checkbox_list[@]}-1))
            tput cud $((${#_checkbox_list[@]}-1))
            tput cub "$(tput cols)"
        else
            _current_index=$((_current_index-1))

            tput cuu1
            tput cub "$(tput cols)"
            tput el
        fi

        if [ "${_checkbox_selected[$_current_index]}" = true ]
        then
            printf '%s' "${cyan}${arrow}${green}${checked}${normal} ${_checkbox_list[$_current_index]} ${normal}"
        else
            printf '%s' "${cyan}${arrow}${normal}${unchecked} ${_checkbox_list[$_current_index]} ${normal}"
        fi
    }

    inquirer:on_checkbox_input_down() {
        inquirer:remove_checkbox_instructions
        tput cub "$(tput cols)"

        if [ "${_checkbox_selected[$_current_index]}" = true ]
        then
            printf '%s' " ${green}${checked}${normal} ${_checkbox_list[$_current_index]} ${normal}"
        else
            printf '%s' " ${unchecked} ${_checkbox_list[$_current_index]} ${normal}"
        fi

        tput el

        if [ $_current_index = $((${#_checkbox_list[@]}-1)) ]
        then
            _current_index=0
            tput cuu $((${#_checkbox_list[@]}-1))
            tput cub "$(tput cols)"
        else
            _current_index=$((_current_index+1))
            tput cud1
            tput cub "$(tput cols)"
            tput el
        fi

        if [ "${_checkbox_selected[$_current_index]}" = true ]
        then
            printf '%s' "${cyan}${arrow}${green}${checked}${normal} ${_checkbox_list[$_current_index]} ${normal}"
        else
            printf '%s' "${cyan}${arrow}${normal}${unchecked} ${_checkbox_list[$_current_index]} ${normal}"
        fi
    }

    inquirer:on_checkbox_input_enter() {
        local OLD_IFS=$IFS
        _checkbox_selected_indices=()
        _checkbox_selected_options=()
        IFS=$'\n'

        for i in $(inquirer:gen_index ${#_checkbox_list[@]})
        do
            if [ "${_checkbox_selected[i]}" = true ]
            then
                _checkbox_selected_indices+=("$i")
                _checkbox_selected_options+=("${_checkbox_list[i]}")
            fi
        done

        tput cud $((${#_checkbox_list[@]}-_current_index))
        tput cub "$(tput cols)"

        for i in $(seq $((${#_checkbox_list[@]}+1)))
        do
            tput el1
            tput el
            tput cuu1
        done
        tput cub "$(tput cols)"

        tput cuf $((prompt_width+3))
        printf '%s' "${cyan}$(inquirer:join _checkbox_selected_options)${normal}"
        tput el

        tput cud1
        tput cub "$(tput cols)"
        tput el

        _break_keypress=true
        IFS=$OLD_IFS
    }

    inquirer:on_checkbox_input_space() {
        inquirer:remove_checkbox_instructions
        tput cub "$(tput cols)"
        tput el
        if [ "${_checkbox_selected[$_current_index]}" = true ]
        then
            _checkbox_selected[$_current_index]=false
        else
            _checkbox_selected[$_current_index]=true
        fi

        if [ "${_checkbox_selected[$_current_index]}" = true ]
        then
            printf '%s' "${cyan}${arrow}${green}${checked}${normal} ${_checkbox_list[$_current_index]} ${normal}"
        else
            printf '%s' "${cyan}${arrow}${normal}${unchecked} ${_checkbox_list[$_current_index]} ${normal}"
        fi
    }

    inquirer:remove_checkbox_instructions() {
        if [ "$_first_keystroke" = true ]
        then
            tput cuu $((_current_index+1))
            tput cub "$(tput cols)"
            tput cuf $((prompt_width+3))
            tput el
            tput cud $((_current_index+1))
            _first_keystroke=false
        fi
    }

    inquirer:on_checkbox_input_ascii() {
        local key=$1
        case $key in
            "w" ) inquirer:on_checkbox_input_up;;
            "s" ) inquirer:on_checkbox_input_down;;
        esac
    }

    inquirer:_checkbox_input() {
        local i j var=("$2"[@])
        _checkbox_list=("${!var}")
        _current_index=0
        _first_keystroke=true

        trap inquirer:control_c SIGINT EXIT

        stty -echo
        tput civis

        inquirer:print "${green}?${normal} ${bold}${prompt}${normal} ${dim}(按 <space> 选择, <enter> 确认)${normal}"

        for i in $(inquirer:gen_index ${#_checkbox_list[@]})
        do
            _checkbox_selected[i]=false
        done

        if [ -n "${3:-}" ]
        then
            var=("$3"[@])
            _selected_indices=("${!var}")
            for i in "${_selected_indices[@]}"
            do
                _checkbox_selected[i]=true
            done
        fi

        for i in $(inquirer:gen_index ${#_checkbox_list[@]})
        do
            tput cub "$(tput cols)"
            if [ $i = 0 ]
            then
                if [ "${_checkbox_selected[i]}" = true ]
                then
                    inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${_checkbox_list[i]} ${normal}"
                else
                    inquirer:print "${cyan}${arrow}${normal}${unchecked} ${_checkbox_list[i]} ${normal}"
                fi
            else
                if [ "${_checkbox_selected[i]}" = true ]
                then
                    inquirer:print " ${green}${checked}${normal} ${_checkbox_list[i]} ${normal}"
                else
                    inquirer:print " ${unchecked} ${_checkbox_list[i]} ${normal}"
                fi
            fi
            tput el
        done

        for j in $(inquirer:gen_index ${#_checkbox_list[@]})
        do
            tput cuu1
        done

        inquirer:on_keypress inquirer:on_checkbox_input_up inquirer:on_checkbox_input_down inquirer:on_checkbox_input_space inquirer:on_checkbox_input_enter inquirer:on_default inquirer:on_default inquirer:on_checkbox_input_ascii
    }

    inquirer:checkbox_input() {
        inquirer:_checkbox_input "$1" "$2"
        _checkbox_input_output_var_name=$3
        inquirer:select_indices _checkbox_list _checkbox_selected_indices $_checkbox_input_output_var_name

        unset _checkbox_list
        unset _break_keypress
        unset _first_keystroke
        unset _current_index
        unset _checkbox_input_output_var_name
        unset _checkbox_selected_indices
        unset _checkbox_selected_options

        inquirer:cleanup
    }

    inquirer:checkbox_input_indices() {
        inquirer:_checkbox_input "$1" "$2" "$3"
        _checkbox_input_output_var_name=$3

        declare -a new_array
        for i in $(inquirer:gen_index ${#_checkbox_selected_indices[@]})
        do
            new_array+=("${_checkbox_selected_indices[i]}")
        done
        read -r -a ${_checkbox_input_output_var_name?} <<< "${new_array[@]}"
        unset new_array

        unset _checkbox_list
        unset _break_keypress
        unset _first_keystroke
        unset _current_index
        unset _checkbox_input_output_var_name
        unset _checkbox_selected_indices
        unset _checkbox_selected_options

        inquirer:cleanup
    }

    inquirer:on_list_input_up() {
        inquirer:remove_list_instructions
        tput cub "$(tput cols)"

        printf '%s' "  ${_list_options[$_list_selected_index]}"
        tput el

        if [ $_list_selected_index = 0 ]
        then
            _list_selected_index=$((${#_list_options[@]}-1))
            tput cud $((${#_list_options[@]}-1))
            tput cub "$(tput cols)"
        else
            _list_selected_index=$((_list_selected_index-1))

            tput cuu1
            tput cub "$(tput cols)"
            tput el
        fi

        printf "${cyan}${arrow} %s ${normal}" "${_list_options[$_list_selected_index]}"
    }

    inquirer:on_list_input_down() {
        inquirer:remove_list_instructions
        tput cub "$(tput cols)"

        printf '%s' "  ${_list_options[$_list_selected_index]}"
        tput el

        if [ $_list_selected_index = $((${#_list_options[@]}-1)) ]
        then
            _list_selected_index=0
            tput cuu $((${#_list_options[@]}-1))
            tput cub "$(tput cols)"
        else
            _list_selected_index=$((_list_selected_index+1))
            tput cud1
            tput cub "$(tput cols)"
            tput el
        fi
        printf "${cyan}${arrow} %s ${normal}" "${_list_options[$_list_selected_index]}"
    }

    inquirer:on_list_input_enter_space() {
        local OLD_IFS=$IFS
        IFS=$'\n'

        tput cud $((${#_list_options[@]}-_list_selected_index))
        tput cub "$(tput cols)"

        for i in $(seq $((${#_list_options[@]}+1)))
        do
            tput el1
            tput el
            tput cuu1
        done
        tput cub "$(tput cols)"

        tput cuf $((prompt_width+3))
        printf '%s' "${cyan}${_list_options[$_list_selected_index]}${normal}"
        tput el

        tput cud1
        tput cub "$(tput cols)"
        tput el

        _break_keypress=true
        IFS=$OLD_IFS
    }

    inquirer:on_list_input_input_ascii()
    {
        local key=$1
        case $key in
            "w" ) inquirer:on_list_input_up;;
            "s" ) inquirer:on_list_input_down;;
        esac
    }

    inquirer:remove_list_instructions() {
        if [ "$_first_keystroke" = true ]
        then
            tput cuu $((_list_selected_index+1))
            tput cub "$(tput cols)"
            tput cuf $((prompt_width+3))
            tput el
            tput cud $((_list_selected_index+1))
            _first_keystroke=false
        fi
    }

    inquirer:_list_input() {
        local i j var=("$2"[@])
        _list_options=("${!var}")

        _list_selected_index=0
        _first_keystroke=true

        trap inquirer:control_c SIGINT EXIT

        stty -echo
        tput civis

        inquirer:print "${green}?${normal} ${bold}${prompt}${normal} ${dim}(使用上下箭头选择)${normal}"

        for i in $(inquirer:gen_index ${#_list_options[@]})
        do
            tput cub "$(tput cols)"
            if [ $i = 0 ]
            then
                inquirer:print "${cyan}${arrow} ${_list_options[i]} ${normal}"
            else
                inquirer:print "  ${_list_options[i]}"
            fi
            tput el
        done

        for j in $(inquirer:gen_index ${#_list_options[@]})
        do
            tput cuu1
        done

        inquirer:on_keypress inquirer:on_list_input_up inquirer:on_list_input_down inquirer:on_list_input_enter_space inquirer:on_list_input_enter_space inquirer:on_default inquirer:on_default inquirer:on_list_input_input_ascii
    }

    inquirer:list_input() {
        inquirer:_list_input "$1" "$2"
        var_name=$3
        read -r ${var_name?} <<< "${_list_options[$_list_selected_index]}"
        unset _list_selected_index
        unset _list_options
        unset _break_keypress
        unset _first_keystroke

        inquirer:cleanup
    }

    inquirer:list_input_index() {
        inquirer:_list_input "$1" "$2"
        var_name=$3
        read -r ${var_name?} <<< "$_list_selected_index"
        unset _list_selected_index
        unset _list_options
        unset _break_keypress
        unset _first_keystroke

        inquirer:cleanup
    }

    inquirer:on_text_input_left() {
        inquirer:remove_regex_failed
        if [[ $_current_pos -gt 0 ]]
        then
            local current=${_text_input:$_current_pos:1} current_width
            current_width=$(inquirer:display_length "$current")

            tput cub $current_width
            _current_pos=$((_current_pos-1))
        fi
    }

    inquirer:on_text_input_right() {
        inquirer:remove_regex_failed
        if [[ $((_current_pos+1)) -eq ${#_text_input} ]] 
        then
            tput cuf1
            _current_pos=$((_current_pos+1))
        elif [[ $_current_pos -lt ${#_text_input} ]]
        then
            local next=${_text_input:$((_current_pos+1)):1} next_width
            next_width=$(inquirer:display_length "$next")

            tput cuf $next_width
            _current_pos=$((_current_pos+1))
        fi
    }

    inquirer:on_text_input_enter() {
        inquirer:remove_regex_failed

        _text_input=${_text_input:-$_text_default_value}

        if [[ $($_text_input_validator "$_text_input") = true ]]
        then
            tput cuu 1
            tput cub "$(tput cols)"
            tput cuf $((prompt_width+3))
            printf '%s' "${cyan}${_text_input}${normal}"
            tput el
            tput cud1
            tput cub "$(tput cols)"
            tput el
            read -r ${var_name?} <<< "$_text_input"
            _break_keypress=true
        else
            _text_input_regex_failed=true
            tput civis
            tput cuu1
            tput cub "$(tput cols)"
            tput cuf $((prompt_width+3))
            tput el
            tput cud1
            tput cub "$(tput cols)"
            tput el
            tput cud1
            tput cub "$(tput cols)"
            printf '%b' "${red}$_text_input_regex_failed_msg${normal}"
            tput el
            _text_input=""
            _current_pos=0
            tput cnorm
        fi
    }

    inquirer:on_text_input_ascii() {
        inquirer:remove_regex_failed
        local c=${1:- }

        local rest=${_text_input:$_current_pos} rest_width
        local current=${_text_input:$_current_pos:1} current_width
        rest_width=$(inquirer:display_length "$rest")
        current_width=$(inquirer:display_length "$current")

        _text_input="${_text_input:0:$_current_pos}$c$rest"
        _current_pos=$((_current_pos+1))

        tput civis
        [[ $current_width -gt 1 ]] && tput cub $((current_width-1))
        printf '%s' "$c$rest"
        tput el

        if [[ $rest_width -gt 0 ]]
        then
            tput cub $((rest_width-current_width+1))
        fi
        tput cnorm
    }

    inquirer:display_length() {
        local display_length=0 byte_len
        local oLC_ALL=${LC_ALL:-} oLANG=${LANG:-} LC_ALL=${LC_ALL:-} LANG=${LANG:-}

        while IFS="" read -rsn1 char
        do
            case "$char" in
                '')
                ;;
                *[$'\x80'-$'\xFF']*) 
                    LC_ALL='' LANG=C
                    byte_len=${#char}
                    LC_ALL=$oLC_ALL LANG=$oLANG
                    if [[ $byte_len -eq 2 ]] 
                    then
                        display_length=$((display_length+1))
                    else
                        display_length=$((display_length+2))
                    fi
                ;;
                *) 
                    display_length=$((display_length+1))
                ;;
            esac
        done <<< "$1"

        echo "$display_length"
    }

    inquirer:on_text_input_not_ascii() {
        inquirer:remove_regex_failed
        local c=$1

        local rest="${_text_input:$_current_pos}" rest_width
        local current=${_text_input:$_current_pos:1} current_width
        rest_width=$(inquirer:display_length "$rest")
        current_width=$(inquirer:display_length "$current")

        _text_input="${_text_input:0:$_current_pos}$c$rest"
        _current_pos=$((_current_pos+1))

        tput civis
        [[ $current_width -gt 1 ]] && tput cub $((current_width-1))
        printf '%s' "$c$rest"
        tput el

        if [[ $rest_width -gt 0 ]]
        then
            tput cub $((rest_width-current_width+1))
        fi
        tput cnorm
    }

    inquirer:on_text_input_backspace() {
        inquirer:remove_regex_failed
        if [ $_current_pos -gt 0 ] || { [ $_current_pos -eq 0 ] && [ "${#_text_input}" -gt 0 ]; }
        then
            local start rest rest_width del del_width next next_width offset
            local current=${_text_input:$_current_pos:1} current_width
            current_width=$(inquirer:display_length "$current")

            tput civis
            if [ $_current_pos -eq 0 ] 
            then
                rest=${_text_input:$((_current_pos+1))}
                next=${_text_input:$((_current_pos+1)):1}
                rest_width=$(inquirer:display_length "$rest")
                next_width=$(inquirer:display_length "$next")
                offset=$((current_width-1))
                [[ $offset -gt 0 ]] && tput cub $offset
                printf '%s' "$rest"
                tput el
                offset=$((rest_width-next_width+1))
                [[ $offset -gt 0 ]] && tput cub $offset
                _text_input=$rest
            else
                rest=${_text_input:$_current_pos}
                start=${_text_input:0:$((_current_pos-1))}
                del=${_text_input:$((_current_pos-1)):1}
                rest_width=$(inquirer:display_length "$rest")
                del_width=$(inquirer:display_length "$del")
                _current_pos=$((_current_pos-1))
                if [[ $current_width -gt 1 ]] 
                then
                    tput cub $((del_width+current_width-1))
                    printf '%s' "$rest"
                    tput el
                    tput cub $((rest_width-current_width+1))
                else
                    tput cub $del_width
                    printf '%s' "$rest"
                    tput el
                    [[ $rest_width -gt 0 ]] && tput cub $((rest_width-current_width+1))
                fi
                _text_input="$start$rest"
            fi
            tput cnorm
        fi
    }

    inquirer:remove_regex_failed() {
        if [ "$_text_input_regex_failed" = true ]
        then
            _text_input_regex_failed=false
            tput sc
            tput cud1
            tput el1
            tput el
            tput rc
        fi
    }

    inquirer:text_input_default_validator() {
        echo true;
    }

    inquirer:text_input() {
        var_name=$2
        if [ -n "$_text_default_value" ] 
        then
            _text_default_tip=" $dim($_text_default_value)"
        else
            _text_default_tip=""
        fi
        _text_input_regex_failed_msg=${4:-"输入验证错误"}
        _text_input_validator=${5:-inquirer:text_input_default_validator}
        _text_input_regex_failed=false

        inquirer:print "${green}?${normal} ${bold}${prompt}$_text_default_tip${normal}"

        trap inquirer:control_c SIGINT EXIT

        stty -echo
        tput cnorm

        inquirer:on_keypress inquirer:on_default inquirer:on_default inquirer:on_text_input_ascii inquirer:on_text_input_enter inquirer:on_text_input_left inquirer:on_text_input_right inquirer:on_text_input_ascii inquirer:on_text_input_backspace inquirer:on_text_input_not_ascii
        read -r ${var_name?} <<< "$_text_input"

        inquirer:cleanup
    }

    local option=$1
    shift
    local var_name prompt=${1:-} prompt_width _text_default_value=${3:-} _current_pos=0 _text_input="" _text_input_regex_failed_msg _text_input_validator _text_input_regex_failed
    prompt_width=$(inquirer:display_length "$prompt")
    inquirer:$option "$@"
}

CompileFFmpeg()
{
    echo
    tls_options=( 'gnutls' 'openssl' )
    inquirer list_input "选择 tls" tls_options tls_option

    nproc="-j$(nproc 2> /dev/null)" || nproc=""

    export CMAKE_PREFIX_PATH="$HOME/ffmpeg_build"
    export PATH="$HOME/ffmpeg_build/bin:$PATH"
    export LDFLAGS="-L$HOME/ffmpeg_build/lib"
    export DYLD_LIBRARY_PATH="$HOME/ffmpeg_build/lib"
    export PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig"
    export CFLAGS="-I$HOME/ffmpeg_build/include $LDFLAGS"

    # zlib
    cd ~/ffmpeg_sources
    if [ ! -d zlib-1.2.11 ] 
    then
        [ ! -f zlib-1.2.11.tar.gz ] && curl -L "https://www.zlib.net/zlib-1.2.11.tar.gz" -o zlib-1.2.11.tar.gz
        tar xzf zlib-1.2.11.tar.gz
    fi
    cd zlib-1.2.11
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --static
    make $nproc
    make install

    # CMake
    cmake_install=1
    if [[ -x $(command -v cmake) ]] 
    then
        cmake_ver=$(cmake --version | awk '{print $3}' | head -1)
        if [[ $cmake_ver =~ ([^.]+).([^.]+).([^.]+) ]] && [[ ${BASH_REMATCH[1]} -lt 14 ]]
        then
            apt-get -y remove cmake
            hash -r
        else
            cmake_install=0
        fi
    fi

    if [ "$cmake_install" -eq 1 ] 
    then
        cd ~/ffmpeg_sources
        if [ ! -d CMake-3.18.4 ] 
        then
            [ ! -f cmake-3.18.4.tar.gz ] && curl -L "https://github.com/Kitware/CMake/archive/v3.18.4.tar.gz" -o cmake-3.18.4.tar.gz
            tar xzf cmake-3.18.4.tar.gz
        fi
        cd CMake-3.18.4
        if [ -f Makefile ] 
        then
            make distclean || true
        fi
        ./bootstrap
        make $nproc
        make install
    fi

    # libbz2
    cd ~/ffmpeg_sources
    if [ ! -d bzip2-1.0.6 ] 
    then
        [ ! -f bzip2-1.0.6.tar.gz ] && curl -L "https://downloads.sourceforge.net/bzip2/bzip2-1.0.6.tar.gz" -o bzip2-1.0.6.tar.gz
        tar xzf bzip2-1.0.6.tar.gz
    fi
    cd bzip2-1.0.6
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    make
    make install PREFIX="$HOME/ffmpeg_build"
    printf '%s' 'prefix=/root/ffmpeg_build
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include

Name: bzip2
Description: bzip2
Version: 1.0.6
Requires:
Libs: -L${libdir} -lbz2
Cflags: -I${includedir}    
' > "$HOME/ffmpeg_build/lib/pkgconfig/bzip2.pc"

    # yasm
    cd ~/ffmpeg_sources
    if [ ! -d yasm-1.3.0 ] 
    then
        [ ! -f yasm-1.3.0.tar.gz ] && curl -L "http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz" -o yasm-1.3.0.tar.gz
        tar xzf yasm-1.3.0.tar.gz
    fi
    cd yasm-1.3.0
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build"
    make $nproc
    make install

    # nasm
    cd ~/ffmpeg_sources
    if [ ! -d nasm-2.15.05 ] 
    then
        [ ! -f nasm-2.15.05.tar.gz ] && curl -L "https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.gz" -o nasm-2.15.05.tar.gz
        tar xzf nasm-2.15.05.tar.gz
    fi
    cd nasm-2.15.05
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build"
    make $nproc
    make install

    # x264
    cd ~/ffmpeg_sources
    git -C x264 pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/x264.git
    cd x264
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --enable-static --enable-pic
    make $nproc
    make install

    # libnuma (for x265)
    cd ~/ffmpeg_sources
    git -C numactl pull 2> /dev/null || git clone --depth 1 https://github.com/numactl/numactl.git
    cd numactl
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # x265
    cd ~/ffmpeg_sources
    rm -rf x265_git
    git clone https://bitbucket.org/multicoreware/x265_git
    cd x265_git/build/linux
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED=OFF -DSTATIC_LINK_CRT=ON -DENABLE_CLI=OFF ../../source
    make $nproc
    sed -i 's/-lgcc_s/-lgcc_eh/g' x265.pc
    make install

    # liblzma (for libxml2, ffmpeg)
    cd ~/ffmpeg_sources
    if [ ! -d xz-5.2.5 ] 
    then
        [ ! -f xz-5.2.5.tar.xz ] && curl -L "https://downloads.sourceforge.net/lzmautils/xz-5.2.5.tar.xz" -o xz-5.2.5.tar.xz
        tar xJf xz-5.2.5.tar.xz
    fi
    cd xz-5.2.5
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static
    make $nproc
    make install

    # libiconv (for libxml2)
    cd ~/ffmpeg_sources
    if [ ! -d libiconv-1.16 ] 
    then
        [ ! -f libiconv-1.16.tar.gz ] && curl -L "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.16.tar.gz" -o libiconv-1.16.tar.gz
        tar xzf libiconv-1.16.tar.gz
    fi
    cd libiconv-1.16
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static
    make $nproc
    make install

    # libxml2
    cd ~/ffmpeg_sources
    rm -rf libxml2
    git clone https://github.com/GNOME/libxml2.git
    mkdir -p libxml2/build
    cd libxml2/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install
    printf '%s' "prefix=$HOME/ffmpeg_build
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libxml2
Description: libxml2
Version: 2.9.10
Requires:
Libs: -L\${libdir} -lxml2
Cflags: -I\${includedir}
" > "$HOME/ffmpeg_build/lib/pkgconfig/libxml-2.0.pc"

    # libpng (for openjpeg)
    cd ~/ffmpeg_sources
    if [ ! -d libpng-1.6.37 ] 
    then
        [ ! -f libpng-1.6.37.tar.gz ] && curl -L "https://downloads.sourceforge.net/libpng/libpng-1.6.37.tar.gz" -o libpng-1.6.37.tar.gz
        tar xzf libpng-1.6.37.tar.gz
    fi
    cd libpng-1.6.37
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --enable-static=yes --enable-shared=no
    make $nproc
    make install

    # c2man (for fribidi)
    cd ~/ffmpeg_sources
    rm -rf c2man
    git clone --depth 1 https://github.com/fribidi/c2man.git
    cd c2man
    rm -rf "$HOME/ffmpeg_sources/c2man_build"
    rm -f "$HOME/ffmpeg_build/bin/c2man"
    mkdir "$HOME/ffmpeg_sources/c2man_build"
    ./Configure -dE
    echo "binexp=$HOME/ffmpeg_build/bin" >> config.sh
    echo "installprivlib=$HOME/ffmpeg_sources/c2man_build" >> config.sh
    echo "mansrc=$HOME/ffmpeg_sources/c2man_build" >> config.sh
    sh config_h.SH
    sh flatten.SH
    sh Makefile.SH
    make depend
    make
    make install

    # fribidi (for libass)
    cd ~/ffmpeg_sources
    if [ ! -d fribidi-1.0.10 ] 
    then
        [ ! -f fribidi-1.0.10.tar.gz ] && curl -L "https://github.com/fribidi/fribidi/archive/v1.0.10.tar.gz" -o fribidi-1.0.10.tar.gz
        tar xzf fribidi-1.0.10.tar.gz
    fi
    cd fribidi-1.0.10
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static
    make $nproc
    make install

    # libass
    cd ~/ffmpeg_sources
    if [ ! -d libass-0.14.0 ] 
    then
        [ ! -f libass-0.14.0.tar.gz ] && curl -L "https://github.com/libass/libass/archive/0.14.0.tar.gz" -o libass-0.14.0.tar.gz
        tar xzf libass-0.14.0.tar.gz
    fi
    cd libass-0.14.0
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # zvbi
    cd ~/ffmpeg_sources
    if [ ! -d zvbi-0.2.35 ] 
    then
        [ ! -f zvbi-0.2.35.tar.bz2 ] && curl -L "https://downloads.sourceforge.net/zapping/zvbi/zvbi-0.2.35.tar.bz2" -o zvbi-0.2.35.tar.bz2
        tar xjf zvbi-0.2.35.tar.bz2
    fi
    cd zvbi-0.2.35
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static
    make $nproc
    make install

    # sdl2
    cd ~/ffmpeg_sources
    rm -rf SDL2-2.0.12
    [ ! -f SDL2-2.0.12.tar.gz ] && curl -L "https://www.libsdl.org/release/SDL2-2.0.12.tar.gz" -o SDL2-2.0.12.tar.gz
    tar xzf SDL2-2.0.12.tar.gz
    mkdir -p SDL2-2.0.12/build
    cd SDL2-2.0.12/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX:PATH="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # lame
    cd ~/ffmpeg_sources
    if [ ! -d lame-3.100 ] 
    then
        [ ! -f lame-3.100.tar.gz ] && curl -L "https://downloads.sourceforge.net/lame/lame/lame-3.100.tar.gz" -o lame-3.100.tar.gz
        tar xzf lame-3.100.tar.gz
    fi
    cd lame-3.100
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --enable-nasm --disable-shared
    make $nproc
    make install

    # opus
    cd ~/ffmpeg_sources
    rm -rf opus
    git -C opus pull 2> /dev/null || git clone --depth 1 https://github.com/xiph/opus.git
    cd opus
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # libvpx
    cd ~/ffmpeg_sources
    git -C libvpx pull 2> /dev/null || git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git
    cd libvpx
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm --enable-pic
    make $nproc
    make install

    # soxr
    cd ~/ffmpeg_sources
    rm -rf soxr-0.1.3-Source
    [ ! -f soxr-0.1.3-Source.tar.xz ] && curl -L "https://downloads.sourceforge.net/soxr/soxr-0.1.3-Source.tar.xz" -o soxr-0.1.3-Source.tar.xz
    tar xJf soxr-0.1.3-Source.tar.xz
    mkdir -p soxr-0.1.3-Source/build
    cd soxr-0.1.3-Source/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF -DWITH_OPENMP=OFF -DBUILD_TESTS=OFF ..
    make $nproc
    make install

    # vidstab
    cd ~/ffmpeg_sources
    rm -rf vid.stab-1.1.0
    [ ! -f vid.stab-1.1.0.tar.gz ] && curl -L "https://github.com/georgmartius/vid.stab/archive/v1.1.0.tar.gz" -o vid.stab-1.1.0.tar.gz
    tar xzf vid.stab-1.1.0.tar.gz
    mkdir -p vid.stab-1.1.0/build
    cd vid.stab-1.1.0/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX:PATH="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # openjpeg
    cd ~/ffmpeg_sources
    rm -rf openjpeg-2.3.1
    [ ! -f openjpeg-2.3.1.tar.gz ] && curl -L "https://github.com/uclouvain/openjpeg/archive/v2.3.1.tar.gz" -o openjpeg-2.3.1.tar.gz
    tar xzf openjpeg-2.3.1.tar.gz
    mkdir -p openjpeg-2.3.1/build
    cd openjpeg-2.3.1/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # zimg
    cd ~/ffmpeg_sources
    git -C zimg pull 2> /dev/null || git clone --depth 1 https://github.com/sekrit-twc/zimg.git
    cd zimg
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --enable-static  --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # libwebp
    cd ~/ffmpeg_sources
    if [ ! -d libwebp-1.0.0 ] 
    then
        [ ! -f libwebp-1.0.0.tar.gz ] && curl -L "https://github.com/webmproject/libwebp/archive/v1.0.0.tar.gz" -o libwebp-1.0.0.tar.gz
        tar xzf libwebp-1.0.0.tar.gz
    fi
    cd libwebp-1.0.0
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # fdk-aac
    cd ~/ffmpeg_sources
    git -C fdk-aac pull 2> /dev/null || git clone --depth 1 https://github.com/mstorsjo/fdk-aac.git
    cd fdk-aac
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # libogg
    cd ~/ffmpeg_sources
    if [ ! -d ogg-1.3.4 ] 
    then
        [ ! -f ogg-1.3.4.tar.gz ] && curl -L "https://github.com/xiph/ogg/archive/v1.3.4.tar.gz" -o ogg-1.3.4.tar.gz
        tar xzf ogg-1.3.4.tar.gz
    fi
    cd ogg-1.3.4
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # libvorbis
    cd ~/ffmpeg_sources
    if [ ! -d vorbis-1.3.7 ] 
    then
        [ ! -f vorbis-1.3.7.tar.gz ] && curl -L "https://github.com/xiph/vorbis/archive/v1.3.7.tar.gz" -o vorbis-1.3.7.tar.gz
        tar xzf vorbis-1.3.7.tar.gz
    fi
    cd vorbis-1.3.7
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # speex
    cd ~/ffmpeg_sources
    if [ ! -d speex-Speex-1.2.0 ] 
    then
        [ ! -f Speex-1.2.0.tar.gz ] && curl -L "https://github.com/xiph/speex/archive/Speex-1.2.0.tar.gz" -o Speex-1.2.0.tar.gz
        tar xzf Speex-1.2.0.tar.gz
    fi
    cd speex-Speex-1.2.0
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./autogen.sh
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
    make $nproc
    make install

    # gmp
    cd ~/ffmpeg_sources
    if [ ! -d gmp-6.2.0 ] 
    then
        [ ! -f gmp-6.2.0.tar.xz ] && curl -L "https://gmplib.org/download/gmp/gmp-6.2.0.tar.xz" -o gmp-6.2.0.tar.xz
        tar xJf gmp-6.2.0.tar.xz
    fi
    cd gmp-6.2.0
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --with-pic
    make $nproc
    make install

    tls_args=()
    if [ "$tls_option" == "openssl" ] 
    then
        tls_args+=( --enable-openssl )
        # openssl
        cd ~/ffmpeg_sources
        if [ ! -d openssl-OpenSSL_1_1_1h ] 
        then
            [ ! -f OpenSSL_1_1_1h.tar.gz ] && curl -L "https://github.com/openssl/openssl/archive/OpenSSL_1_1_1h.tar.gz" -o OpenSSL_1_1_1h.tar.gz
            tar xzf OpenSSL_1_1_1h.tar.gz
        fi
        cd openssl-OpenSSL_1_1_1h
        if [ -f Makefile ] 
        then
            make distclean || true
        fi
        ./config --prefix="$HOME/ffmpeg_build"
        make $nproc
        make install_sw
    else
        tls_args+=( --enable-gnutls )

        # libtasn1
        cd ~/ffmpeg_sources
        if [ ! -d libtasn1-4.16.0 ] 
        then
            [ ! -f libtasn1-4.16.0.tar.gz ] && curl -L "https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.16.0.tar.gz" -o libtasn1-4.16.0.tar.gz
            tar xzf libtasn1-4.16.0.tar.gz
        fi
        cd libtasn1-4.16.0
        if [ -f Makefile ] 
        then
            make distclean || true
        fi
        ./configure --prefix="$HOME/ffmpeg_build" --disable-shared
        make $nproc
        make install

        # nettle
        cd ~/ffmpeg_sources
        if [ ! -d nettle-3.5 ] 
        then
            [ ! -f nettle-3.5.tar.gz ] && curl -L "https://ftp.gnu.org/gnu/nettle/nettle-3.5.tar.gz" -o nettle-3.5.tar.gz
            tar xzf nettle-3.5.tar.gz
        fi
        cd nettle-3.5
        if [ -f Makefile ] 
        then
            make distclean || true
        fi
        ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-pic
        make $nproc
        make install

        # gnutls
        cd ~/ffmpeg_sources
        if [ ! -d gnutls-3.6.15 ] 
        then
            [ ! -f gnutls-3.6.15.tar.xz ] && curl -L "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.6/gnutls-3.6.15.tar.xz" -o gnutls-3.6.15.tar.xz
            tar xJf gnutls-3.6.15.tar.xz
        fi
        cd gnutls-3.6.15
        if [ -f Makefile ] 
        then
            make distclean || true
        fi
        ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static \
        --with-pic --with-included-libtasn1 --with-included-unistring --without-p11-kit --disable-doc
        make $nproc
        make install
    fi

    # fftw
    cd ~/ffmpeg_sources
    rm -rf fftw-3.3.8
    [ ! -f fftw-3.3.8.tar.gz ] && curl -L "http://www.fftw.org/fftw-3.3.8.tar.gz" -o fftw-3.3.8.tar.gz
    tar xzf fftw-3.3.8.tar.gz
    mkdir -p fftw-3.3.8/build
    cd fftw-3.3.8/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # libsamplerate
    cd ~/ffmpeg_sources
    rm -rf libsamplerate
    git clone https://github.com/libsndfile/libsamplerate.git
    mkdir -p libsamplerate/build
    cd libsamplerate/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # vamp-plugin-sdk
    cd ~/ffmpeg_sources
    git -C vamp-plugin-sdk pull 2> /dev/null || git clone https://github.com/c4dm/vamp-plugin-sdk.git
    cd vamp-plugin-sdk
    if [ -f Makefile ] 
    then
        make distclean || true
    fi
    ./configure --prefix="$HOME/ffmpeg_build"
    make $nproc
    make install

    # rubberband
    cd ~/ffmpeg_sources
    rm -rf rubberband-1.9
    [ ! -f rubberband-1.9.tar.gz ] && curl -L "https://github.com/breakfastquay/rubberband/archive/v1.9.tar.gz" -o rubberband-1.9.tar.gz
    tar xzf rubberband-1.9.tar.gz
    cd rubberband-1.9
    if [ ! -f CMakeLists.txt ] 
    then
        curl -L "https://raw.githubusercontent.com/breakfastquay/rubberband/8e09e4a2a9d54e627d5c80da89a0f4d2cdf8f65d/CMakeLists.txt" -o CMakeLists.txt
    fi
    mkdir build
    cd build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" ..
    make $nproc
    make install
    mkdir -p "$HOME/ffmpeg_build/include/rubberband/"
    cp -f ../rubberband/* "$HOME/ffmpeg_build/include/rubberband/"
    printf '%s' "prefix=$HOME/ffmpeg_build
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: rubberband
Version: 1.9
Description:
Libs: -L\${libdir} -lrubberband
Cflags: -I\${includedir}
" > "$HOME/ffmpeg_build/lib/pkgconfig/rubberband.pc"

    # libsrt
    cd ~/ffmpeg_sources
    rm -rf srt-1.4.2
    [ ! -f srt-1.4.2.tar.gz ] && curl -L "https://github.com/Haivision/srt/archive/v1.4.2.tar.gz" -o srt-1.4.2.tar.gz
    tar xzf srt-1.4.2.tar.gz
    mkdir -p srt-1.4.2/build
    cd srt-1.4.2/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED=OFF ..
    make $nproc
    sed -i 's/-lgcc_s/-lgcc_eh/g' srt.pc
    make install

    # libgme
    cd ~/ffmpeg_sources
    rm -rf game-music-emu-0.6.2
    [ ! -f game-music-emu-0.6.2.tar.xz ] && curl -L "https://bitbucket.org/mpyne/game-music-emu/downloads/game-music-emu-0.6.2.tar.xz" -o game-music-emu-0.6.2.tar.xz
    tar xJf game-music-emu-0.6.2.tar.xz
    mkdir -p game-music-emu-0.6.2/build
    cd game-music-emu-0.6.2/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # aom
    cd ~/ffmpeg_sources
    rm -rf aom
    git clone --depth 1 https://aomedia.googlesource.com/aom
    mkdir -p aom/build
    cd aom/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF -DENABLE_NASM=on ..
    make $nproc
    make install

    # SVT-AV1
    cd ~/ffmpeg_sources
    rm -rf SVT-AV1
    git clone https://github.com/AOMediaCodec/SVT-AV1.git
    mkdir -p SVT-AV1/build
    cd SVT-AV1/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DCMAKE_BUILD_TYPE=Release -DBUILD_DEC=OFF -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # vmaf
    cd ~/ffmpeg_sources
    rm -rf vmaf-1.5.3
    [ ! -f vmaf_v1.5.3.tar.gz ] && curl -L https://github.com/Netflix/vmaf/archive/v1.5.3.tar.gz -o vmaf_v1.5.3.tar.gz
    tar zxf vmaf_v1.5.3.tar.gz
    cd vmaf-1.5.3
    pip3 install meson
    pip3 install Cython
    pip3 install numpy
    meson setup libvmaf/build libvmaf --buildtype=release --default-library=static --prefix="$HOME/ffmpeg_build"
    ninja -vC libvmaf/build install
    cp -f ~/ffmpeg_build/lib/*-linux-gnu/pkgconfig/libvmaf.pc ~/ffmpeg_build/lib/pkgconfig/

    # dav1d
    cd ~/ffmpeg_sources
    rm -rf dav1d
    git clone https://code.videolan.org/videolan/dav1d.git
    cd dav1d
    meson build --buildtype release --default-library static --prefix "$HOME/ffmpeg_build" --libdir lib
    cd build
    meson configure
    ninja
    meson test -v
    ninja install

    # graphite2
    cd ~/ffmpeg_sources
    rm -rf graphite
    git clone https://github.com/silnrsi/graphite.git
    mkdir -p graphite/build
    cd graphite/build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DBUILD_SHARED_LIBS=OFF ..
    make $nproc
    make install

    # ffmpeg
    cd ~/ffmpeg_sources
    rm -rf ffmpeg
    curl -L https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 -o ffmpeg-snapshot.tar.bz2
    tar xjf ffmpeg-snapshot.tar.bz2

    cd ffmpeg
    curl -L "https://raw.githubusercontent.com/woniuzfb/iptv/master/scripts/Add-SVT-HEVC-FLV-support-on-FFmpeg-git.patch" -o Add-SVT-HEVC-FLV-support-on-FFmpeg-git.patch
    patch -p1 < Add-SVT-HEVC-FLV-support-on-FFmpeg-git.patch
    ./configure \
    --prefix="$HOME/ffmpeg_build" \
    --pkg-config-flags="--static" \
    --extra-cflags="-fopenmp -I$HOME/ffmpeg_build/include -I$HOME/ffmpeg_build/include/libxml2" \
    --extra-ldflags="-static -fopenmp -L$HOME/ffmpeg_build/lib" \
    --extra-libs="-lpthread -lfftw3 -lsamplerate -lz -llzma -liconv -lm -lstdc++" \
    --disable-debug \
    --disable-shared \
    --disable-indev=sndio \
    --disable-outdev=sndio \
    --enable-static \
    --enable-gpl \
    --enable-pic \
    --enable-ffplay \
    --enable-version3 \
    --enable-iconv \
    --enable-fontconfig \
    --enable-frei0r \
    --enable-gmp \
    --enable-libgme \
    --enable-gray \
    --enable-libaom \
    --enable-libfribidi \
    --enable-libass \
    --enable-libfdk-aac \
    --enable-libfreetype \
    --enable-libmp3lame \
    --enable-libopencore-amrnb \
    --enable-libopencore-amrwb \
    --enable-libopenjpeg \
    --enable-libsoxr \
    --enable-libspeex \
    --enable-libvorbis \
    --enable-libopus \
    --enable-libtheora \
    --enable-libvidstab \
    --enable-libvo-amrwbenc \
    --enable-libvpx \
    --enable-libwebp \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libsvtav1 \
    --enable-libdav1d \
    --enable-libxvid \
    --enable-libzvbi \
    --enable-libzimg \
    --enable-nonfree \
    --enable-librubberband \
    --enable-libsrt \
    --enable-libvmaf \
    --enable-libxml2 ${tls_args[@]+"${tls_args[@]}"}
    make $nproc
    Println "$info ffmpeg 编译成功\n"
}

CompileFFmpeg