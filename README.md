# elasticsearch-snapshot-s3

Backup Elasticsearch to S3 (supports periodic backups)

## Usage

Docker:
```sh
$ docker run -e S3_ACCESS_KEY_ID=key -e S3_SECRET_ACCESS_KEY=secret -e S3_BUCKET=my-bucket -e S3_PATH=backup -e ES_REPOSITORY=dbname -e ES_USER=user -e ES_PASSWORD=password -e ES_HOST=localhost treksler/elasticsearch-snapshot-s3
```

Docker Compose:
```yaml
elasticsearch-snapshot-s3:
  image: treksler/elasticsearch-snapshot-s3
  environment:
    SCHEDULE: '@daily'
    S3_REGION: region
    S3_ACCESS_KEY_ID: key
    S3_SECRET_ACCESS_KEY: secret
    S3_BUCKET: my-bucket
    S3_PATH: backup
    ES_REPOSITORY: dbname
    ES_USER: user
    ES_PASSWORD: password
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

