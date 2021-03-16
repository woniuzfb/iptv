# --- Translation table i18n ----------------------------------------------{{{1

# Notes for translators
# ---------------------
# To create a pot file for this script use xgettext.sh[1] instead of xgettext.
# xgettext.sh augments xgettext with the ability to extract MSGIDs from calls
# to 'gettext -es'.
# [1] https://github.com/step-/i18n-table
#
# A. Never use \n **inside** your MSGSTR. For yad and gtkdialog replace \n with \r.
# B. However, always **end** your MSGSTR with \n.
# C. Replace trailing spaces (U+0020) with no-break spaces (U+00A0).

i18n_table() {
    {
# PART GLOBAL
read i18n_usage
read i18n_change_update_language
read i18n_info
read i18n_error
read i18n_tip
	} << EOF
$(gettext -es -- \
"Usage\n" \
"change/update language\n" \
"Info\n" \
"Error\n" \
"Tip\n" \
)
EOF
}