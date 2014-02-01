#!/bin/bash

AUTHOR="Mauro Carvalho Chehab"

unset TYPE
unset HELP
unset ENDHASH
unset SILENT

while [ $# -ne 0 ]; do
        case $1 in
	--help)
		HELP="1"
		;;
	--committer)
		TYPE="%cd %cn"
		;;
	--author)
		TYPE="%ad %an"
		;;
	--name)
		shift
		AUTHOR="$1"
		;;
	--since)
		shift
		START="$1"
		;;
	--since-hash)
		shift
		STARTHASH="$1"
		;;
	--to-hash)
		shift
		ENDHASH="$1"
		;;
	--to)
		shift
		END="$1"
		;;
	--silent)
		shift
		SILENT=1
	esac
	shift
done

if [ "$START" == "" ]; then
	if [ "$STARTHASH" == "" ]; then
		echo "Start date or hash missing"
		HELP="1"
	fi
fi

if [ "$TYPE" == "" ]; then
	echo "--committer or --author is missing"
	HELP="1"
fi

if [ "$HELP" != "" ]; then
	echo "$0 <--commiter|--author> --since <start date> [--to <end date>] [--name <author/committer's name>]"
	echo
	echo "dates should be on ISO format: year-mo-dy, like 2013-11-23"
	echo "if not <end date>, it will use today"
	exit
fi

if [ "$STARTHASH" == "" ]; then
	if [ "$END" == "" ]; then
		END=$(date --iso)
	fi

	if [ "$SILENT" == "" ]; then
		echo "git log --format=\"%H $TYPE\" --date-order --date=iso --since \"$START\" |grep \"$AUTHOR\" |ruby -ane \"hash, date = \$F[0..1] ; puts hash if (\"$START\"..\"$END\").cover?(date)"
		for i in $(git log --format="%H $TYPE" --date-order --date=iso --since "$START" |grep "$AUTHOR" |ruby -ane "hash, date = \$F[0..1] ; puts hash if (\"$START\"..\"$END\").cover?(date)"); do
			git log -n 1 $i --pretty=oneline |cat
		done

		echo -n "Number of commits: "
	fi
	git log --format="%H $TYPE" --date-order --date=iso --since "$START" |grep "$AUTHOR" |ruby -ane "hash, date = \$F[0..1] ; puts hash if (\"$START\"..\"$END\").cover?(date)"|wc -l
else
	if [ "$SILENT" == "" ]; then
		for i in $(git log --format="%H $TYPE" --date-order --date=iso "$STARTHASH..$ENDHASH" |grep "$AUTHOR"|cut -d' ' -f1); do
			git log -n 1 $i --pretty=oneline |cat
		done

		echo -n "Number of commits: "
	fi
	git log --format="%H $TYPE" --date-order --date=iso "$STARTHASH..$ENDHASH" |grep "$AUTHOR"|wc -l
fi
