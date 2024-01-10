#!/bin/sh
#
#
# Maintenance shell script to vacuum and backup database
# Put this in /usr/local/etc/periodic/daily, and it will be run 
# every night
#
# Written by Palle Girgensohn <girgen@pingpong.net>
#
# In public domain, do what you like with it,
# and use it at your own risk... :)
#
# modified script from FreeBSD distribution,
# adopted to Linux variants by ruslan shevchenko <ruslan@shevchenko.kiev.ua>

# Define these variables in either /etc/periodic.conf or
# /etc/periodic.conf.local to override the default values.
#
# daily_pgsql_backup_enable="YES" # do backup
# daily_pgsql_vacuum_enable="YES" # do vacuum

daily_pgsql_vacuum_enable="NO"
daily_pgsql_backup_enable="YES"

daily_pgsql_vacuum_args="-z"
daily_pgsql_pgdump_args="-b -F c"
# backupdir is relative to ~pgsql home directory unless it begins with a slash:
#Fedora:
#daily_pgsql_backupdir="/var/lib/pgsql/backups"
#Debian:
daily_pgsql_backupdir="/home/backup/postgres/"

pgsql_user="postgres"
pgsql_password="postgres"

daily_pgsql_savedays="2"

PGPASSWORD=${pgsql_password}
export PGPASSWORD

# allow '~? in dir name
eval backupdir=${daily_pgsql_backupdir}

rc=0

case "$daily_pgsql_backup_enable" in
    [Yy][Ee][Ss])

# Check Master or Slave Node
        i=`su -l ${pgsql_user} -m -c "psql -q -t -A -d template1 -c SELECT\ 'pg_is_in_recovery()'"`   # Должно вернуть (f Master или t Slave)
        if [ "X$i" = "Xt" ] ; then                                                                    # сравниваем полученное значение = "Xt" (Мастер Нода)
            echo "Slave - exit"                                                                       # Если не Мастер, а Слейв - то выходим
            exit 1
        fi

	if [ ! -d ${backupdir} ] ; then 
	    echo Creating ${backupdir}
	    mkdir ${backupdir}; chmod 700 ${backupdir}; chown ${pgsql_user} ${backupdir}
	fi

	echo
	echo "PostgreSQL maintenance"

	# Protect the data
	umask 077
	dbnames=`su -l ${pgsql_user} -m -c "psql -q -t -A -d template1 -c SELECT\ datname\ FROM\ pg_database\ WHERE\ datname!=\'template0\'"`
	rc=$?
	now=`date "+%Y-%m-%dT%H:%M:%S"`
	file=${daily_pgsql_backupdir}/pgglobals_${now}
	su -l ${pgsql_user} -c "pg_dumpall -g | gzip -9 > ${file}.gz"
	for db in ${dbnames}; do
	    echo -n " $db"
	    file=${backupdir}/pgdump_${db}_${now}
	    su -l ${pgsql_user} -c "pg_dump ${daily_pgsql_pgdump_args} -f ${file} ${db}"
	    [ $? -gt 0 ] && rc=3
	done

	if [ $rc -gt 0 ]; then
	    echo
	    echo "Errors were reported during backup."
	fi

	# cleaning up old data
#	find ${backupdir} \( -name 'pgdump_*' -o -name 'pgglobals_*' \) \
#	    -a -mtime +${daily_pgsql_savedays} -delete
	;;
esac

case "$daily_pgsql_vacuum_enable" in
    [Yy][Ee][Ss])

	echo
	echo "vacuuming..."
	su -l ${pgsql_user} -c "vacuumdb -a -q ${daily_pgsql_vacuum_args}"
	if [ $? -gt 0 ]
	then
	    echo
	    echo "Errors were reported during vacuum."
	    rc=3
	fi
	;;
esac
#backup DB here

#rclone sync /home/backup/postgres/$YOUR_S3_BUCKET
exit $rc
