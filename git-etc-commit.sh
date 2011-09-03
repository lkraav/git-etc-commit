#!/bin/bash
# git-etc-commit 0.4, Leho Kraav <leho@kraav.com> https://github.com/lkraav/git-etc-commit

COLUMNS=80 # replace with $(tput cols) for variable width
DIR="/etc"
IGNORE="$DIR/.gitignore"
MULTIEDITOR="$EDITOR -p"
PAGER=""
SEP="-"
SEPARATOR=""

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
            printf "  \-$(color red)%${WH}s$(color off) %-${WM}s $(color green)%${WT}s$(color off) $(color blue)%-${WA}s$(color off)\n" "${hash:0:$WH}" "${message:0:$WM}" "${time:0:$WT}" "${author:0:$WA}"
        done
}

fieldwidth() {
    printf -v FLOAT "%s" "$(bc <<< "$COLUMNS * $1")"
    echo ${FLOAT/\.*}
}

getstatus() {
    # git-status doesn't like absolute paths, make sure you give it relatives
    IFS=" " read STATUS TMP <<< $(git status -s "$1")
    echo $STATUS
}

printlog() {
    local FILE="$1"; shift

    printf "%s $(color ltred)%s$(color off) %s\n" "$(gitlog $@ -- $FILE)"
}

[ $PWD != $DIR ] && die "Error: working directory is not $DIR, cannot continue"
[ -r .git ] || die "Error: unable to read .git, check directory exists or permissions"

# Processing goes in two passes. First go through others, then modifieds.
for FILETYPE in others modified; do
    echo "Starting processing $FILETYPE..."

    # Should have a (x/X) counter here
    # Counting can be difficult when we actually make changes to the list inside loop
    LSFILES=$(git ls-files --$FILETYPE -X $IGNORE)
    COUNT=$(echo "$LSFILES" | wc -l)
    C=0
    for FILE in $LSFILES; do
        [ -n "$FILE" ] || break
        let C++

        STATUS=$(getstatus "$FILE")
        if [ -z "$STATUS" ]; then
            echo -e "$(color ltblue)$FILE$(color off) has no change status, it was probably already processsed. Skipping..."
            continue
        fi

        echo -e "\nLast 5 commits:"; gitlog -5 --reverse; echo

        printf "($C/$COUNT) Processing $(color ltred)${STATUS:+$STATUS }$(color off)$(color ltblue)$FILE$(color off)"

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
                STATUS=""
                EXISTS=$(git ls-files "$PFILE")
                
                if [ -n "$EXISTS" ]; then
                    HAS_EXISTING="yes"
                    STATUS=$(getstatus "$PFILE")
                    [ "$STATUS" = "M" ] && MLIST+="$PFILE"$'\n'
                fi
                printf "$(color red)${STATUS:- }$(color off) ${PFILE#$DIR/}\n$(printlog "$PFILE" -1)\n"
            done

            if [ -n "$HAS_EXISTING" ]; then
                echo -e "\n$(color red)WARNING$(color off): existing files found in tree, this might be an upgrade\n"
                echo -e "Merge history:"
                qlop -l "$CATEGORY/$PN-" | while read line; do echo "$line"; done
                echo
            fi

            [ "$FILETYPE" = "modified" ] && OPTYPE="upgrade ->"
            COMMIT="git commit -m \"$OPTYPE $(qlist -IUCv $P)\" -uno -q"
            echo "$ $COMMIT"
        else
            printf " - no owner found\n"
            printlog "$FILE" -1
        fi

        while true; do
            read -p "(A)mend,(C)ommit,(D)el,(E)dit,Di(F)f,(I)gnore,(L)og,(P)atch,(S)kip,(T)ig,(U)pgrade,(Q)uit: " OACTION
            OACTION="${FILETYPE:0:1}$OACTION"
            case "${OACTION,,}" in
                [mo]a) # (A)mend
                    git add "$FILE"
                    git commit --amend
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
                    [ -n "$COMMIT" ] && eval "$COMMIT" "$FILE" || git commit "$FILE"
                    if [ $? != 0 ]; then
                        git reset -q HEAD
                        continue
                    fi
                    ;;
                [mo]d) # (D)elete
                    rm -i "$FILE"
                    ;;
                [mo]e) # (E)dit
                    eval $EDITOR "$FILE"
                    continue
                    ;;
                [mo]ee) # (E)dit multiple
                    $MULTIEDITOR $QLIST
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
                oi) # (I)gnore
                    IGNOREFILE="echo \"$FILE\" >> \"$IGNORE\""
                    echo "...orphan, ignoring"
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
                [mo]s) # (S)kip
                    break
                    ;;
                [mo]t) # (t)ig
                    tig status
                    continue
                    ;;
                mu) # (U)pgrade
                    echo -e "Committing...\n"
                    # -f for files possibly in .gitignored, such as gconf/*
                    for FILE in $MLIST; do git add -f "$FILE"; done
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
