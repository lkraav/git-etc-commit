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
            printf "  $(color red)%${WH}s$(color off) %-${WM}s $(color green)%${WT}s$(color off) $(color blue)%-${WA}s$(color off)\n" "${hash:0:$WH}" "${message:0:$WM}" "${time:0:$WT}" "${author:0:$WA}"
        done
}

fieldwidth() {
    printf -v FLOAT "%s" "$(bc <<< "$COLUMNS * $1")"
    echo ${FLOAT/\.*}
}

[ $PWD != $DIR ] && die "Error: working directory is not $DIR, cannot continue"
[ -r .git ] || die "Error: unable to read .git, check directory exists or permissions"

# Processing goes in two passes. First go through others, then modifieds.
for FILETYPE in others modified; do
    echo "Starting processing $FILETYPE..."

    for FILE in $(git ls-files --$FILETYPE -X $IGNORE); do
        echo -e "\nLast 5 commits:"; gitlog -5 --reverse; echo

        [ -n "$FILE" ] || break

        printf "Processing $(color blue)$FILE$(color off)"

        PKG=$(qfile -qvC "$DIR/$FILE")

        if [ $? = 0 ]; then
            read CATEGORY PN PV PR <<< $(qatom $PKG)
            P="$CATEGORY/$PN-$PV${PR:+-$PR}"

            echo -e ", belongs to $(color blue)$P$(color off)"
            QLIST=$(qlist $P | grep ^$DIR) # list of all files owned by package in /etc
            MLIST=""                       # ...only package files with modifications

            EXISTS=""
            HAS_EXISTING="" # need this in case last file checked is not in the tree

            OLDIFS=$IFS
            IFS=$'\n'

            echo "  Package contents (grep $DIR):"
            for p in $QLIST; do
                # For each file we have to determine, whether this package
                # already has files in the tree. In case this might
                # be an upgrade, commit message should reflect that.
                # In case package has files in modified state, it can be:
                #  - uncommited configuration changes
                #  - version upgrades

                # git ls-files can throw errors here if $p is symlink pointing to
                # outside the repository
                EXISTS=$(git ls-files "$p")
                LOG=""
                STATUS=""
                
                if [ -n "$EXISTS" ]; then
                    HAS_EXISTING="yes"
                    IFS=" " read STATUS TMP <<< $(git status -s "$p")
                    [ "$STATUS" = "M" ] && MLIST+="$p"$'\n'
                    LOG=$(gitlog -1 "$p")
                fi
                printf "  $(color ltred)%s$(color off) %s %s\n" ${STATUS:-' '} "$p" "$LOG"
            done

            if [ -n "$HAS_EXISTING" ]; then
                echo -e "- $(color red)WARNING$(color off): existing files found in tree, \
                    this might be an upgrade"
                echo -e "  Merge history:"
                qlop -l "$CATEGORY/$PN" | while read line; do echo "   $line"; done
            fi

            OPTYPE="emerge"
            [ "$FILETYPE" = "modified" ] && OPTYPE="upgrade ->"
            COMMIT="git commit -m \"$OPTYPE $(qlist -IUCv $P)\" -uno -q"
            echo "  $ $COMMIT"
            # Actions can be modified, markers used are same as git ls-files parameters
            # m modified, o other (i.e. untracked)
        else
            echo " - no owner found"
        fi

        while true; do
        echo "  $(color blue)$FILE$(color off) $(color red)Action?$(color off)"
            read -p "  (A)mend,(C)ommit,(D)el,(E)dit,Di(F)f,(I)gnore,(L)og,(P)atch,(S)kip,(T)ig,(U)pgrade,(Q)uit: " OACTION
            OACTION="${FILETYPE:0:1}$OACTION"
            case "${OACTION,,}" in
                [mo]a) # (A)mend
                    git add "$FILE"
                    git commit --amend
                    ;;
                [mo]c) # (C)ommit
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
                    git diff --no-color "$FILE"
                    continue
                    ;;
                [mo]ff) # Di(ff) multiple
                    git diff --no-color -- $(echo "$MLIST")
                    continue
                    ;;
                oi) # (I)gnore
                    IGNOREFILE="echo \"$FILE\" >> \"$IGNORE\""
                    echo "  ...orphan, ignoring"
                    echo "  $ $IGNOREFILE"
                    eval "$IGNOREFILE"
                    ;;
                [mo]l) # (L)og
                    gitlog "$FILE"
                    continue
                    ;;
                [mo]ll) # (L)og multiple
                    gitlog -p "$FILE"
                    continue
                    ;;
                [mo]p) # (P)atch i.e. add interactive
                    git add -p "$FILE"
                    git commit
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
                    echo "  Committing..."
                    # -f for files possibly in .gitignored, such as gconf/*
                    for f in $MLIST; do git add -f "$f"; done
                    eval $COMMIT 2> /dev/null
                    ;;
                *)
                    die "Empty or unrecognized action, exiting" ;;
            esac
            break
        done

        IFS=$OLDIFS
    done

    echo "Finished with $FILETYPE"
done
