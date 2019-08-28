# Copyright 2017-2019 Hewlett Packard Enterprise Development LP
FROM goodwithtech/dockle:v0.1.16 as dockle

FROM docker:19.03-git

RUN apk add --no-cache --update \
    bash \
    ca-certificates \
    coreutils \
    curl \
    gzip \
    jq \
    moreutils \
    openssh \
    python3 \
    tar \
    unzip

RUN pip3 install awscli --upgrade

COPY --from=dockle /usr/local/bin/dockle /usr/local/bin/dockle

COPY --from=docker.bintray.io/jfrog/jfrog-cli-go:1.26.1 /usr/local/bin/jfrog /usr/bin

COPY containerize.sh set-read-for-aws-ecr.sh /usr/bin/
COPY registry.json /usr/bin
COPY login.sh /usr/bin

ENTRYPOINT ["containerize.sh"]
HEALTHCHECK NONE

ARG TAG
ARG GIT_DESCRIBE
ARG GIT_SHA
ARG BUILD_DATE
ARG SRC_REPO
LABEL TAG=$TAG \
  GIT_DESCRIBE=$GIT_DESCRIBE \
  GIT_SHA=$GIT_SHA \
  BUILD_DATE=$BUILD_DATE \
  SRC_REPO=$SRC_REPO
