#!/bin/bash
# git-etc-commit 0.4
# Leho Kraav <leho@kraav.com>
# https://github.com/lkraav/git-etc-commit

COLUMNS=80 # replace with $(tput cols) for variable width
DIR="/etc"
IGNORE="$DIR/.gitignore"
GECIGNORE="$DIR/.gecignore"
MULTIEDIT="-p"
PAGER=""
SEP="-"
SEPARATOR=""

usage() {
    echo "Usage: ${0##*/} [<filename> ...]"
}

die() {
    echo "$@"
    exit 1
}

pause() {
    [ -n "$@" ] && echo -n -e "- Press ENTER to $(color red)$1$(color off), "
    read -p "CTRL-C to quit"
}

gitlog() {
    local WH=7                 # hash
    local WM=$(fieldwidth 0.6) # message
    local WT=$(fieldwidth 0.2) # time
    local WA=$(fieldwidth 0.1) # author
    # log format source: https://twitter.com/#!/lkraav/status/72605873616322560
    git --no-pager log --pretty=tformat:'%h|%d%s|(%cr)|<%an>' \
        --abbrev-commit --date=relative "$@" |
        while IFS="|" read hash message time author; do
            # shell printf apparently doesn't truncate fields, we need to double with bash
            # extra space after \- so your terminal can copy hashes without ascii
            printf "  \- $(color red)%${WH}s$(color off) %-${WM}s $(color green)%${WT}s$(color off) $(color blue)%-${WA}s$(color off)\n" "${hash:0:$WH}" "${message:0:$WM}" "${time:0:$WT}" "${author:0:$WA}"
        done
}

fieldwidth() {
    printf -v FLOAT "%s" "$(bc <<< "$COLUMNS * $1")"
    echo ${FLOAT/\.*}
}

getstatus() {
    # git-status doesn't like absolute paths, make sure you give it relatives
    IFS=" " read STATUS TMP <<< $(git status -s "$1")
    [ -n "$STATUS" ] && echo "${STATUS:0:1}"
}

printlog() {
    local FILE="$1"; shift

    printf "%s $(color ltred)%s$(color off) %s\n" "$(gitlog $@ -- $FILE)"
}

[ $PWD != $DIR ] && die "Error: working directory is not $DIR, cannot continue"
[ -r .git ] || die "Error: unable to read .git, check directory exists or permissions"

while getopts "h" opt; do
    case $opt in
        h) usage; exit 0;;
        \?) usage; exit 1;;
    esac
done
shift $((OPTIND-1))

# Processing goes in two passes. First go through others, then modifieds.
for FILETYPE in others modified; do
    echo "Starting processing $FILETYPE..."

    # Should have a (x/X) counter here
    # Counting can be difficult when we actually make changes to the list inside loop
    LSFILES=$(git ls-files --$FILETYPE -X $IGNORE)
    COUNT=$(echo "$LSFILES" | wc -l)
    C=0
    IFS=$'\n'
    for FILE in $LSFILES; do
        [ -n "$FILE" ] || break
        let C++

        STATUS=$(getstatus "$FILE")
        if [ -z "$STATUS" ]; then
            echo -e "$(color ltblue)$FILE$(color off) has no change status, it was probably already processsed. Skipping..."
            continue
        fi

        if [ -f "$GECIGNORE" ]; then
            if [ -r "$GECIGNORE" ]; then
                if grep -qx "$FILE" "$GECIGNORE"; then
                    echo -e "Found $(color ltblue)$FILE$(color off) in $GECIGNORE. Skipping..."
                    continue
                fi
            else
                die "Error: unable to read $GECIGNORE, check file permissions"
            fi
        fi

        echo -e "\nLast 5 commits:"; gitlog -5; echo

        printf "($C/$COUNT) Processing $(color ltred)${STATUS:+"$STATUS" }$(color off)$(color ltblue)$FILE$(color off)"

        COMMIT=""
        MLIST="" # package-owned files with modifications
        P=$(qfile -qvC "$DIR/$FILE" | head -n 1)

        if [ -n "$P" ]; then
            IFS=" " read CATEGORY PN PV PR <<< $(qatom "$P")
            P="$CATEGORY/$PN-$PV${PR:+-$PR}"

            echo -e ", belongs to $(color blue)$P$(color off)\n"
            QLIST=$(qlist $P | grep ^$DIR) # all package-owned files in /etc

            EXISTS=""
            HAS_EXISTING="" # need this in case last file checked is not in the tree
            OPTYPE="emerge"

            OLDIFS=$IFS
            IFS=$'\n'

            # This also needs to respect .gitignore
            echo "Package contents (grep $DIR) and their status:"
            for PFILE in $QLIST; do
                # For each file we have to determine, whether this package
                #  already has files in the tree. In case this might
                #  be an upgrade, commit message should reflect that.
                # In case package has files in modified state, it can be:
                #  - uncommited configuration changes
                #  - version upgrades
                # git ls-files can throw errors here if $p is symlink pointing to
                #  outside the repository
                # git ls-files also returns target of symlink, not symlink
                PFILE=${PFILE#$DIR/}
                LOG=""
                EXISTS=$(git ls-files "$PFILE")
                STATUS=$(getstatus "$PFILE")
                
                if [ -n "$EXISTS" ]; then
                    HAS_EXISTING="yes"
                    LOG="$(printlog "$PFILE" -1)\n"
                else
                    # file cannot be ignored
                    [ "$STATUS" = "?" ] || continue
                fi
                MLIST+="$PFILE"$'\n'
                printf "$(color red)${STATUS:- }$(color off) ${PFILE#$DIR/}\n${LOG:-}"
            done

            if [ -n "$HAS_EXISTING" ]; then
                echo -e "\n$(color red)WARNING$(color off): existing files found in tree, this might be an upgrade"
            fi

            echo -e "\nMerge history:"
            qlop -lu "$CATEGORY/$PN-" | while read line; do echo "$line"; done
            echo

            [ "$FILETYPE" = "modified" -o -n "$HAS_EXISTING" ] && OPTYPE="upgrade ->"
            COMMIT="git commit -m \"$OPTYPE $(qlist -IUCv $P)\" -uno -q"
            echo "$ $COMMIT"
        else
            printf " - no owner found\n"
            printlog "$FILE" -1
        fi

        while true; do
            read -p "(A)mend,(C)ommit,(D)el,(E)dit,Di(f)(f),(I)gnore,(L)og,(P)atch,(R)evert,(S)kip,(T)ig,E(x)ec,(Q)uit: " OACTION
            OACTION="${FILETYPE:0:1}$OACTION" # m = modified, o = other
            case "${OACTION,,}" in
                [mo]a) # (A)mend
                    git add "$FILE"
                    git commit --amend
                    if [ $? != 0 ]; then
                        git reset -q HEAD
                        continue
                    fi
                    ;;
                mc) # (C)ommit
                    git commit "$FILE"
                    if [ $? != 0 ]; then
                        git reset -q HEAD
                        continue
                    fi
                    ;;
                oc) # (C)ommit
                    git add "$FILE"
                    git commit "$FILE"
                    if [ $? != 0 ]; then
                        git reset -q HEAD
                        continue
                    fi
                    ;;
                [mo]d) # (D)elete
                    rm -i "$FILE"
                    [ -e "$FILE" ] && continue
                    ;;
                [mo]e) # (E)dit
                    eval $EDITOR "$FILE"
                    continue
                    ;;
                [mo]ee) # (E)dit multiple
                    eval $EDITOR $MULTIEDIT $(echo "$QLIST")
                    continue
                    ;;
                [mo]f) # Di(f)f
                    git diff --no-color -- "$FILE"
                    continue
                    ;;
                [mo]ff) # Di(ff) multiple
                    git diff --no-color -- $(echo "$MLIST")
                    continue
                    ;;
                [mo]fs) # Di(f) stage
                    git diff --no-color --cached
                    continue
                    ;;
                oi) # (I)gnore
                    IGNOREFILE="echo \"$FILE\" >> \"$IGNORE\""
                    echo "...orphan, ignoring"
                    echo "$ $IGNOREFILE"
                    eval "$IGNOREFILE"
                    ;;
                [mo]ig) # (I)gnore in git-etc-commit
                    IGNOREFILE="echo \"$FILE\" >> \"$GECIGNORE\""
                    echo "...ignoring for future git-etc-commit runs"
                    echo "$ $IGNOREFILE"
                    eval "$IGNOREFILE"
                    ;;
                [mo]l) # (L)og
                    printf "$(color red)${STATUS:- }$(color off) $FILE\n$(printlog $FILE --follow)\n"
                    continue
                    ;;
                [o]ll) # (L)og multiple
                    printf "$(color red)${STATUS:- }$(color off) $FILE\n$(printlog "$FILE" -p)\n"
                    continue
                    ;;
                [mo]p) # (P)atch i.e. add interactive
                    git add -p "$FILE"
                    continue
                    ;;
                [mo]q) # (Q)uit
                    die "Exiting by user command"
                    ;;
                mr) # (R)evert
                    git checkout -- "$FILE"
                    break
                    ;;
                [mo]s) # (S)kip
                    break
                    ;;
                [mo]t) # (t)ig
                    tig status
                    continue
                    ;;
                [mo]x) # E(x)ecute suggestion
                    [ -z $COMMIT ] && echo -e "Pardon sir, we have no suggestions to eXecute here\n" && continue
                    echo -e "Committing...\n"
                    # -f for files possibly in .gitignored, such as gconf/*
                    # for FILE in $MLIST; do git add -f "$FILE"; done
                    git add -f $(echo "$MLIST")
                    eval $COMMIT 2> /dev/null
                    ;;
                *)
                    die "Empty or unrecognized action, exiting" ;;
            esac
            break
        done

        IFS=$OLDIFS
        unset P CATEGORY PN PV PR
    done

    echo -e "Finished with $FILETYPE\n"
done
