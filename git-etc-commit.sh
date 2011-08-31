#!/bin/bash
# git-etc-commit 0.4, Leho Kraav <leho@kraav.com> https://github.com/lkraav/git-etc-commit

DIR="/etc"
IGNORE="$DIR/.gitignore"
# GITLOG source: https://twitter.com/#!/lkraav/status/72605873616322560
GITLOG="git --no-pager log --graph --pretty=tformat:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative -1"
PAGER=""
SEP="-"
SEPARATOR=""

die() {
    echo "$@"
    exit 1
}

pause() {
    [ -n "$@" ] && echo -n -e "- Press ENTER to \033[1;31m$1\033[0m, "
    read -p "CTRL-C to quit"
}

[ $PWD != $DIR ] && die "Error: working directory is not $DIR, cannot continue"
[ -r .git ] || die "Error: unable to read .git, check directory exists or permissions"

echo "Starting processing"

while true; do
    # STATUS=$(git status -uno -s)
    # [ -n "$STATUS" ] && die "Error: working directory not clean, cannot continue"

    echo -e "\nLast commit was:\n$(eval "$GITLOG -1")\n"

    FILE=$(git ls-files -o -X $IGNORE | head -n 1)
    [ -n "$FILE" ] || break

    echo -n -e "Processing \033[1;34m${FILE}\033[0m"

    PKG=$(qfile -qvC "$DIR/$FILE")
    if [ $? = 0 ]; then
        echo -e ", belongs to \033[1;34m${PKG}\033[0m"
        QLIST=$(qlist $PKG | grep ^$DIR)

        EXISTS=""
        HAS_EXISTING=""

        OLDIFS=$IFS
        IFS=$'\n'

        echo "  Package contents (grep $DIR):"
        for p in $QLIST; do
            # For each file we have to determine, whether this package
            # already has files in the tree. In this case this might
            # be an upgrade, commit message should reflect that.
            # In case package has files in modified state, it can be:
            #  - uncommited configuration changes
            #  - version upgrades
            EXISTS=$(git ls-files $p)
            echo -n "   $p"
            
            if [ -n "$EXISTS" ]; then
                HAS_EXISTING="yes"
                echo -n " M $(eval $GITLOG -1 $p)"
            fi
            echo
        done

        if [ -n "$HAS_EXISTING" ]; then
            echo -e "- \033[1;31mWARNING\033[0m: existing files found in tree, this might be an upgrade"
            qlop -l $PKG
        fi

        COMMIT="git commit -m \"emerge $(qlist -IUCv $PKG)\" -uno -q"
        echo "  $ $COMMIT"
        pause "commit"
        
        # -f is needed to add files that are possibly in .gitignored, such as gconf/*
        echo "  Committing..."
        git add -f $QLIST
        eval $COMMIT 2> /dev/null

        IFS=$OLDIFS
    else
        # TODO: what about custom injected configuration files? They
        # should not be ignored.
        echo " - no owner found"
        read -p "  Action? (A)mend,(C)ommit,(E)dit,(I)gnore,(Q)uit: " OACTION   
        case "$OACTION" in
            A)
                git add "$FILE"
                git commit --amend
                ;;
            C)
                git add "$FILE"
                git commit
                ;;
            E)
                eval $EDITOR "$FILE"
                ;;
            I)
                IGNOREFILE="echo \"$FILE\" >> \"$IGNORE\""
                echo "  ...orphan, ignoring"
                echo "  $ $IGNOREFILE"
                eval "$IGNOREFILE"
                ;;
            *)
                die "No action, exiting" ;;
        esac
        pause "keep working"
    fi
done

cat $IGNORE | less

echo "Finished"
