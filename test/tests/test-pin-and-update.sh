#!/bin/bash

. $(dirname "$0")/include.sh

libcontent_pinned=$(cat <<EOF
"A": {
    "vcs": "hg",
    "service": "testfile",
    "pin": "1379d75"
},
"B": {
    "vcs": "git",
    "service": "testfile",
    "pin": "7219cf6e6"
}
EOF
          )

libcontent_unpinned=$(cat <<EOF
"A": {
    "vcs": "hg",
    "service": "testfile"
},
"B": {
    "vcs": "git",
    "service": "testfile"
}
EOF
          )

prepare
write_project_file "$libcontent_unpinned"

"$vext" install
check_expected f94ae9d7e5c9 3199655c658ff337ce24f78c6d1f410f34f4c6f2

write_project_file "$libcontent_pinned"

"$vext" install # obeys lock file, so should do nothing
check_expected f94ae9d7e5c9 3199655c658ff337ce24f78c6d1f410f34f4c6f2

assert_all_wrong status
assert_all_wrong review

"$vext" update
check_expected 1379d75f0b4f 7219cf6e6d4706295246d278a3821ea923e1dfe2

assert_all_present status
assert_all_correct review