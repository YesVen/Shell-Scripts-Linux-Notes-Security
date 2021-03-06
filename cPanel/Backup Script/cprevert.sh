#! /bin/sh
#=============================================================================
#
#  Run through an account's cPanel backups in reverse chronological order
#  (as from findbackup -s) restoring the backups with extensions based on
#  the backup date.
#
#  This script semi-automates restoration from cPanel backup
#
#  NB: Use at your own risk; has been subjected to basic testing only.
#
#  Usage: revert [-a] filename
#  or     revert [-a] directoryname
#  or	  revert [-a] /home/user/somefilename
#
#  Without the -a flag, will only restore file versions that do differ
#  With -a, will restore all versions, even if identical
#
#  eg: # cd /home/someuser/public_html
#      # revert some_deleted_file.htm
#      # ls -l some_deleted_file.htm.bak_*
#=============================================================================

ME=${0##*/}
unset CDPATH

keepall=
distinct=distinct

fatal() { echo $ME: $* 1>&2; exit 1; }

#
# restore_backup $user $n $backupfile $file
# internal function called from mainline to restore an indiv file
#
restore_backup()
{
    local user=$1
    local backup=$2
    local file=$3
    local destination=$4
    local restored=1

    # form a "pretty" (short) name from full backup name eg 20091129_weekly
    dname=$(echo $backup | 
    	sed -e "s/\.tar\.gz$//" \
	    -e "s/$user$//" \
	    -e "s;^.*cpbackup/;;" \
	    -e "s;/$;;" \
	    -e "s;/;_;g" \
	    -e 's;^\(weekly\|daily\|monthly\)_\(.*\);\2_\1;g' \
	    )
    echo -n "  --> " $dname ...

    #
    #   Now restore the file and save it under name.bak_$dname
    #
    rm -fr tmp$$
    mytmp=$PWD/tmp$$
    trap "rm -rf tmp$$ ../tmp$$; exit" 1 2 15
    mkdir tmp$$
    cd tmp$$ || fatal cannot chdir tmp$$

    if [ "$homedir" = "" ]
    then
	#   This is pretty inefficient!! so we do once and assume stays same
	homedir=$(tar tzf $backup | grep /homedir.tar$ | head -1)
    fi
    if [ ! -s $backup ]
    then
        echo "(backup zero length!)"
	return 1
    fi

    #
    #   Extract home dir tarfile, then the actual file
    #
    echo -n " h"
    tar xzf $backup $homedir
    echo -n f
    # hate to suppress errors, but get big mess if file not in backup
    tar xf $homedir  $file    2> /dev/null

    #
    #   Preserve the file, if it exists and was different
    #
    if [ "$lastdiff" = "" ]
    then
        lastdiff="$destination"
    fi
    if [ ! -e $file ]
    then
	# file was not in backup (or error extracting)
        echo -n "(not found)"
    elif [ "$keepall" = "" ] && cmp -s $lastdiff $file
    then
	# no change since last version
        echo -n "(no change)"
        had_file=yes
    else
	# preserve the file
	dest=${destination}.bak_$dname
	lastdiff=$dest
	mv $file $dest
	echo -n m
	restored=0
    fi

    cd ..
    rm -rf tmp$$
	trap - 1 2 15
    echo
    return $restored
}


# take the supplied argument and make it relative to their homedir
homedir_ize()
{
    local f=$1

    case "$f" in
    /*) ;;
    *)	f=$PWD/$f ;;
    esac
    f=./${f#/home/*/}
    echo $f
}


#
#   Mainline start
#

if [ $# == 0 ]
then
     fatal "run with -h for help message"
fi

case "$1" in
-h|--help*)
	echo "Usage: $ME [-a] file-or-directory-name"
	echo "Must be run from a user home directory or with full path"
	exit 0
    ;;
esac

[ -w / ] || fatal must be run as root, sorry

if [ "$1" = "-a" ]
then
    echo "[keeping all changed copies found]"
    keepall=yes
    distinct=
    shift
fi



#
#  Argument is a file/directory, or should be
#
file=$1

case $file in
/home/*) ;;
/*) fatal file outside home tree!  ;;
esac


# derive user from file or PWD
if [ "$user" = "" ]
then
    case $file in
    /home/*) user=$file ;;
    *)	case $PWD in
	/home/*) ;;
	*) fatal cannot derive user - cd to their home or use full path
	   ;;
	esac
	user=$PWD ;;
    esac
    user=${user#/home/}
    user=${user%%/*}
    test -d /home/$user || fatal no such user as $user
    test "$user" != "" || fatal null user - assert fail
fi
echo user = $user


backupfile=$(homedir_ize $file)
destfile=$file
case $destfile in
/*) ;;
*)  destfile=$PWD/$file ;;
esac

echo looking for $backupfile

echo



#
#   Loop through existing backups
#
lastdiff=
had_file=    #horrible hack :) true if had file, but no diffs
count=0
for n in $(findbackup -s $user)
do

    #echo === $n ========================
    good=yes
    if restore_backup $user $n $backupfile $destfile
    then
	(( count += 1 ))
    fi
done

if [ "$good" != yes ]
then
    fatal "No restore files specified"
fi

if (( count == 0 ))
then
    if [ "$had_file" != "" ]
    then
        echo
	echo Failed to find a different version of your file, sorry
    else
	fatal "restore failed to find your file, sorry"
    fi
fi

echo
echo Restored $count $distinct versions
