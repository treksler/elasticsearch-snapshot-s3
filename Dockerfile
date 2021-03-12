FROM  alpine:3.10
LABEL maintainer="Risto Treksler <risto78@gmail.com>"
ENV   ES_HOST='elasticsearch' \
      ES_PORT='9200' \
      ES_SCHEME='https' \
      ES_REPO='elasticsearch' \
      ES_REPO_FILE='' \
      ES_USER='' \
      ES_USER_FILE='' \
      ES_PASSWORD='' \
      ES_PASSWORD_FILE='' \
      S3_ACCESS_KEY_ID='' \
      S3_SECRET_ACCESS_KEY='' \
      S3_DEFAULT_REGION='ca-central-1' \
      S3_BUCKET='' \
      S3_IAM_ROLE='' \
      S3_ENDPOINT='' \
      S3_S3V4='no' \
      SCHEDULE='' \
      MAX_AGE='10y'
RUN   apk update \
      && apk add --no-cache \
          curl \
          jq \
          py-pip \
          gcc \
          libc-dev \
          python2-dev \
          libffi-dev \
          libressl-dev \
      && curl -L --insecure https://github.com/odise/go-cron/releases/download/v0.0.6/go-cron-linux.gz | zcat > /usr/local/bin/go-cron \
      && chmod u+x /usr/local/bin/go-cron \
      && pip install awscurl

COPY bin/* /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["snapshot.sh"]
