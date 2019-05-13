# Copyright 2017-2019 Hewlett Packard Enterprise Development LP
FROM docker:18.09.6-git

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
    sudo \
    tar \
    unzip

RUN pip3 install awscli --upgrade

COPY containerize.sh /usr/bin
COPY registry.json /usr/bin
COPY login.sh /usr/bin

ENTRYPOINT ["containerize.sh"]

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