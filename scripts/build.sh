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
    inquirer:print() {
        tput el
        printf '%b' "$1"
    }

    inquirer:print_input() {
        tput el
        printf '%s' "$1"
    }

    inquirer:join() {
        local var=("$1"[@])
        if [[ -z ${!var:-} ]] 
        then
            return
        fi
        local join_list=("${!var}") first=true item
        for item in "${join_list[@]}"
        do
            if [ "$first" = true ]
            then
                printf '%b' "$item"
                first=false
            else
                printf "${2-, }%b" "$item"
            fi
        done
    }

    inquirer:on_default() {
        return
    }

    inquirer:on_keypress() {
        local oIFS=$IFS
        local key char_read byte_len
        local oLC_ALL=${LC_ALL:-} oLANG=${LANG:-}
        local on_up=${1:-inquirer:on_default}
        local on_down=${2:-inquirer:on_default}
        local on_space=${3:-inquirer:on_default}
        local on_enter=${4:-inquirer:on_default}
        local on_left=${5:-inquirer:on_default}
        local on_right=${6:-inquirer:on_default}
        local on_ascii=${7:-inquirer:on_default}
        local on_backspace=${8:-inquirer:on_default}
        local on_not_ascii=${9:-inquirer:on_default}
        break_keypress=false

        while IFS= read -rsn1 key
        do
            case "$key" in
                $'\x1b')
                    read -rsn1 key
                    if [ "$key" == "[" ]
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
                $'\x7f') $on_backspace "$key";;
                '') $on_enter "$key";;
                # The space is the first printable character listed on http://www.asciitable.com/, ~ is the last
                # [^ -~]
                *[$'\x80'-$'\xFF']*) 
                    if [[ ${BASH_VERSINFO[0]} -lt 4 ]] 
                    then
                        char_read="${char_read:-}$key"
                        LC_ALL= LANG=C
                        byte_len=${#char_read}
                        LC_ALL=$oLC_ALL LANG=$oLANG
                        if [ "$byte_len" -ne "${#char_read}" ] 
                        then
                            $on_not_ascii "$char_read"
                            char_read=""
                        fi
                    else
                        $on_not_ascii "$key"
                    fi
                ;;
                $'\x09')
                    local i
                    for((i=0;i<4;i++));
                    do
                        $on_space
                    done
                ;;
                *) $on_ascii "$key";;
            esac
            if [ "$break_keypress" = true ]
            then
                break
            fi
        done

        IFS="$oIFS"
    }

    inquirer:cleanup() {
        tput sgr0
        tput cnorm
        stty echo
    }

    inquirer:control_c() {
        inquirer:cleanup
        exit $?
    }

    inquirer:remove_instructions() {
        if [ "$first_keystroke" = true ]
        then
            tput cuu $((current_index+1))
            tput cub "$(tput cols)"
            tput cuf $((prompt_width+3))
            tput el
            if [ -n "${pages_tip:-}" ] 
            then
                inquirer:print "$pages_tip"
            fi
            tput cud $((current_index+1))
            first_keystroke=false
        fi
    }

    inquirer:page_instructions() {
        tput cuu $((current_index+1))
        tput cub "$(tput cols)"
        tput cuf $((prompt_width+3))
        tput el
        inquirer:print "$pages_tip"
        tput cud $((current_index+1))
    }

    inquirer:on_checkbox_input_up() {
        if [ "$input_search" = true ] 
        then
            tput cub "$(tput cols)"
            tput el
            tput cuu1
            tput el
            tput cuu1
            tput el

            stty -echo
            tput civis

            local i

            for((i=0;i<page_list_count;i++));
            do
                if [ "$i" = "$current_index" ] 
                then
                    if [ "${checkbox_page_selected[i]}" = true ]
                    then
                        inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[i]}\n"
                    else
                        inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[i]}\n"
                    fi
                else
                    if [ "${checkbox_page_selected[i]}" = true ]
                    then
                        inquirer:print " ${green}${checked}${normal} ${page_list[i]}\n"
                    else
                        inquirer:print " ${unchecked} ${page_list[i]}\n"
                    fi
                fi
            done

            tput cuu $((page_list_count-current_index))

            input_search=false
            return
        fi

        inquirer:remove_instructions
        tput cub "$(tput cols)"

        if [ "${checkbox_page_selected[current_index]}" = true ]
        then
            inquirer:print " ${green}${checked}${normal} ${page_list[current_index]}"
        else
            inquirer:print " ${unchecked} ${page_list[current_index]}"
        fi

        if [ $current_index = 0 ]
        then
            current_index=$((page_list_count-1))
            tput cud $((page_list_count-1))
        else
            current_index=$((current_index-1))
            tput cuu1
        fi

        tput cub "$(tput cols)"

        if [ "${checkbox_page_selected[current_index]}" = true ]
        then
            inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[current_index]}"
        else
            inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[current_index]}"
        fi
    }

    inquirer:on_checkbox_input_down() {
        if [ "$input_search" = true ] 
        then
            return
        fi

        inquirer:remove_instructions
        tput cub "$(tput cols)"

        if [ "${checkbox_page_selected[current_index]}" = true ]
        then
            inquirer:print " ${green}${checked}${normal} ${page_list[current_index]}"
        else
            inquirer:print " ${unchecked} ${page_list[current_index]}"
        fi

        if [ $current_index = $((page_list_count-1)) ]
        then
            current_index=0
            tput cuu $((page_list_count-1))
        else
            current_index=$((current_index+1))
            tput cud1
        fi

        tput cub "$(tput cols)"

        if [ "${checkbox_page_selected[current_index]}" = true ]
        then
            inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[current_index]}"
        else
            inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[current_index]}"
        fi
    }

    inquirer:on_checkbox_input_left() {
        if [ -z "${pages_tip:-}" ] 
        then
            return
        fi

        if [ "$input_search" = true ] 
        then
            inquirer:on_text_input_left
            return
        fi

        local i

        if [ "$pages_index" -eq 0 ] 
        then
            pages_index=$((pages_count-1))
            page_list_count=$((list_count-list_perpage*pages_index))
        else
            pages_index=$((pages_index-1))
            page_list_count=$list_perpage
        fi

        pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal}"

        inquirer:page_instructions
        tput cub "$(tput cols)"
        tput cud $((list_perpage-current_index+1))

        for((i=0;i<=list_perpage;i++));
        do
            tput el
            tput cuu1
        done

        tput el

        if [ "$current_index" -gt "$page_list_count" ] 
        then
            current_index=$page_list_count
        fi

        page_list=()
        checkbox_page_selected=()
        checkbox_page_select_all=true

        for((i=0;i<page_list_count;i++));
        do
            page_list+=("${checkbox_list[i+list_perpage*pages_index]}")

            if [ "$i" = "$current_index" ] 
            then
                if [ "${checkbox_selected[i+list_perpage*pages_index]}" = true ]
                then
                    checkbox_page_selected+=("true")
                    inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[i]}\n"
                else
                    checkbox_page_selected+=("false")
                    checkbox_page_select_all=false
                    inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[i]}\n"
                fi
            else
                if [ "${checkbox_selected[i+list_perpage*pages_index]}" = true ]
                then
                    checkbox_page_selected+=("true")
                    inquirer:print " ${green}${checked}${normal} ${page_list[i]}\n"
                else
                    checkbox_page_selected+=("false")
                    checkbox_page_select_all=false
                    inquirer:print " ${unchecked} ${page_list[i]}\n"
                fi
            fi
        done

        page_list+=("$(gettext 全选)")

        if [ "$current_index" -eq $page_list_count ] 
        then
            if [ "$checkbox_page_select_all" = true ] 
            then
                checkbox_page_selected+=("true")
                inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[page_list_count]}\n"
            else
                checkbox_page_selected+=("false")
                inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[page_list_count]}\n"
            fi
        else
            if [ "$checkbox_page_select_all" = true ] 
            then
                checkbox_page_selected+=("true")
                inquirer:print " ${green}${checked}${normal} ${page_list[page_list_count]}\n"
            else
                checkbox_page_selected+=("false")
                inquirer:print " ${unchecked} ${page_list[page_list_count]}\n"
            fi
        fi

        page_list_count=$((page_list_count+1))

        tput cuu $((page_list_count-current_index))
    }

    inquirer:on_checkbox_input_right() {
        if [ -z "${pages_tip:-}" ] 
        then
            return
        fi

        if [ "$input_search" = true ] 
        then
            inquirer:on_text_input_right
            return
        fi

        local i

        if [ "$pages_index" -eq $((pages_count-1)) ] 
        then
            pages_index=0
            page_list_count=$list_perpage
        else
            pages_index=$((pages_index+1))
            if [ "$pages_index" -eq $((pages_count-1)) ] 
            then
                page_list_count=$((list_count-pages_index*list_perpage))
            else
                page_list_count=$list_perpage
            fi
        fi

        pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal}"

        inquirer:page_instructions
        tput cub "$(tput cols)"
        tput cud $((list_perpage-current_index+1))

        for((i=0;i<=list_perpage;i++));
        do
            tput el
            tput cuu1
        done

        tput el

        if [ "$current_index" -gt "$page_list_count" ] 
        then
            current_index=$page_list_count
        fi

        page_list=()
        checkbox_page_selected=()
        checkbox_page_select_all=true

        for((i=0;i<page_list_count;i++));
        do
            page_list+=("${checkbox_list[i+list_perpage*pages_index]}")

            if [ "$i" = "$current_index" ] 
            then
                if [ "${checkbox_selected[i+list_perpage*pages_index]}" = true ]
                then
                    checkbox_page_selected+=("true")
                    inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[i]}\n"
                else
                    checkbox_page_selected+=("false")
                    checkbox_page_select_all=false
                    inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[i]}\n"
                fi
            else
                if [ "${checkbox_selected[i+list_perpage*pages_index]}" = true ]
                then
                    checkbox_page_selected+=("true")
                    inquirer:print " ${green}${checked}${normal} ${page_list[i]}\n"
                else
                    checkbox_page_selected+=("false")
                    checkbox_page_select_all=false
                    inquirer:print " ${unchecked} ${page_list[i]}\n"
                fi
            fi
        done

        page_list+=("$(gettext 全选)")

        if [ "$current_index" -eq $page_list_count ] 
        then
            if [ "$checkbox_page_select_all" = true ] 
            then
                checkbox_page_selected+=("true")
                inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[page_list_count]}\n"
            else
                checkbox_page_selected+=("false")
                inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[page_list_count]}\n"
            fi
        else
            if [ "$checkbox_page_select_all" = true ] 
            then
                checkbox_page_selected+=("true")
                inquirer:print " ${green}${checked}${normal} ${page_list[page_list_count]}\n"
            else
                checkbox_page_selected+=("false")
                inquirer:print " ${unchecked} ${page_list[page_list_count]}\n"
            fi
        fi

        page_list_count=$((page_list_count+1))

        tput cuu $((page_list_count-current_index))
    }

    inquirer:on_input_page() {
        if [ "$input_page" = true ] && [[ "$1" =~ [0-9] ]] 
        then
            input_page_num="${input_page_num:-}$1"
            input_page_num=${input_page_num#\0}
        else
            input_page=true
            input_page_num=""
        fi
    }

    inquirer:on_checkbox_input_enter() {
        local i

        if [ "$input_search" = true ] 
        then
            if [ -n "$text_input" ] 
            then
                tput cub "$(tput cols)"
                tput el
                tput cuu1
                tput el
                tput cuu1
                tput el
                tput cuu1
                tput el
                tput cud1

                local checkbox_list_page

                for i in "${!checkbox_list[@]}"
                do
                    if [[ "${checkbox_list[i]}" =~ "$text_input" ]] 
                    then
                        checkbox_list_page=$((i/list_perpage+1))
                        inquirer:print "${green}P${checkbox_list_page}${normal} ${checkbox_list[i]}\n"
                    fi
                done

                if [ -n "${checkbox_list_page:-}" ] 
                then
                    tput cud1
                fi

                inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${pages_tip:-}${dim}`gettext \"(按 <space> 选择, <enter> 确认)\"`${normal}\n\n\n"
            fi
            inquirer:on_checkbox_input_up
            return
        fi

        if [ "$input_page" = true ] 
        then
            input_page=false
            if [ -n "${input_page_num:-}" ] 
            then
                if [ "$input_page_num" -gt "$pages_count" ] || [ "$input_page_num" -eq $((pages_index+1)) ]
                then
                    input_page_num=""
                    return
                fi

                pages_index=$((input_page_num-1))

                pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal}"

                if [ "$input_page_num" -eq "$pages_count" ] 
                then
                    page_list_count=$((list_count-pages_index*list_perpage))
                else
                    page_list_count=$list_perpage
                fi

                inquirer:page_instructions
                tput cub "$(tput cols)"
                tput cud $((list_perpage-current_index+1))

                for((i=0;i<=list_perpage;i++));
                do
                    tput el
                    tput cuu1
                done

                tput el

                if [ "$current_index" -gt "$page_list_count" ] 
                then
                    current_index=$page_list_count
                fi

                page_list=()
                checkbox_page_selected=()
                checkbox_page_select_all=true

                for((i=0;i<page_list_count;i++));
                do
                    page_list+=("${checkbox_list[i+list_perpage*pages_index]}")

                    if [ "$i" = "$current_index" ] 
                    then
                        if [ "${checkbox_selected[i+list_perpage*pages_index]}" = true ]
                        then
                            checkbox_page_selected+=("true")
                            inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[i]}\n"
                        else
                            checkbox_page_selected+=("false")
                            checkbox_page_select_all=false
                            inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[i]}\n"
                        fi
                    else
                        if [ "${checkbox_selected[i+list_perpage*pages_index]}" = true ]
                        then
                            checkbox_page_selected+=("true")
                            inquirer:print " ${green}${checked}${normal} ${page_list[i]}\n"
                        else
                            checkbox_page_selected+=("false")
                            checkbox_page_select_all=false
                            inquirer:print " ${unchecked} ${page_list[i]}\n"
                        fi
                    fi
                done

                page_list+=("$(gettext 全选)")

                if [ "$current_index" -eq $page_list_count ] 
                then
                    if [ "$checkbox_page_select_all" = true ] 
                    then
                        checkbox_page_selected+=("true")
                        inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[page_list_count]}\n"
                    else
                        checkbox_page_selected+=("false")
                        inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[page_list_count]}\n"
                    fi
                else
                    if [ "$checkbox_page_select_all" = true ] 
                    then
                        checkbox_page_selected+=("true")
                        inquirer:print " ${green}${checked}${normal} ${page_list[page_list_count]}\n"
                    else
                        checkbox_page_selected+=("false")
                        inquirer:print " ${unchecked} ${page_list[page_list_count]}\n"
                    fi
                fi

                page_list_count=$((page_list_count+1))

                tput cuu $((page_list_count-current_index))

                input_page_num=""
            fi
            return
        fi

        for i in "${!checkbox_list[@]}"
        do
            if [ "${checkbox_selected[i]}" = true ] 
            then
                checkbox_selected_indices+=("$i")
                checkbox_selected_options+=("${checkbox_list[i]}")
            fi
        done

        tput cub "$(tput cols)"

        if [ -z "${checkbox_selected_indices:-}" ] 
        then
            tput sc
            failed_count=$((failed_count+1))
            tput cuu $((current_index+1))
            tput cuf $((prompt_width+3))
            inquirer:print "${bg_black}${red}${checkbox_input_failed_msg}${normal}"
            tput rc
        else
            tput cud $((page_list_count-current_index))

            for i in $(seq $((page_list_count+1)))
            do
                tput el
                tput cuu1
            done

            tput cuf $((prompt_width+3))
            inquirer:print "${bg_black}${cyan}$(inquirer:join checkbox_selected_options)${normal}\n"

            break_keypress=true
        fi
    }

    inquirer:on_checkbox_input_space() {
        if [ "$input_search" = true ] 
        then
            inquirer:on_text_input_ascii
            return
        fi

        local i

        inquirer:remove_instructions
        tput cub "$(tput cols)"
        tput el

        if [ "$current_index" -eq $((page_list_count-1)) ] 
        then
            if [ "${checkbox_page_selected[current_index]}" = true ]
            then
                tput cuu $current_index
                for i in "${!page_list[@]}"
                do
                    if [ "$i" -eq "$current_index" ]
                    then
                        inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[i]}"
                    else
                        inquirer:print " ${unchecked} ${page_list[i]}\n"
                        checkbox_selected[i+pages_index*list_perpage]=false
                    fi
                    checkbox_page_selected[i]=false
                done
            else
                tput cuu $current_index
                for i in "${!page_list[@]}"
                do
                    if [ "$i" -eq "$current_index" ]
                    then
                        inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[i]}"
                    else
                        inquirer:print " ${green}${checked}${normal} ${page_list[i]}\n"
                        checkbox_selected[i+pages_index*list_perpage]=true
                    fi
                    checkbox_page_selected[i]=true
                done
            fi
        else
            if [ "${checkbox_page_selected[current_index]}" = true ]
            then
                checkbox_page_selected[current_index]=false
                checkbox_selected[current_index+pages_index*list_perpage]=false
                inquirer:print "${cyan}${arrow}${normal}${unchecked} ${page_list[current_index]}"
            else
                checkbox_page_selected[current_index]=true
                checkbox_selected[current_index+pages_index*list_perpage]=true
                inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${page_list[current_index]}"
            fi
        fi
    }

    inquirer:on_checkbox_input_ascii() {
        local key=$1

        if [ "$input_search" = false ] 
        then
            case "$key" in
                "w" ) 
                    inquirer:on_checkbox_input_up
                    return
                ;;
                "s" ) 
                    inquirer:on_checkbox_input_down
                    return
                ;;
                "a" ) 
                    inquirer:on_checkbox_input_left
                    return
                ;;
                "d" ) 
                    inquirer:on_checkbox_input_right
                    return
                ;;
            esac
            if [ "$key" == "/" ]
            then
                if [ "$pages_count" -eq 1 ] 
                then
                    return
                fi

                input_search=true
                text_input=""
                current_pos=0

                tput cub "$(tput cols)"
                tput cud $((list_perpage-current_index+1))

                for((i=0;i<=list_perpage;i++));
                do
                    tput el
                    tput cuu1
                done

                tput el
                tput cud1

                inquirer:print "${green}?${normal} ${bold}${bg_black}${white}输入搜索内容${bold} ${dim}( $arrow_up 返回)${normal}\n"

                stty -echo
                tput cnorm
            elif [[ "$key" =~ [0-9Pp] ]]
            then
                inquirer:on_input_page "$key"
            fi
            return
        fi

        inquirer:on_text_input_ascii "$key"
    }

    inquirer:on_checkbox_input_not_ascii() {
        if [ "$input_search" = false ] 
        then
            return
        fi

        inquirer:on_text_input_not_ascii "$1"
    }

    inquirer:on_checkbox_input_backspace() {
        if [ "$input_search" = false ] 
        then
            return
        fi

        inquirer:on_text_input_backspace
    }

    inquirer:_checkbox_input() {
        local i var=("$2"[@])
        list_perpage=${4:-$list_perpage}
        checkbox_list=("${!var}")
        list_count=${#checkbox_list[@]}

        if [ "$list_count" -eq 1 ] 
        then
            checkbox_selected_options=("${checkbox_list[@]}")
            checkbox_selected_indices=(0)

            inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${bg_black}${cyan}$(inquirer:join checkbox_selected_options)${normal}\n"
            return
        fi

        checkbox_selected=()
        checkbox_selected_indices=()
        checkbox_selected_options=()
        checkbox_input_failed_msg=$(gettext "选择不能为空")
        current_index=0
        failed_count=0
        first_keystroke=true

        trap inquirer:control_c EXIT

        stty -echo
        tput civis

        if [ "$list_perpage" -gt 0 ] && [ "$list_count" -gt "$list_perpage" ] 
        then
            pages_count=$((list_count/list_perpage))
            if [[ $((list_perpage*pages_count)) -lt "$list_count" ]] 
            then
                pages_count=$((pages_count+1))
            fi
            pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal} "
        fi

        inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${pages_tip:-}${dim}`gettext \"(按 <space> 选择, <enter> 确认)\"`${normal}\n"

        for i in "${!checkbox_list[@]}"
        do
            checkbox_selected[i]=false
        done

        var=("$3"[@])
        if [[ -n ${!var:-} ]] 
        then
            checkbox_selected_indices=("${!var}")
            for i in "${checkbox_selected_indices[@]}"
            do
                checkbox_selected[i]=true
            done
            checkbox_selected_indices=()
        fi

        for i in "${!checkbox_list[@]}"
        do
            if [ "$i" = 0 ]
            then
                if [ "${checkbox_selected[i]}" = true ]
                then
                    inquirer:print "${cyan}${arrow}${green}${checked}${normal} ${checkbox_list[i]}\n"
                else
                    inquirer:print "${cyan}${arrow}${normal}${unchecked} ${checkbox_list[i]}\n"
                fi
            elif [ "$pages_count" -gt 1 ] && [ "$i" = "$list_perpage" ] 
            then
                break
            else
                if [ "${checkbox_selected[i]}" = true ]
                then
                    inquirer:print " ${green}${checked}${normal} ${checkbox_list[i]}\n"
                else
                    inquirer:print " ${unchecked} ${checkbox_list[i]}\n"
                fi
            fi
            page_list_count=$((page_list_count+1))
            page_list+=("${checkbox_list[i]}")
        done

        for((i=0;i<page_list_count;i++));
        do
            if [ "${checkbox_selected[i]}" = true ] 
            then
                checkbox_page_selected+=("true")
            else
                checkbox_page_selected+=("false")
                checkbox_page_select_all=false
            fi
        done

        page_list+=("$(gettext 全选)")
        page_list_count=$((page_list_count+1))

        if [ "$checkbox_page_select_all" = true ] 
        then
            checkbox_page_selected+=("true")
            inquirer:print " ${green}${checked}${normal} ${page_list[page_list_count-1]}\n"
        else
            checkbox_page_selected+=("false")
            inquirer:print " ${unchecked} ${page_list[page_list_count-1]}\n"
        fi

        tput cuu $page_list_count

        inquirer:on_keypress inquirer:on_checkbox_input_up inquirer:on_checkbox_input_down inquirer:on_checkbox_input_space inquirer:on_checkbox_input_enter inquirer:on_checkbox_input_left inquirer:on_checkbox_input_right inquirer:on_checkbox_input_ascii inquirer:on_checkbox_input_backspace inquirer:on_checkbox_input_not_ascii
    }

    inquirer:checkbox_input() {
        var_name=$3

        inquirer:_checkbox_input "$1" "$2" "$var_name" "${4:-}"

        read -r -a ${var_name?} <<< "${checkbox_selected_options[@]}"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:checkbox_input_indices() {
        var_name=$3

        inquirer:_checkbox_input "$1" "$2" "$var_name" "${4:-}"

        read -r -a ${var_name?} <<< "${checkbox_selected_indices[@]}"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:on_sort_up() {
        if [ "${#sort_options[@]}" -eq 1 ]
        then
            return
        fi

        tput cub "$(tput cols)"

        inquirer:print "  ${sort_options[current_index]}"

        if [ $current_index = 0 ]
        then
            current_index=$((${#sort_options[@]}-1))
            tput cud $((${#sort_options[@]}-1))
        else
            current_index=$((current_index-1))
            tput cuu1
        fi

        tput cub "$(tput cols)"

        inquirer:print "${cyan}${arrow} ${sort_options[current_index]} ${normal}"
    }

    inquirer:on_sort_down() {
        if [ "${#sort_options[@]}" -eq 1 ]
        then
            return
        fi

        tput cub "$(tput cols)"

        inquirer:print "  ${sort_options[current_index]}"

        if [ $current_index = $((${#sort_options[@]}-1)) ]
        then
            current_index=0
            tput cuu $((${#sort_options[@]}-1))
        else
            current_index=$((current_index+1))
            tput cud1
        fi

        tput cub "$(tput cols)"

        inquirer:print "${cyan}${arrow} ${sort_options[current_index]} ${normal}"
    }

    inquirer:on_sort_move_up() {
        if [ "${#sort_options[@]}" -eq 1 ]
        then
            return
        fi

        local i

        tput cub "$(tput cols)"

        if [ $current_index = 0 ]
        then
            for((i=1;i<${#sort_options[@]};i++));
            do
                inquirer:print "  ${sort_options[i]}\n"
            done
            inquirer:print "${cyan}${arrow} ${sort_options[current_index]} ${normal}"
            current_index=$((${#sort_options[@]}-1))
            sort_options=( "${sort_options[@]:1}" "${sort_options[@]:0:1}" )
            sort_indices=( "${sort_indices[@]:1}" "${sort_indices[@]:0:1}" )
        else
            inquirer:print "  ${sort_options[current_index-1]}"
            tput cuu1
            tput cub "$(tput cols)"
            inquirer:print "${cyan}${arrow} ${sort_options[current_index]} ${normal}"
            local tmp="${sort_options[current_index]}"
            sort_options[current_index]="${sort_options[current_index-1]}"
            sort_options[current_index-1]="$tmp"
            tmp="${sort_indices[current_index]}"
            sort_indices[current_index]="${sort_indices[current_index-1]}"
            sort_indices[current_index-1]="$tmp"
            current_index=$((current_index-1))
        fi
    }

    inquirer:on_sort_move_down() {
        if [ "${#sort_options[@]}" -eq 1 ]
        then
            return
        fi

        local i

        tput cub "$(tput cols)"

        if [ $current_index = $((${#sort_options[@]}-1)) ]
        then
            tput cuu $((${#sort_options[@]}-1))
            inquirer:print "${cyan}${arrow} ${sort_options[current_index]} ${normal}\n"
            for((i=0;i<current_index;i++));
            do
                inquirer:print "  ${sort_options[i]}\n"
            done
            tput cuu ${#sort_options[@]}
            sort_options=( "${sort_options[@]:current_index}" "${sort_options[@]:0:current_index}" )
            sort_indices=( "${sort_indices[@]:current_index}" "${sort_indices[@]:0:current_index}" )
            current_index=0
        else
            inquirer:print "  ${sort_options[current_index+1]}"
            tput cud1
            tput cub "$(tput cols)"
            inquirer:print "${cyan}${arrow} ${sort_options[current_index]} ${normal}"
            local tmp="${sort_options[current_index]}"
            sort_options[current_index]="${sort_options[current_index+1]}"
            sort_options[current_index+1]="$tmp"
            tmp="${sort_indices[current_index]}"
            sort_indices[current_index]="${sort_indices[current_index+1]}"
            sort_indices[current_index+1]="$tmp"
            current_index=$((current_index+1))
        fi
    }

    inquirer:on_sort_ascii() {
        case "$1" in
            "w" ) inquirer:on_sort_move_up;;
            "s" ) inquirer:on_sort_move_down;;
        esac
    }

    inquirer:on_sort_enter_space() {
        local i

        tput cud $((${#sort_options[@]}-current_index))
        tput cub "$(tput cols)"

        for i in $(seq $((${#sort_options[@]}+1)))
        do
            tput el
            tput cuu1
        done

        tput cuf $((prompt_width+3))
        inquirer:print "${bg_black}${cyan}$(inquirer:join sort_options)${normal}\n"

        break_keypress=true
    }

    inquirer:_sort_input() {
        local i var=("$2"[@])
        sort_options=("${!var}")
        sort_indices=("${!sort_options[@]}")

        current_index=0

        trap inquirer:control_c EXIT

        stty -echo
        tput civis

        inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${dim}`gettext \"(上下箭头选择, 按 <w> <s> 上下移动)\"`${normal}\n"

        for i in "${!sort_options[@]}"
        do
            if [ $i = 0 ]
            then
                inquirer:print "${cyan}${arrow} ${sort_options[i]} ${normal}\n"
            else
                inquirer:print "  ${sort_options[i]}\n"
            fi
        done

        tput cuu ${#sort_options[@]}

        inquirer:on_keypress inquirer:on_sort_up inquirer:on_sort_down inquirer:on_sort_enter_space inquirer:on_sort_enter_space inquirer:on_default inquirer:on_default inquirer:on_sort_ascii
    }

    inquirer:sort_input() {
        var_name=$3

        inquirer:_sort_input "$1" "$2"

        read -r -a ${var_name?} <<< "${sort_options[@]}"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:sort_input_indices() {
        var_name=$3

        inquirer:_sort_input "$1" "$2"

        read -r -a ${var_name?} <<< "${sort_indices[@]}"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:on_list_input_up() {
        if [ "$input_search" = true ] 
        then
            tput cub "$(tput cols)"
            tput el
            tput cuu1
            tput el
            tput cuu1
            tput el

            stty -echo
            tput civis

            local i

            for((i=0;i<page_list_count;i++));
            do
                if [ "$i" = "$current_index" ] 
                then
                    inquirer:print "${cyan}${arrow} ${page_list[i]} ${normal}\n"
                else
                    inquirer:print "  ${page_list[i]}\n"
                fi
            done

            tput cuu $((page_list_count-current_index))

            input_search=false
            return
        fi

        inquirer:remove_instructions

        tput cub "$(tput cols)"

        inquirer:print "  ${page_list[current_index]}"

        if [ $current_index = 0 ]
        then
            current_index=$((page_list_count-1))
            tput cud $((page_list_count-1))
        else
            current_index=$((current_index-1))
            tput cuu1
        fi

        tput cub "$(tput cols)"

        inquirer:print "${cyan}${arrow} ${page_list[current_index]}${normal}"
    }

    inquirer:on_list_input_down() {
        if [ "$input_search" = true ] 
        then
            return
        fi

        inquirer:remove_instructions

        tput cub "$(tput cols)"

        inquirer:print "  ${page_list[current_index]}"

        if [ $current_index = $((page_list_count-1)) ]
        then
            current_index=0
            tput cuu $((page_list_count-1))
        else
            current_index=$((current_index+1))
            tput cud1
        fi

        tput cub "$(tput cols)"

        inquirer:print "${cyan}${arrow} ${page_list[current_index]} ${normal}"
    }

    inquirer:on_list_input_left() {
        if [ -z "${pages_tip:-}" ] 
        then
            return
        fi

        if [ "$input_search" = true ] 
        then
            inquirer:on_text_input_left
            return
        fi

        local i

        if [ "$pages_index" -eq 0 ] 
        then
            pages_index=$((pages_count-1))
            page_list_count=$((list_count-list_perpage*pages_index))
        else
            pages_index=$((pages_index-1))
            page_list_count=$list_perpage
        fi

        pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal}"

        inquirer:page_instructions
        tput cub "$(tput cols)"
        tput cud $((list_perpage-current_index))

        for((i=0;i<list_perpage;i++));
        do
            tput el
            tput cuu1
        done

        tput el

        if [ "$current_index" -ge "$page_list_count" ] 
        then
            current_index=$((page_list_count-1))
        fi

        page_list=()

        for((i=0;i<page_list_count;i++));
        do
            page_list+=("${list_options[i+list_perpage*pages_index]}")

            if [ "$i" = "$current_index" ] 
            then
                inquirer:print "${cyan}${arrow} ${page_list[i]} ${normal}\n"
            else
                inquirer:print "  ${page_list[i]}\n"
            fi
        done

        tput cuu $((page_list_count-current_index))
    }

    inquirer:on_list_input_right() {
        if [ -z "${pages_tip:-}" ] 
        then
            return
        fi

        if [ "$input_search" = true ] 
        then
            inquirer:on_text_input_right
            return
        fi

        local i

        if [ "$pages_index" -eq $((pages_count-1)) ] 
        then
            pages_index=0
            page_list_count=$list_perpage
        else
            pages_index=$((pages_index+1))
            if [ "$pages_index" -eq $((pages_count-1)) ] 
            then
                page_list_count=$((list_count-pages_index*list_perpage))
            else
                page_list_count=$list_perpage
            fi
        fi

        pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal}"

        inquirer:page_instructions
        tput cub "$(tput cols)"
        tput cud $((list_perpage-current_index))

        for((i=0;i<list_perpage;i++));
        do
            tput el
            tput cuu1
        done

        tput el

        if [ "$current_index" -ge "$page_list_count" ] 
        then
            current_index=$((page_list_count-1))
        fi

        page_list=()

        for((i=0;i<page_list_count;i++));
        do
            page_list+=("${list_options[i+list_perpage*pages_index]}")

            if [ "$i" = "$current_index" ] 
            then
                inquirer:print "${cyan}${arrow} ${page_list[i]} ${normal}\n"
            else
                inquirer:print "  ${page_list[i]}\n"
            fi
        done

        tput cuu $((page_list_count-current_index))
    }

    inquirer:on_list_input_space() {
        if [ "$input_search" = true ] 
        then
            inquirer:on_text_input_ascii
            return
        fi

        local i

        tput cud $((page_list_count-current_index))
        tput cub "$(tput cols)"

        for i in $(seq $((page_list_count+1)))
        do
            tput el
            tput cuu1
        done

        tput cuf $((prompt_width+3))
        inquirer:print "${bg_black}${cyan}${page_list[current_index]}${normal}\n"

        break_keypress=true
    }

    inquirer:on_list_input_enter() {
        local i

        if [ "$input_search" = true ] 
        then
            if [ -n "$text_input" ] 
            then
                tput cub "$(tput cols)"
                tput el
                tput cuu1
                tput el
                tput cuu1
                tput el
                tput cuu1
                tput el
                tput cud1

                local list_page

                for i in "${!list_options[@]}"
                do
                    if [[ "${list_options[i]}" =~ "$text_input" ]] 
                    then
                        list_page=$((i/list_perpage+1))
                        inquirer:print "${green}P${list_page}${normal} ${list_options[i]}\n"
                    fi
                done

                if [ -n "${list_page:-}" ] 
                then
                    tput cud1
                fi

                inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${pages_tip:-}${dim}`gettext \"(使用上下箭头选择)\"`${normal}\n\n\n"
            fi
            inquirer:on_list_input_up
            return
        fi

        if [ "$input_page" = true ] 
        then
            input_page=false
            if [ -n "${input_page_num:-}" ] 
            then
                if [ "$input_page_num" -gt "$pages_count" ] || [ "$input_page_num" -eq $((pages_index+1)) ]
                then
                    input_page_num=""
                    return
                fi

                pages_index=$((input_page_num-1))

                pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal}"

                if [ "$input_page_num" -eq "$pages_count" ] 
                then
                    page_list_count=$((list_count-pages_index*list_perpage))
                else
                    page_list_count=$list_perpage
                fi

                inquirer:page_instructions
                tput cub "$(tput cols)"
                tput cud $((list_perpage-current_index+1))

                for((i=0;i<=list_perpage;i++));
                do
                    tput el
                    tput cuu1
                done

                tput el

                if [ "$current_index" -ge "$page_list_count" ] 
                then
                    current_index=$((page_list_count-1))
                fi

                page_list=()

                for((i=0;i<page_list_count;i++));
                do
                    page_list+=("${list_options[i+list_perpage*pages_index]}")

                    if [ "$i" = "$current_index" ] 
                    then
                        inquirer:print "${cyan}${arrow} ${page_list[i]} ${normal}\n"
                    else
                        inquirer:print "  ${page_list[i]}\n"
                    fi
                done

                tput cuu $((page_list_count-current_index))

                input_page_num=""
            fi
            return
        fi

        tput cud $((page_list_count-current_index))
        tput cub "$(tput cols)"

        for i in $(seq $((page_list_count+1)))
        do
            tput el
            tput cuu1
        done

        tput cuf $((prompt_width+3))
        inquirer:print "${bg_black}${cyan}${page_list[current_index]}${normal}\n"

        break_keypress=true
    }

    inquirer:on_list_input_ascii() {
        local key=$1

        if [ "$input_search" = false ] 
        then
            case "$key" in
                "w" ) 
                    inquirer:on_list_input_up
                    return
                ;;
                "s" ) 
                    inquirer:on_list_input_down
                    return
                ;;
                "a" ) 
                    inquirer:on_list_input_left
                    return
                ;;
                "d" ) 
                    inquirer:on_list_input_right
                    return
                ;;
            esac
            if [ "$key" == "/" ]
            then
                if [ "$pages_count" -eq 1 ] 
                then
                    return
                fi

                input_search=true
                text_input=""
                current_pos=0

                tput cub "$(tput cols)"
                tput cud $((list_perpage-current_index+1))

                for((i=0;i<=list_perpage;i++));
                do
                    tput el
                    tput cuu1
                done

                tput el
                tput cud1

                inquirer:print "${green}?${normal} ${bold}${bg_black}${white}输入搜索内容${bold} ${dim}( $arrow_up 返回)${normal}\n"

                stty -echo
                tput cnorm
            elif [[ "$key" =~ [0-9Pp] ]]
            then
                inquirer:on_input_page "$key"
            fi
            return
        fi

        inquirer:on_text_input_ascii "$key"
    }

    inquirer:on_list_input_not_ascii() {
        if [ "$input_search" = false ] 
        then
            return
        fi

        inquirer:on_text_input_not_ascii "$1"
    }

    inquirer:on_list_input_backspace() {
        if [ "$input_search" = false ] 
        then
            return
        fi

        inquirer:on_text_input_backspace
    }

    inquirer:_list_input() {
        local i var=("$2"[@])
        list_perpage=${3:-$list_perpage}
        list_options=("${!var}")
        list_count=${#list_options[@]}
        current_index=0

        if [ "$list_count" -eq 1 ] 
        then
            inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${bg_black}${cyan}${list_options[current_index]}${normal}\n"
            page_list=("${list_options[@]}")
            return
        fi

        first_keystroke=true

        trap inquirer:control_c EXIT

        stty -echo
        tput civis

        if [ "$list_perpage" -gt 0 ] && [ "$list_count" -gt "$list_perpage" ] 
        then
            pages_count=$((list_count/list_perpage))
            if [[ $((list_perpage*pages_count)) -lt "$list_count" ]] 
            then
                pages_count=$((pages_count+1))
            fi
            pages_tip="${dim}$pages_arrows $((pages_index+1))/$pages_count `gettext \"页\"`${normal} "
        fi

        inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${pages_tip:-}${dim}`gettext \"(使用上下箭头选择)\"`${normal}\n"

        for i in "${!list_options[@]}"
        do
            if [ $i = 0 ]
            then
                inquirer:print "${cyan}${arrow} ${list_options[i]} ${normal}\n"
            elif [ "$pages_count" -gt 1 ] && [ "$i" = "$list_perpage" ] 
            then
                break
            else
                inquirer:print "  ${list_options[i]}\n"
            fi
            page_list_count=$((page_list_count+1))
            page_list+=("${list_options[i]}")
        done

        tput cuu $page_list_count

        inquirer:on_keypress inquirer:on_list_input_up inquirer:on_list_input_down inquirer:on_list_input_space inquirer:on_list_input_enter inquirer:on_list_input_left inquirer:on_list_input_right inquirer:on_list_input_ascii inquirer:on_list_input_backspace inquirer:on_list_input_not_ascii
    }

    inquirer:list_input() {
        var_name=$3

        inquirer:_list_input "$1" "$2" ${4:-$list_perpage}

        read -r ${var_name?} <<< "${page_list[current_index]}"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:list_input_index() {
        var_name=$3

        inquirer:_list_input "$1" "$2" ${4:-$list_perpage}

        read -r ${var_name?} <<< "$((list_perpage*pages_index+current_index))"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:on_text_input_left() {
        if [[ $current_pos -gt 0 ]]
        then
            local current=${text_input:$current_pos:1} current_width
            current_width=$(inquirer:display_length "$current")

            tput cub $current_width
            current_pos=$((current_pos-1))
        fi
    }

    inquirer:on_text_input_right() {
        if [[ $((current_pos+1)) -eq ${#text_input} ]] 
        then
            tput cuf1
            current_pos=$((current_pos+1))
        elif [[ $current_pos -lt ${#text_input} ]]
        then
            local next=${text_input:$((current_pos+1)):1} next_width
            next_width=$(inquirer:display_length "$next")

            tput cuf $next_width
            current_pos=$((current_pos+1))
        fi
    }

    inquirer:on_text_input_enter() {
        local validate_failed_msg
        text_input=${text_input:-$text_default}

        tput civis
        tput cub "$(tput cols)"
        tput el

        if validate_failed_msg=$($text_input_validator "$text_input")
        then
            tput sc
            tput cuu $((1+failed_count*3))
            tput cuf $((prompt_width+3))
            inquirer:print "${bg_black}${cyan}"
            inquirer:print_input "${text_input}"
            inquirer:print "${normal}"
            tput rc
            break_keypress=true
        else
            failed_count=$((failed_count+1))
            tput cud1
            inquirer:print "${bg_black}${red}${validate_failed_msg:-$text_input_validate_failed_msg}${normal}\n"
            tput cud1
            if [ "$text_input" == "$text_default" ] 
            then
                text_input=""
                current_pos=0
            else
                inquirer:print_input "${text_input}"
                tput cub "$(tput cols)"
                tput cuf "$current_pos"
            fi
        fi

        tput cnorm
    }

    inquirer:on_text_input_ascii() {
        local c=${1:- }
        local rest=${text_input:$current_pos} rest_width
        local current=${text_input:$current_pos:1} current_width

        rest_width=$(inquirer:display_length "$rest")
        current_width=$(inquirer:display_length "$current")
        text_input="${text_input:0:$current_pos}$c$rest"
        current_pos=$((current_pos+1))

        tput civis

        [[ $current_width -gt 1 ]] && tput cub $((current_width-1))

        inquirer:print_input "$c$rest"

        if [[ $rest_width -gt 0 ]]
        then
            tput cub $((rest_width-current_width+1))
        fi

        tput cnorm
    }

    inquirer:on_text_input_not_ascii() {
        local c=$1
        local rest="${text_input:$current_pos}" rest_width
        local current=${text_input:$current_pos:1} current_width

        rest_width=$(inquirer:display_length "$rest")
        current_width=$(inquirer:display_length "$current")
        text_input="${text_input:0:$current_pos}$c$rest"
        current_pos=$((current_pos+1))

        tput civis

        [[ $current_width -gt 1 ]] && tput cub $((current_width-1))

        inquirer:print_input "$c$rest"

        if [[ $rest_width -gt 0 ]]
        then
            tput cub $((rest_width-current_width+1))
        fi

        tput cnorm
    }

    inquirer:on_text_input_backspace() {
        if [ $current_pos -gt 0 ] || { [ $current_pos -eq 0 ] && [ "${#text_input}" -gt 0 ]; }
        then
            local start rest rest_width del del_width next next_width offset
            local current=${text_input:$current_pos:1} current_width
            current_width=$(inquirer:display_length "$current")

            tput civis
            if [ $current_pos -eq 0 ] 
            then
                rest=${text_input:$((current_pos+1))}
                next=${text_input:$((current_pos+1)):1}
                rest_width=$(inquirer:display_length "$rest")
                next_width=$(inquirer:display_length "$next")
                offset=$((current_width-1))
                [[ $offset -gt 0 ]] && tput cub $offset
                inquirer:print_input "$rest"
                offset=$((rest_width-next_width+1))
                [[ $offset -gt 0 ]] && tput cub $offset
                text_input="$rest"
            else
                rest=${text_input:$current_pos}
                start=${text_input:0:$((current_pos-1))}
                del=${text_input:$((current_pos-1)):1}
                rest_width=$(inquirer:display_length "$rest")
                del_width=$(inquirer:display_length "$del")
                current_pos=$((current_pos-1))
                if [[ $current_width -gt 1 ]] 
                then
                    tput cub $((del_width+current_width-1))
                    inquirer:print_input "$rest"
                    tput cub $((rest_width-current_width+1))
                else
                    tput cub $del_width
                    inquirer:print_input "$rest"
                    [[ $rest_width -gt 0 ]] && tput cub $((rest_width-current_width+1))
                fi
                text_input="$start$rest"
            fi
            tput cnorm
        fi
    }

    inquirer:text_input_default_validator() {
        return
    }

    inquirer:text_input() {
        var_name=$2
        text_default=${3:-}
        text_input=""
        current_pos=0
        failed_count=0
        local text_default_tip

        if [ -n "$text_default" ] 
        then
            text_default_tip=" ${bold}${dim}($text_default)${normal}"
        else
            text_default_tip="${normal}"
        fi

        text_input_validator=${4:-inquirer:text_input_default_validator}
        text_input_validate_failed_msg=${5:-$(gettext "输入验证错误")}

        inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt}${text_default_tip}\n"

        trap inquirer:control_c EXIT

        #stty -echo
        #tput cnorm

        read -e text_input
        #inquirer:on_keypress inquirer:on_default inquirer:on_default inquirer:on_text_input_ascii inquirer:on_text_input_enter inquirer:on_text_input_left inquirer:on_text_input_right inquirer:on_text_input_ascii inquirer:on_text_input_backspace inquirer:on_text_input_not_ascii
        read -r ${var_name?} <<< "${text_input:-$text_default}"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:date_pick_default_validator() {
        if ! date +%s -d "$1" > /dev/null 2>&1
        then
            return 1
        fi
        return
    }

    inquirer:remove_date_instructions() {
        if [ "$first_keystroke" = true ]
        then
            tput sc
            tput civis
            tput cuu 1
            tput cub "$(tput cols)"
            tput cuf $((prompt_width+3))
            tput el
            tput rc
            tput cnorm
            first_keystroke=false
        fi
    }

    inquirer:on_date_pick_ascii() {
        case "$1" in
            "w" ) inquirer:on_date_pick_up;;
            "s" ) inquirer:on_date_pick_down;;
            "a" ) inquirer:on_date_pick_left;;
            "d" ) inquirer:on_date_pick_right;;
        esac
    }

    inquirer:on_date_pick_up() {
        inquirer:remove_date_instructions
        case $current_pos in
            3)  date_pick="$((${date_pick:0:4}+1))${date_pick:4}"
            ;;
            6) 
                local month=$((10#${date_pick:5:2}+1))
                [ "$month" -eq 13 ] && month=1
                date_pick="${date_pick:0:5}$(printf %02d "$month")${date_pick:7}"
            ;;
            9) 
                local day=$((10#${date_pick:8:2}+1))
                [ "$day" -eq 32 ] && day=1
                date_pick="${date_pick:0:8}$(printf %02d "$day")${date_pick:10}"
            ;;
            12) 
                local hour=$(((10#${date_pick:11:2}+1)%24))
                date_pick="${date_pick:0:11}$(printf %02d "$hour")${date_pick:13}"
            ;;
            15) 
                local min=$(((10#${date_pick:14:2}+1)%60))
                date_pick="${date_pick:0:14}$(printf %02d "$min")${date_pick:16}"
            ;;
            18) 
                local sec=$(((10#${date_pick:17:2}+1)%60))
                date_pick="${date_pick:0:17}$(printf %02d "$sec")${date_pick:19}"
            ;;
        esac

        tput sc
        tput civis
        tput cub $current_pos
        inquirer:print "$date_pick"
        tput rc
        tput cnorm
    }

    inquirer:on_date_pick_down() {
        inquirer:remove_date_instructions
        case $current_pos in
            3)  
                local year=$((${date_pick:0:4}-1))
                [ "$year" -eq 2020 ] && return
                date_pick="$year${date_pick:4}"
            ;;
            6) 
                local month=$((10#${date_pick:5:2}-1))
                [ "$month" -eq 0 ] && month=12
                date_pick="${date_pick:0:5}$(printf %02d "$month")${date_pick:7}"
            ;;
            9) 
                local day=$((10#${date_pick:8:2}-1))
                [ "$day" -eq 0 ] && day=31
                date_pick="${date_pick:0:8}$(printf %02d "$day")${date_pick:10}"
            ;;
            12) 
                local hour=$(((10#${date_pick:11:2}+23)%24))
                date_pick="${date_pick:0:11}$(printf %02d "$hour")${date_pick:13}"
            ;;
            15) 
                local min=$(((10#${date_pick:14:2}+59)%60))
                date_pick="${date_pick:0:14}$(printf %02d "$min")${date_pick:16}"
            ;;
            18) 
                local sec=$(((10#${date_pick:17:2}+59)%60))
                date_pick="${date_pick:0:17}$(printf %02d "$sec")${date_pick:19}"
            ;;
        esac

        tput sc
        tput civis
        tput cub $current_pos
        inquirer:print "$date_pick"
        tput rc
        tput cnorm
    }

    inquirer:on_date_pick_left() {
        inquirer:remove_date_instructions
        if [[ $current_pos -gt 3 ]] 
        then
            tput cub 3
            current_pos=$((current_pos-3))
        fi
    }

    inquirer:on_date_pick_right() {
        inquirer:remove_date_instructions
        if [[ $current_pos -lt 18 ]] 
        then
            tput cuf 3
            current_pos=$((current_pos+3))
        fi
    }

    inquirer:on_date_pick_enter_space() {
        tput civis
        tput cub $current_pos
        tput el

        if $date_pick_validator "$date_pick"
        then
            tput sc
            tput cuu $((1+failed_count*3))
            tput cuf $((prompt_width+3))
            inquirer:print "${bg_black}${cyan}${date_pick}${normal}"
            tput rc
            break_keypress=true
        else
            failed_count=$((failed_count+1))
            tput cud1
            inquirer:print "${bg_black}${red}${date_pick_validate_failed_msg}${normal}\n"
            tput cud1
            inquirer:print "${date_pick}"
            tput cub $((19-current_pos))
        fi

        tput cnorm
    }

    inquirer:date_pick() {
        var_name=$2
        date_pick_validator=${3:-inquirer:date_pick_default_validator}
        date_pick_validate_failed_msg=${4:-$(gettext "时间验证错误")}
        date_pick=$(printf '%(%Y-%m-%d %H:%M:%S)T' "${!var_name:--1}")
        current_pos=12
        failed_count=0
        first_keystroke=true

        inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${dim}`gettext \"(使用箭头选择)\"`${normal}\n"
        inquirer:print "$date_pick"
        tput cub 7

        trap inquirer:control_c EXIT

        stty -echo
        tput cnorm

        inquirer:on_keypress inquirer:on_date_pick_up inquirer:on_date_pick_down inquirer:on_date_pick_enter_space inquirer:on_date_pick_enter_space inquirer:on_date_pick_left inquirer:on_date_pick_right inquirer:on_date_pick_ascii
        read -r ${var_name?} <<< $(date +%s -d "$date_pick")

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:remove_color_instructions() {
        if [ "$first_keystroke" = true ]
        then
            tput cuu 1
            tput cub "$(tput cols)"
            tput cuf $((prompt_width+3))
            tput el
            tput cud 1
            first_keystroke=false
        fi
    }

    inquirer:on_color_pick_ascii() {
        case "$1" in
            "w" ) inquirer:on_color_pick_up;;
            "s" ) inquirer:on_color_pick_down;;
            "a" ) inquirer:on_color_pick_left;;
            "d" ) inquirer:on_color_pick_right;;
        esac
    }

    inquirer:on_color_pick_up() {
        inquirer:remove_color_instructions
        tput cub "$(tput cols)"
        colors_index=$(((colors_index+1)%16))
        inquirer:print "${bg_colors[bg_colors_index]}${colors[colors_index]}$text_default${normal}"
    }

    inquirer:on_color_pick_down() {
        inquirer:remove_color_instructions
        tput cub "$(tput cols)"
        colors_index=$(((colors_index-1)%16))
        inquirer:print "${bg_colors[bg_colors_index]}${colors[colors_index]}$text_default${normal}"
    }

    inquirer:on_color_pick_left() {
        inquirer:remove_color_instructions
        tput cub "$(tput cols)"
        bg_colors_index=$(((bg_colors_index-1)%17))
        inquirer:print "${bg_colors[bg_colors_index]}${colors[colors_index]}$text_default${normal}"
    }

    inquirer:on_color_pick_right() {
        inquirer:remove_color_instructions
        tput cub "$(tput cols)"
        bg_colors_index=$(((bg_colors_index+1)%17))
        inquirer:print "${bg_colors[bg_colors_index]}${colors[colors_index]}$text_default${normal}"
    }

    inquirer:on_color_pick_enter_space() {
        tput cub "$(tput cols)"
        tput el
        tput sc
        tput cuu 1
        tput cuf $((prompt_width+3))
        inquirer:print "${bg_colors[bg_colors_index]}${colors[colors_index]}$text_default${normal}"
        tput rc
        break_keypress=true

        tput cnorm
    }

    inquirer:color_pick() {
        var_name=$2
        text_default="${3:-$(gettext "示例文字 ABC 123")}"
        colors=( '\033[30m' '\033[31m' '\033[32m' '\033[33m' '\033[34m' '\033[35m' '\033[36m' '\033[37m' 
            '\033[90m' '\033[91m' '\033[92m' '\033[93m' '\033[94m' '\033[95m' '\033[96m' '\033[97m' )
        bg_colors=( '' '\033[40m' '\033[41m' '\033[42m' '\033[43m' '\033[44m' '\033[45m' '\033[46m' '\033[47m' 
            '\033[100m' '\033[101m' '\033[102m' '\033[103m' '\033[104m' '\033[105m' '\033[106m' '\033[107m' )
        colors_index=7
        bg_colors_index=0
        first_keystroke=true

        inquirer:print "${green}?${normal} ${bold}${bg_black}${white}${prompt} ${dim}`gettext \"(上下/左右 箭头选择 文字/背景颜色)\"`${normal}\n"
        inquirer:print "${colors[colors_index]}${bg_colors[bg_colors_index]}$text_default${normal}"

        trap inquirer:control_c EXIT

        tput civis

        inquirer:on_keypress inquirer:on_color_pick_up inquirer:on_color_pick_down inquirer:on_color_pick_enter_space inquirer:on_color_pick_enter_space inquirer:on_color_pick_left inquirer:on_color_pick_right inquirer:on_color_pick_ascii

        read -r ${var_name?} <<< "${colors[colors_index]}${bg_colors[bg_colors_index]}"

        inquirer:cleanup

        trap - EXIT
    }

    inquirer:display_length() {
        local display_length=0 char_read byte_len char_len char_i char
        local oLC_ALL=${LC_ALL:-} oLANG=${LANG:-}

        while IFS= read -rsn1 char
        do
            case "$char" in
                '')
                ;;
                *[$'\x80'-$'\xFF']*) 
                    char_read="${char_read:-}$char"
                    LC_ALL= LANG=C
                    byte_len=${#char_read}
                    LC_ALL=$oLC_ALL LANG=$oLANG

                    if [ "$byte_len" -ne "${#char_read}" ] 
                    then
                        if [[ $byte_len -le 2 ]] 
                        then
                            display_length=$((display_length+1))
                        elif [[ $byte_len -le 4 ]] 
                        then
                            display_length=$((display_length+2))
                        else
                            display_length=$((display_length+3))
                        fi
                        char_read=""
                    fi
                ;;
                *) 
                    display_length=$((display_length+1))
                ;;
            esac
        done <<< "${1:-}"

        echo "$display_length"
    }

    local option=$1 var_name \
    prompt=${2:-} \
    prompt_raw \
    prompt_width \
    break_keypress \
    first_keystroke \
    current_index \
    list_perpage=0 \
    list_count \
    page_list=() \
    page_list_count=0 \
    pages_arrows="\xe2\x9d\xae\xe2\x9d\xaf" \
    pages_tip \
    pages_index=0 \
    pages_count=1 \
    input_page=false \
    input_page_num \
    input_search=false \
    checkbox_list=() \
    checkbox_page_selected=() \
    checkbox_page_select_all=true \
    checkbox_selected=() \
    checkbox_selected_indices=() \
    checkbox_selected_options=() \
    checkbox_input_failed_msg \
    sort_options=() \
    sort_indices=() \
    list_options=() \
    current_pos \
    failed_count \
    text_default \
    text_input \
    text_input_validate_failed_msg \
    text_input_validator \
    date_pick \
    date_pick_validate_failed_msg \
    date_pick_validator \
    colors=() \
    bg_colors=() \
    colors_index \
    bg_colors_index \
    arrow arrow_up checked unchecked bold dim normal

    prompt_raw=$(printf '%b' "$prompt"|sed 's/\x1b\[[0-9;]*m//g')
    prompt_width=$(inquirer:display_length "$prompt_raw")

    arrow='\xe2\x9d\xaf'
    arrow_up='\xe2\x86\x91'
    checked='\xe2\x97\x89'
    unchecked='\xe2\x97\xaf'
    red=${red:-'\033[31m'}
    green=${green:-'\033[32m'}
    yellow=${yellow:-'\033[33m'}
    blue=${blue:-'\033[34m'}
    cyan=${cyan:-'\033[36m'}
    white=${white:-'\033[37m'}
    bg_black=${bg_black:-'\033[40m'}
    bold='\033[1m'
    dim='\033[2m'
    normal='\033[0m'

    shift
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
    echo "prefix=$HOME/ffmpeg_build
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: bzip2
Description: bzip2
Version: 1.0.6
Requires:
Libs: -L\${libdir} -lbz2
Cflags: -I\${includedir}
" > "$HOME/ffmpeg_build/lib/pkgconfig/bzip2.pc"

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
cat > "$HOME"/ffmpeg_build/lib/pkgconfig/libxml-2.0.pc <<EOF
prefix=$HOME/ffmpeg_build
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libxml2
Description: libxml2
Version: 2.9.10
Requires:
Libs: -L\${libdir} -lxml2
Cflags: -I\${includedir}
EOF

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
cat > "$HOME"/ffmpeg_build/lib/pkgconfig/rubberband.pc <<EOF
prefix=$HOME/ffmpeg_build
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: rubberband
Version: 1.9
Description:
Libs: -L\${libdir} -lrubberband
Cflags: -I\${includedir}
EOF

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
