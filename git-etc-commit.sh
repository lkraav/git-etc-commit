#!/bin/bash
# git-etc-commit 0.4, Leho Kraav <leho@kraav.com> https://github.com/lkraav/git-etc-commit

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
    # log format source: https://twitter.com/#!/lkraav/status/72605873616322560
    git --no-pager log --pretty=tformat:'%Cred%h%Creset|%C(yellow)%d%Creset%s|%Cgreen(%cr)|%C(bold blue)<%an>%Creset' \
        --abbrev-commit --date=relative "$@" |
        while IFS="|" read hash message time author; do
            printf '%s %s %s %s\n' "$hash" "$message" "$time" "$author"
        done
}

getaction() {
}

halfcols() {
    printf "%d" $(bc <<< "($(tput cols) - 10 + $1) / 2")
}

[ $PWD != $DIR ] && die "Error: working directory is not $DIR, cannot continue"
[ -r .git ] || die "Error: unable to read .git, check directory exists or permissions"

echo "Starting processing"

while true; do
    echo "Last 5 commits:"; gitlog -5 --reverse; echo

    FILE=$(git ls-files -m -X $IGNORE | head -n 1)
    [ -n "$FILE" ] || break

    printf "Processing $(color blue)${FILE}$(color off)"

    PKG=$(qfile -qvC "$DIR/$FILE")

    if [ $? = 0 ]; then
        read CATEGORY PN PV PR <<< $(qatom $PKG)
        P="$CATEGORY/$PN-$PV${PR:+-$PR}"

        echo -e ", belongs to $(color blue)$P$(color off)"
        QLIST=$(qlist $P | grep ^$DIR)
        MLIST=""

        EXISTS=""
        HAS_EXISTING=""

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
                # We need this variable in case last file checked is not in the tree
                HAS_EXISTING="yes"
                IFS=" " read STATUS TMP <<< $(git status -s "$p")
                [ "$STATUS" = "M" ] && MLIST+="$p"$'\n'
                LOG=$(gitlog -1 "$p")
            fi
            printf "  $(color ltred)%s$(color off) %-$(halfcols -3)s%$(halfcols -1)s\n" ${STATUS:-' '} "$p" "$LOG"
        done

        if [ -n "$HAS_EXISTING" ]; then
            echo -e "- $(color red)WARNING$(color off): existing files found in tree, this might be an upgrade"
            echo -e "  Merge history:"
            qlop -l "$CATEGORY/$PN" | while read line; do echo "   $line"; done
        fi

        COMMIT="git commit -m \"upgrade -> $(qlist -IUCv $P)\" -uno -q"
        echo "  $ $COMMIT"
        COMMIT="$COMMIT" QLIST="$QLIST" MLIST="$MLIST" getaction m "$FILE"
        # Actions can be modified, markers used are same as git ls-files parameters
        # m modified, o other (i.e. untracked)
        local STATUS="$1"; shift
        local FILE="$@"

        while true; do
        read -p "  $(color blue)$FILE$(color off) $(color red)Action?$(color off) (A)mend,(C)ommit,(D)el,(E)dit,Di(F)f,(I)gnore,(L)og,(P)atch,(R)efresh,(T)ig,(U)pgrade,(Q)uit: " OACTION
        OACTION="$STATUS$OACTION"
        case "${OACTION,,}" in
            [mo]a)
                git add "$FILE"
                git commit --amend
                ;;
            [mo]c)
                git commit "$FILE"
                ;;
            [mo]d)
                rm -i "$FILE"
                ;;
            [mo]e)
                eval $EDITOR "$FILE"
                continue
                ;;
            [mo]ee)
                $MULTIEDITOR $QLIST
                continue
                ;;
            [mo]f)
                git diff --no-color "$FILE"
                continue
                ;;
            [mo]ff)
                git diff --no-color -- $(echo "$MLIST")
                continue
                ;;
            oi)
                IGNOREFILE="echo \"$FILE\" >> \"$IGNORE\""
                echo "  ...orphan, ignoring"
                echo "  $ $IGNOREFILE"
                eval "$IGNOREFILE"
                ;;
            [mo]l)
                gitlog "$FILE"
                continue
                ;;
            [mo]ll)
                gitlog -p "$FILE"
                continue
                ;;
            [mo]p)
                git add -p "$FILE"
                git commit
                ;;
            [mo]r)
                break
                ;;
            [mo]t)
                tig status
                continue
                ;;
            mu)
                # -f is needed to add files that are possibly in .gitignored, such as gconf/*
                echo "  Committing..."
                for f in $MLIST; do git add -f "$f"; done
                eval $COMMIT 2> /dev/null
                ;;
            *)
                die "Empty or unrecognized action, exiting" ;;
        esac
        break
        done

        IFS=$OLDIFS
    else
        # TODO: what about custom injected configuration files? They
        # should not be ignored.
        echo " - no owner found"
        getaction o "$FILE"
        pause "keep working"
    fi
done

cat $IGNORE | less

echo "Finished"
