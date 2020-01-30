#! /bin/sh

set -e
set -o pipefail


if [ -z "${S3_BUCKET}" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ -z "${ES_HOST}" ]; then
  echo "You need to set the ES_HOST environment variable."
  exit 1
fi

if [ -z "${ES_REPOSITORY}" ]; then
  echo "You need to set the ES_REPOSITORY environment variable."
  exit 1
fi

if [ -z "${ES_USER}" ]; then
  echo "You need to set the ES_USER environment variable."
  exit 1
fi

if [ -n "${S3_ENDPOINT}" ]; then
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

# construct ES_URL
ES_URL="${ES_SCHEME}://${ES_USER}:${ES_PASSWORD}@${ES_HOST}:${ES_PORT}"

## -------------- setup repositories ---------------

# detect project name by removing all possible ENV suffixes from repository name
ES_REPOSITORY_BASE=${ES_REPOSITORY}
for ENV in ${ES_REPOSITORY_ENV_LIST} ; do
  ES_REPOSITORY_BASE=${ES_REPOSITORY_BASE%-${ENV}}
done

# add all suffixes
ES_REPOSITORY_LIST="${ES_REPOSITORY_BASE}"
for ENV in ${ES_REPOSITORY_ENV_LIST} ; do
  ES_REPOSITORY_LIST="${ES_REPOSITORY_LIST} ${ES_REPOSITORY_BASE}-${ENV}"
done

for REPO in ${ES_REPOSITORY_LIST} ; do 
  if [ -n "${S3_ACCESS_KEY_ID}" ] && [ -n "${S3_SECRET_ACCESS_KEY}" ]; then
    curl -s -k -H 'Content-Type: application/json' -X PUT "${ES_URL}/_snapshot/${REPO}-s3-repository?verify=false&pretty" -d'
    {
      "type": "s3",
      "settings": {
        "bucket": "'${S3_BUCKET}'",
        "region": "'${S3_DEFAULT_REGION}'",
        "base_path": "'${REPO}'/elasticsearch",
        "client": "default",
        "access_key": "'${S3_ACCESS_KEY_ID}'",
        "secret_key": "'${S3_SECRET_ACCESS_KEY}'"
      }
    }'
  else
    curl -s -k -H 'Content-Type: application/json' -X PUT "${ES_URL}/_snapshot/${REPO}-s3-repository?verify=false&pretty" -d'
    {
      "type": "s3",
      "settings": {
        "bucket": "'${S3_BUCKET}'",
        "region": "'${S3_DEFAULT_REGION}'",
        "base_path": "'${REPO}'/elasticsearch",
        "client": "default"
      }
    }'
  fi
done


## -------------- perform snapshot ---------------

curl -s -k -XPUT "${ES_URL}/_snapshot/${ES_REPOSITORY}-s3-repository/${ES_REPOSITORY}_$(date +%Y-%m-%d_%H-%M-%S)?pretty&wait_for_completion=true"

## -------------- remove old snapshots ---------------

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

# refuse to prune old backups if MAX_AGE is not set
if [ -z "${MAX_AGE}" ] ; then
  "You need to set the MAX_AGE environment variable."
  exit 2
fi

# prune old snapshots
MAX_AGE=$(duration2seconds ${MAX_AGE})
now=$(date +%s);
older_than=$((now-MAX_AGE))
curl -s -k -XGET "${ES_URL}/_snapshot/${ES_REPOSITORY}-s3-repository/_all?pretty" | jq -r '.[][] | "\(.start_time) \(.snapshot)" | sub("T"; " ") | sub ("\\..*Z"; "")' | while read date time name ; do
  created=$(date -d "$date $time" +%s); 
  if [[ $created -lt $older_than ]] ; then 
    if [ -n "${name}" ] ; then 
      curl -s -k -XDELETE "${ES_URL}/_snapshot/${ES_REPOSITORY}-s3-repository/${name}?pretty" 
    fi
  fi
done
