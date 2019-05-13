<!-- (c) Copyright 2017-2019 Hewlett Packard Enterprise Development LP -->

# Containerize (create-container)
Create, tag, and optionally publish a container for a GIT repository.

The container tag has the format:
 - `<name>:<version>`
 - image created from Dockerfile without extension has also tag "latest"

The container name is generated based on the following precedence:

 1. The GIT `<organization>/<repository>` of the 'origin' remote.
 1. The top level GIT directory
 1. The current directory

The container version is generated based on the following precedence:

 1. Drone tag
 1. Drone branch
 1. GIT branch
 1. The string `unknown`

## Requires
 1. One or more Dockerfiles in the project at the current working directory.
    1. File names match: `Dockerfile` and `Dockerfile.*`
    1. Dockerfiles SHOULD contain:
    ```
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
    ```
 1. Docker installed on the localhost.
 1. [Optional] Tags will prefer a git repository but can work without it.
 
 ## Registries
 1. Containerize will attempt to publish to the registries listed in a registry file, see [Registry File Precedence](#precedence)
 1. Containerize will attempt to create repositories for some versions of Dockerhub (e.g. HPE's version), and AWS ECR
    1. The Namespace for HPE's Dockerhub is required to exist prior to running this utility 

### <a name="precedence"></a>Registry File Precedence
 1. The `-f <file>` command line option
 1. A user registry file: `<project_dir>/.dev/registry.json`
    1. Be sure to add `.dev/` to the project `.gitignore` file.
 1. A project registry file: `<project_dir>/registry.json`
 1. A program registry file in the docker image for containerize
 
### Registry File Format
Follow this example showing an unsecure private registry, a secure private registry, a secure aws ec2 registry: [registry.json](./registry.json)`

## Usage

### Options
 - `containerize.sh` : Will build a container image
 - `containerize.sh --publish`: Will build and publish a container image 
 - `containerize.sh -q|--quiet` : Will only print the tag `<name>:<version>`

### CLI/bash
 1. Get the containerize image:
    1. Build it from source: `./containerize.sh`
    1. Pull from registry: `docker pull containerize:latest`
 1. `cd <project_dir>`
 1. `docker run --init --rm --workdir="$PWD" -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD":"$PWD" -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY -e http_proxy -e https_proxy -e no_proxy containerize`

### Drone
```
clone:
  tags: true
build:
  create-container:
    image: picasso/containerize:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    commands:
      - containerize.sh --publish
```
