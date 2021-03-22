# Translating

``` bash
git clone https://github.com/woniuzfb/iptv.git
cd iptv/i18n

- DO NOT edit/remove iptv.sh.pot # if you are a native English speaker and want to help (see bottom)

./make-pot.sh [pot-language (en, zh_CN)] [po-language (ru, de ...)]

e.g.
./make-pot.sh en ru # translating English to ru
./make-pot.sh zh_CN ru # if you prefer translating Chinese to ru

using the editor of your choice:
poedit po/iptv.sh-ru.po # iptv.sh-ru.po under directory po

./make-pot.sh zh_CN ru # run this when you are done

PR po/iptv.sh-ru.po
```

## PR iptv.sh.pot

- if you are a native English speaker

``` bash
using the editor of your choice:
poedit iptv.sh.pot # EDIT msgid only

PR iptv.sh.pot
```
