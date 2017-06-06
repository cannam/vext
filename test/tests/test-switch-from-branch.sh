#!/bin/bash

. $(dirname "$0")/include.sh

libcontent_nobranch=$(cat <<EOF
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

libcontent_branch=$(cat <<EOF
"A": {
    "vcs": "hg",
    "service": "testfile",
    "branch": "b2"
},
"B": {
    "vcs": "git",
    "service": "testfile",
    "branch": "b2"
}
EOF
          )

prepare
write_project_file "$libcontent_branch"

"$vext" install
check_expected 1379d75f0b4f 7219cf6e6d4706295246d278a3821ea923e1dfe2

write_project_file "$libcontent_nobranch"

"$vext" install # obeys lock file, so should do nothing
check_expected 1379d75f0b4f 7219cf6e6d4706295246d278a3821ea923e1dfe2

# We are now on the wrong branch, and both status and review should be
# able to see that
assert_all_wrong status
assert_all_wrong review

"$vext" update
check_expected f94ae9d7e5c9 3199655c658ff337ce24f78c6d1f410f34f4c6f2

assert_all_present status
assert_all_correct review
