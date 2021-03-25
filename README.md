# elasticsearch-snapshot-s3

Backup Elasticsearch to S3 (supports periodic backups)

## Create Snapshot

Docker:
```sh
$ docker run -e S3_ACCESS_KEY_ID=key -e S3_SECRET_ACCESS_KEY=secret -e S3_BUCKET=my-bucket -e ES_REPO=dbname -e ES_USER=user -e ES_PASSWORD=password -e ES_HOST=localhost treksler/elasticsearch-snapshot-s3
```

Docker Compose:
```yaml
elasticsearch-snapshot-s3:
  image: treksler/elasticsearch-snapshot-s3
  environment:
    ES_SNAPSHOT_ACTION: 'create'
    SCHEDULE: '@daily'
    S3_REGION: ca-central-1
    S3_ACCESS_KEY_ID: key
    S3_SECRET_ACCESS_KEY: secret
    S3_BUCKET: my-bucket
    S3_IAM_ROLE: arn:aws:iam::013456789:role/BackupsESSnapshotRole
    ES_SCHEME: https
    ES_host: elasticsearch
    ES_REPO: dbname
    ES_USER: user
    ES_PASSWORD: password
```

### List Snapshot(s)
```
    ES_SNAPSHOT_ACTION: 'list'
    ES_SNAPSHOT: '_all' # or specify the name of a snapshot to get info about it
```

### List Snapshot Indices
```
    ES_SNAPSHOT_ACTION: 'list-indices'
    ES_SNAPSHOT: '<snapshot name>' # required
```

### Restore Snapshot Indices
```
    ES_SNAPSHOT_ACTION: 'restore'
    ES_SNAPSHOT: '<snapshot name>' # name of snapshot to restore (required)
    ES_IGNORE_UNAVAILABLE: true
    ES_RESTORE_INDICES: '' # will restore all but kibana by default, if this is empty
    ES_RESTORE_GLOBAL_STATE: true # if true this will restore templates, etc.
    ES_RESTORE_ALIASES: false
    ES_RESTORE_OVERWRITE_ALL_INDICES: false # if true, this will DELETE existing indices first, prior to resotring
    ES_RESTORE_OVERWRITE_INDICES: '' # if not empty, this will DELETE this list of existing indices first, prior to resotring
    ES_RESTORE_RENAME_PATTERN='(.+)'
    ES_RESTORE_RENAME_REPLACEMENT=restored_\$1   
```

### Automatic Periodic Backups

You can additionally set the `SCHEDULE` environment variable like `-e SCHEDULE="@daily"` to run the backup automatically.

More information about the scheduling can be found [here](http://godoc.org/github.com/robfig/cron#hdr-Predefined_schedules).


### Elasticsearch

Elasticsearch needs to 

1. have repository-s3 plugin installed 
```
RUN ./bin/elasticsearch-plugin install --batch repository-s3
```

and EITHER:

2.
    a. have AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY stored in the keystore (which practically means storing it in the image, as the changes to the keystore do not take effect until elasticsearch is restarted)
    NOTE: this is only safe if the image is not publicly accessible.
```
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
RUN /usr/share/elasticsearch/bin/elasticsearch-keystore create
RUN echo $AWS_ACCESS_KEY_ID | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.access_key
RUN echo $AWS_SECRET_ACCESS_KEY | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.secret_key
```

OR

2.
    b. allow insecure settings (to avoid having to store S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY in the keystore)
    NOTE: this is only safe if the elasticsearch instance is not publicly accessible
```
"ES_JAVA_OPTS=-Xms${ES_HEAP_SIZE:-1g} -Xmx${ES_HEAP_SIZE:-1g} -Des.allow_insecure_settings=true"
```

### AWS Hosted Elasticsearch

When using AWS hosted elasticsearch, set up the user and the snapshot role as described here:

https://docs.aws.amazon.com/elasticsearch-service/latest/developerguide/es-managedomains-snapshots.html

then pass the ES_ROLE variable
