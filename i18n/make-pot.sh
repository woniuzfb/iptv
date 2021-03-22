#!/bin/bash

# ============================================
# Based on https://github.com/step-/i18n-table
# Depends: GNU gawk, gsed, xgettext
# ============================================

if [ "$(uname -s)" = "Darwin" ]
then
  GSED="gsed"
  if [ -z "$(which $GSED)" ]
  then
    brew install gnu-sed
  fi
  if [ -z "$(which gettext)" ]
  then
    brew install gettext
  fi
else
  GSED="sed"
  . /etc/os-release
  if [ -z "$(which gettext)" ]
  then
    echo "installing gettext..."
    if [ "$ID" == "centos" ] 
    then
      yum -y install gettext
    else
      apt-get -y install gettext
    fi
  fi
fi

if [ -z "$(which gettext)" ]
then
  echo "gettext not found!"
  exit 1
fi

PACKAGE_NAME=iptv.sh # iptv.sh, v2.sh, x.sh, nx.sh, or.sh, cf.sh, ibm.sh, arm.sh, pve.sh
PACKAGE_POT_LANGUAGE=$1 # en, zh_CN
PACKAGE_PO_LANGUAGE=$2 # ru, de ...

if [ "$1" == "b" ] && [ -e "po/$PACKAGE_NAME-en.po" ]
then
  awk '$1 == "msgstr" { s=$0; sub(/msgstr/, "msgid", s); print s; print "msgstr \"\""; next }
    $1 == "msgid" { next }
    1' "po/$PACKAGE_NAME-en.po" > "$PACKAGE_NAME.pot"
  exit 0
fi

if [ -z "$PACKAGE_PO_LANGUAGE" ] 
then
  echo >&2 "${0##*/}: error: one or more values not set or wrong.
usage: ${0##*/} [pot-language (en, zh_CN)] [po-language (ru, de ...)]"
  exit 1
fi

if [ "$PACKAGE_POT_LANGUAGE" != "en" ] && [ "$PACKAGE_POT_LANGUAGE" != "zh_CN" ] 
then
  echo "pot-language must be en or zh_CN"
  exit 1
fi

# Output file name
FPOT=$PACKAGE_NAME-$PACKAGE_POT_LANGUAGE.pot
FPO=$PACKAGE_NAME-$PACKAGE_PO_LANGUAGE.po
FMO=$PACKAGE_NAME-$PACKAGE_PO_LANGUAGE.mo

# Input encoding
IENC=UTF-8
# Output encoding
OENC=UTF-8

XSRC=../docs/$PACKAGE_NAME

PACKAGE_VERSION=$(grep 'sh_ver="' < $XSRC |awk -F "=" '{print $NF}'|$GSED 's/\"//g'|head -1)
PACKAGE_TITLE="Locale $PACKAGE_PO_LANGUAGE For $PACKAGE_NAME v$PACKAGE_VERSION - ONE Click Script"
PACKAGE_COPYRIGHT="BSD 3 Clause License"
PACKAGE_FIRST_POT_AUTHOR="MTimer https://github.com/woniuzfb/iptv"
PACKAGE_POT_CREATION_TZ="UTC"
PACKAGE_CHARSET="$OENC"
PACKAGE_POT_BUGS_ADDRESS="tg @woniuzfb"

if ! [ -e "$XSRC" ]
then
  echo >&2 "${0##*/}: error: file $XSRC not found."
  exit 1
fi

create_pot_file() # $1-pot-file $2...-xgettext-options
{
  local fpot=$1
  shift

  if ! scan_source_file "$XSRC" "$fpot" "$@"
  then
    echo >&2 "${0##*/}: ERRORS:scan_source_file '$XSRC'"
    exit 1
  fi
}

scan_source_file() # $1-filepath $2-potfile...-xgettext-options
{
  local f=$1 o=$2
  shift
  shift
  echo >&2 "scan_source_file $f"
  env TZ="$PACKAGE_POT_CREATION_TZ" \
    xgettext ${IENC:+--from-code=$IENC} -L Shell "$@" --no-wrap -o "$o"  \
      --package-name="$PACKAGE_NAME" \
      --package-version="$PACKAGE_VERSION" \
      --msgid-bugs-address="$PACKAGE_POT_BUGS_ADDRESS" "$f"
  $GSED -i '
  {
    s~SOME DESCRIPTIVE TITLE~'"$PACKAGE_TITLE"'~
    s~YEAR THE PACKAGE.*$~'"$PACKAGE_COPYRIGHT"'~
    s~FIRST AUTHOR.*$~'"$PACKAGE_FIRST_POT_AUTHOR"'~
    s~Language: ~&'"$PACKAGE_PO_LANGUAGE"'~
    s~=CHARSET~='"$PACKAGE_CHARSET"'~
  }' "$o"
}

if [ -e "po/$FPO" ] && [ -e "$FPOT" ]
then
  po_new=$(awk 'NR==FNR{ if($1 == "msgid") {arr[FNR]= $0};next}{ if($1 == "msgid") {$0=arr[FNR]}; print $0}' "$FPOT" "po/$FPO")
  echo "$po_new" > "po/$FPO"
fi

create_pot_file "$PACKAGE_NAME-en.pot"
create_pot_file "$PACKAGE_NAME-zh_CN.pot"

mkdir -p "po"

if [ "$PACKAGE_POT_LANGUAGE" == "en" ] 
then
  msgmerge --update --backup=none --no-wrap "$FPOT" "$PACKAGE_NAME.pot"
fi

if ! [ -e "po/$FPO" ]
then
  cp -f "$FPOT" "po/$FPO"
else
  msgmerge --update -N --backup=none --no-wrap "po/$FPO" "$FPOT"
fi

if [ "$PACKAGE_POT_LANGUAGE" == "zh_CN" ] 
then
  msgfmt -o "po/$FMO" "po/$FPO"
fi

