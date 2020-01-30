#! /bin/sh

set -e

# read values from file, if available
if [ -f "${ES_USER_FILE}" ] ; then
  export ES_USER="$(cat ${ES_USER_FILE})"
fi
if [ -f "${ES_PASSWORD_FILE}" ] ; then
  export ES_PASSWORD="$(cat ${ES_PASSWORD_FILE})"
fi

# run snapshot.sh, if no command was passed
if [ -z "$@" ] ; then
  set -- /bin/sh /usr/local/bin/snapshot.sh
fi

# run on a schedule, if specified
if [ -n "${SCHEDULE}" ]; then
  set -- /usr/local/bin/go-cron "$SCHEDULE" "$@"
fi

# run command
exec "$@"
