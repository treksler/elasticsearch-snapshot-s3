#! /bin/sh

set -e
set -o pipefail

# date function is very limited in busybox
function duration2seconds () {
  COUNT=${1//[[:alpha:]]*}
  UNIT=${1##*[[:digit:]]}
  case "${UNIT}" in
    S)
      echo ${COUNT}
      ;;
    M)
      echo $((COUNT*60))
      ;;
    H)
      echo $((COUNT*60*60))
      ;;
    d)
      echo $((COUNT*60*60*24))
      ;;
    w)
      echo $((COUNT*60*60*24*7))
      ;;
    m)
      echo $((COUNT*60*60*24*30))
      ;;
    y)
      echo $((COUNT*60*60*24*30*365))
      ;;
    *)
      echo ${COUNT}
      ;;
  esac
}

if [ -z "${S3_BUCKET}" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ -z "${ES_HOST}" ]; then
  echo "You need to set the ES_HOST environment variable."
  exit 1
fi

if [ -z "${ES_REPO}" ]; then
  echo "You need to set the ES_REPO environment variable."
  exit 1
fi

if [ -n "${S3_ENDPOINT}" ]; then
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

# signed AWS ES requests do not work with a port          
if [ -n "${S3_IAM_ROLE}" ] ; then         
  unset ES_PORT                                                      
fi                                                                   
                                                                     
# construct ES_URL                                                   
if [ -n "${ES_USER}" ] ; then                                        
  ES_URL="${ES_SCHEME:-https}://${ES_USER}:${ES_PASSWORD}@${ES_HOST}"
else                                                                 
  ES_URL="${ES_SCHEME:-http}://${ES_HOST}"                           
fi                                                                   
if [ -n "${ES_PORT}" ] ; then                     
  ES_URL="${ES_URL}:${ES_PORT}"                   
fi

## -------------- setup repository ---------------

if [ -n "${S3_IAM_ROLE}" ] ; then
  awscurl \
    --service=es \
    --region=${S3_DEFAULT_REGION} \
    --access_key=${S3_ACCESS_KEY_ID} \
    --secret_key=${S3_SECRET_ACCESS_KEY} \
    -X PUT ${ES_URL}/_snapshot/${ES_REPO}-s3-repository \
    -d '
  {
    "type": "s3",
    "settings": {
      "bucket": "'${S3_BUCKET}'",
      "region": "'${S3_DEFAULT_REGION}'",
      "base_path": "'${ES_REPO}'",
      "role_arn": "'${S3_IAM_ROLE}'"
    }
  }
  '
elif [ -n "${S3_ACCESS_KEY_ID}" ] && [ -n "${S3_SECRET_ACCESS_KEY}" ]; then
  curl -s -k -H 'Content-Type: application/json' -X PUT "${ES_URL}/_snapshot/${ES_REPO}-s3-repository?verify=false&pretty" -d'
  {
    "type": "s3",
    "settings": {
      "bucket": "'${S3_BUCKET}'",
      "region": "'${S3_DEFAULT_REGION}'",
      "base_path": "'${ES_REPO}'",
      "client": "default",
      "access_key": "'${S3_ACCESS_KEY_ID}'",
      "secret_key": "'${S3_SECRET_ACCESS_KEY}'"
    }
  }'
else
  curl -s -k -H 'Content-Type: application/json' -X PUT "${ES_URL}/_snapshot/${ES_REPO}-s3-repository?verify=false&pretty" -d'
  {
    "type": "s3",
    "settings": {
      "bucket": "'${S3_BUCKET}'",
      "region": "'${S3_DEFAULT_REGION}'",
      "base_path": "'${ES_REPO}'",
      "client": "default"
    }
  }'
fi

case "${ES_SNAPSHOT_ACTION:-create}" in
  create)
    ## -------------- create snapshot ---------------
    curl -s -k -XPUT "${ES_URL}/_snapshot/${ES_REPO}-s3-repository/${ES_REPO}_$(date +%Y-%m-%d_%H-%M-%S)?pretty&wait_for_completion=true"
    ## -------------- remove old snapshots ---------------
    # refuse to prune old backups if MAX_AGE is not set
    if [ -z "${MAX_AGE}" ] ; then
      echo "You need to set the MAX_AGE environment variable." >&2
      exit 2
    fi
    # prune old snapshots
    MAX_AGE=$(duration2seconds ${MAX_AGE})
    now=$(date +%s);
    older_than=$((now-MAX_AGE))
    curl -s -k -XGET "${ES_URL}/_snapshot/${ES_REPO}-s3-repository/_all?pretty" | jq -r '.[][] | "\(.start_time) \(.snapshot)" | sub("T"; " ") | sub ("\\..*Z"; "")' | while read date time name ; do
      created=$(date -d "${date} ${time}" +%s);
      if [[ ${created} -lt ${older_than} ]] ; then
        if [ -n "${name}" ] ; then
          curl -s -k -XDELETE "${ES_URL}/_snapshot/${ES_REPO}-s3-repository/${name}?pretty"
        fi
      fi
    done
    ;;
  list)
    ## -------------- list snapshots ---------------
    curl -s -k -XGET "${ES_URL}/_snapshot/${ES_REPO}-s3-repository/${ES_SNAPSHOT:-_all}?pretty"
    ;;
  list-indices)
    ## -------------- list snapshot indices ---------------
    # refuse to restore if ES_SNAPSHOT is not set
    if [ -z "${ES_SNAPSHOT}" ] ; then
      echo "You need to set the ES_SNAPSHOT environment variable." >&2
      exit 3
    fi
    curl -s -k -XGET "${ES_URL}/_snapshot/${ES_REPO}-s3-repository/${ES_SNAPSHOT}/" | jq -r .snapshots[0].indices[] | tr '\n' ','
    ;;
  restore)
    ## -------------- restore snapshot ---------------
    # refuse to restore if ES_SNAPSHOT is not set
    if [ -z "${ES_SNAPSHOT}" ] ; then
      echo "You need to set the ES_SNAPSHOT environment variable." >&2
      exit 3
    fi
    # by default, restore all indices except kibana
    ES_RESTORE_INDICES="${ES_RESTORE_INDICES:-$(curl -s -k -XGET "${ES_URL}/_snapshot/${ES_REPO}-s3-repository/${ES_SNAPSHOT}/" | jq -r .snapshots[0].indices[] | grep -v kibana | tr '\n' ',')}"
    # refuse to restore if ES_RESTORE_INDICES is blank
    if [ -z "${ES_RESTORE_INDICES}" ] ; then
      echo "You need to set the ES_RESTORE_INDICES environment variable." >&2
      exit 4
    fi
    # overwrite existing indices if desired
    if [ "${ES_RESTORE_OVERWRITE_ALL_INDICES}" == "true" ] || [ "${ES_RESTORE_OVERWRITE_ALL_INDICES}" == "1" ] ; then
      for index in ${ES_RESTORE_INDICES//,/ } ; do
        # check if index exists and delete it
        [ "$(curl -qs -XGET "${ES_URL}/${index}" | jq .error)" == "null" ] && curl -s -k -XDELETE "${ES_URL}/${index}"
      done
    elif [ -n "${ES_RESTORE_OVERWRITE_INDICES}" ] ; then
      for index in ${ES_RESTORE_OVERWRITE_INDICES//,/ } ; do
        # check if index exists and delete it
        [ "$(curl -qs -XGET "${ES_URL}/${index}" | jq .error)" == "null" ] && curl -s -k -XDELETE "${ES_URL}/${index}"
      done
    fi
    # restore snapshot
    curl -s -k -XPOST "${ES_URL}/_snapshot/${ES_REPO}-s3-repository/${ES_SNAPSHOT}/_restore?pretty" -H 'Content-Type: application/json' -d'
    {
      "indices": "'${ES_RESTORE_INDICES}'",
      "ignore_unavailable": '${ES_IGNORE_UNAVAILABLE:-true}',
      "include_global_state": '${ES_RESTORE_GLOBAL_STATE:-false}',
      "rename_pattern": "'${ES_RESTORE_RENAME_PATTERN}'",
      "rename_replacement": "'${ES_RESTORE_RENAME_REPLACEMENT}'",
      "include_aliases": '${ES_RESTORE_ALIASES:-false}'
    }'
    ;;
esac
