#!/bin/bash

IGNORE="/root/orphans"

die() {
	echo $@
	exit 1
}

pause() {
	[ -n $1 ] && echo -n -e "- Press ENTER to \033[1;31m$1\033[0m, CTRL-C to quit"
	read
}

> $IGNORE

while true; do
	clear
	# Source: https://twitter.com/#!/lkraav/status/72605873616322560
	git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative -1
	STATUS=`git status -uno -s`
	[ -n "${STATUS}" ] && die "Error: staging area not empty, cannot continue"

	FILE=`git ls-files -o -X $IGNORE | head -n 1`
	[ -n "${FILE}" ] || break

	echo -n -e "* Processing \033[1;34m${FILE}\033[0m"

	PKG=`qfile -qvC "/etc/${FILE}"`
	if [ $? = 0 ]; then
		echo -e ", belongs to \033[1;34m${PKG}\033[0m"
		QLIST=`qlist ${PKG} | grep ^/etc`

		echo "  Package contents (grep /etc):"
		for p in $QLIST; do
			echo "   $p" 
		done

		pause "commit"
		
		echo "  Committing..."
		git add $QLIST
		COMMIT="git commit -m \"emerge `qlist -IUCv $PKG`\" -uno -q"
		echo "  $ ${COMMIT}"
		eval $COMMIT 2> /dev/null
	else
		echo " - orphan, ignoring"
		echo $FILE >> $IGNORE 
		pause "continue"
	fi
done

cat $IGNORE | less

echo "Finished"
