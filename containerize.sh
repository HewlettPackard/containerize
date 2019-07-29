#!/usr/bin/env bash
#
# Copyright 2017-2019 Hewlett Packard Enterprise Development LP
#
set -e

# enable interruption signal handling
trap - INT TERM

show_help() {
    echo "Usage:"
    echo "    $0 [-f|file <file>] [-p|--publish] [-P|--publish-only] [-q|--quiet] [-l|--list] [-s|--scan] [-v|--verbose] [--no-pull] [-d|--dockerfile <dockerfile>] [-t|--tag-as-subdir]"
    echo "    $0 [-h|--help]"
}

sanitize() {
    echo $1 | sed -e 's/(//g' -e 's/#/__/g' -e 's/ /--/g' | tr '[:upper:]' '[:lower:]' | xargs
}

name_repo() {
    # lowercase goodness
    local REPO
    local top

    REPO=$(echo $DRONE_REPO | tr '[:upper:]' '[:lower:]' | xargs)
    if [ -z $REPO ] ; then
      REPO=$(git config --local remote.origin.url | sed -e 's/\.git$//' -e 's,//[^/]*/,,g' -e 's,.*:,,' -e 's#/$##' | tr '[:upper:]' '[:lower:]')
    fi
    if [ -n $REPO ] ; then
      top=$(git rev-parse --show-toplevel)
      if [ "$PWD" != "$top" ] ; then
        REPO="$REPO-$(basename $PWD)"
      fi
    fi
    if [ -z $REPO ] ; then
      REPO="$(basename $PWD)"
    fi
    REPO=$(sanitize $REPO )
    echo $REPO
}

name_version() {
    if [ $# -ne 1 ]; then
      echo "Internal Error: $0 requires 1 argument" 1>&2
    fi
    local dockerfile
    local version
    local extension
    dockerfile=${1:-""}

    if [ ! -z $DRONE_PULL_REQUEST ] ; then
      version=pr${DRONE_PULL_REQUEST}
    fi
    if [ -n "$CIRCLE_PULL_REQUEST" ] ; then
      version=pr${CIRCLE_PULL_REQUEST##*/}
    fi
    if [ -z $version ] ; then
      version=$(echo $DRONE_TAG | xargs)
    fi
    if [ -z $version ] ; then
      version=$(echo $CIRCLE_TAG | xargs)
    fi
    if [ -z $version ] && [ -n $DRONE_BRANCH ] ; then
      version=$(echo $DRONE_BRANCH | xargs)
    fi
    if [ -z $version ] ; then
      version=$(git branch | grep '\*' | awk '{print $2}')
    fi
    if [ -z $version ] ; then
      version="unknown"
    fi
    version=$(sanitize $version | sed -e 's/\//_/g')
    extension="$(echo $dockerfile | awk -FDockerfile. '{print $2}')"

    echo $version${extension:+"-$extension"}
}


get_tag() {
    local DOCKERFILE=${1:-Dockerfile}
    local REPO=$(name_repo)
    local VERSION=$(name_version $DOCKERFILE)
    local TAG=$REPO:$VERSION
    if [[ $TAG_AS_SUBDIR == true ]] && [[ $DOCKERFILE != Dockerfile ]] ; then
        VERSION=$(name_version Dockerfile)
        local EXTENSION=$(cut -f 2- -d '.' <<< $DOCKERFILE)
        local SANITIZE=$( sed -e 's/\//_/g' -e 's/\./_/g' <<< $(sanitize $EXTENSION))
        TAG=${REPO}-$SANITIZE:$VERSION
    fi

    echo $TAG
}

name_src_repo() {
    local SRC_REPO
    if [ ! -z $DRONE_REMOTE_URL ] ; then
      SRC_REPO=$DRONE_REMOTE_URL
    fi
    if [ -z $SRC_REPO ] ; then
      SRC_REPO=$(git config --local remote.origin.url)
    fi
    echo ${SRC_REPO:="unknown"}
}

name_git_describe() {
    local GIT_DESCRIBE_DEFAULT
    local GIT_DESCRIBE
    GIT_DESCRIBE_DEFAULT="not-a-repo"
    GIT_DESCRIBE=$(git describe --dirty --tags --long --abbrev=40 2>/dev/null || git describe --dirty --tags --long --abbrev=40 --all 2>/dev/null || echo $GIT_DESCRIBE_DEFAULT)
    if [ "$GIT_DESCRIBE" = "$GIT_DESCRIBE_DEFAULT" ] && [ -n "$DRONE_COMMIT_SHA" ] ; then
      GIT_DESCRIBE=$DRONE_COMMIT_SHA
    fi
    echo $GIT_DESCRIBE
}

# always return the bare SHA1 for a repo
get_git_sha() {
    local GIT_SHA
    GIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo)
    echo ${GIT_SHA}
}

build_image() {
    if [ $# -ne 2 ]; then
      echo "Internal Error: $0 requires 2 arguments" 1>&2
    fi
    local dockerfile
    local tag
    local pull
    dockerfile="$1"
    tag="$2"
    pull="--pull"

    if [ $PULL == false ]; then
      pull=
    fi

    docker build \
      --rm=true \
      $pull \
      --build-arg http_proxy=$http_proxy \
      --build-arg https_proxy=$https_proxy \
      --build-arg no_proxy=$no_proxy \
      --build-arg GITHUB_TOKEN=$GITHUB_TOKEN \
      --build-arg TAG="$tag" \
      --build-arg BUILD_DATE="$BUILD_DATE" \
      --build-arg GIT_DESCRIBE=$GIT_DESCRIBE \
      --build-arg GIT_SHA=$GIT_SHA \
      --build-arg SRC_REPO=$SRC_REPO \
      -f $dockerfile \
      --tag=$tag .
}

login() {
    if [ $# -lt 1 ] || [ $# -gt 2 ]; then
      echo "Internal Error: $0 requires 1-2 arguments" 1>&2
    fi
    local registry_info
    local repo
    local registry
    local secrets
    registry_info="$1"
    repo="$2"
    registry=$(echo "$registry_info" | jq -r .uri)

    secrets=$(echo "$registry_info" | jq -r .secrets)
    if [ "$secrets" = "null" ]; then
        echo "Warning: Not able to login to $registry. Registry may be insecure."
        return
    fi

    local EXPORTS
    local e
    local key
    local value
    local is_aws
    EXPORTS=$(echo "$secrets" | jq -r 'to_entries[] | .key + ":" + (.value | tostring)')
    for e in $EXPORTS; do
      key=$(eval echo $(echo "$e" | cut -d':' -f1 | sed -e 's/ /_/g' -e 's|/|_|g' -e 's/-/_/g' | tr '[:lower:]' '[:upper:]' | xargs))
      value=$(eval echo $(echo "$e" | cut -d':' -f2 | xargs))
      export "${key}"="${value}"
    done

    local region
    region=$(echo "$registry_info" | jq -r .region)
    local is_aws
    is_aws=$(echo "$registry_info" | jq -r .aws)
    if [ "$is_aws" = true ]; then
        login_aws_create_repo "$registry" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$repo" "$region"
    else
        login_reg_create_repo "$registry" "$DOCKER_USR" "$DOCKER_PW" "$repo"
    fi
}

login_reg() {
    if [ $# -ne 3 ]; then
      echo "Internal Error: $0 requires 3 argument" 1>&2
    fi
    local registry
    local docker_user
    local docker_pw
    registry="$1"
    docker_user="$2"
    docker_pw="$3"

    if [ -z "$registry" ] || [ -z "$docker_user" ] || [ -z "$docker_pw" ] ; then
      echo "Warning: One or more fields are missing for registry login. Disabling publish for $registry" 1>&2
      return 1
    fi

    echo "Attempt login to $registry"
    docker login -u "$docker_user" -p "$docker_pw" "$registry"
}

login_reg_create_repo() {
    if [ $# -ne 4 ]; then
      echo "Internal Error: $0 requires 4 argument" 1>&2
    fi
    local registry
    local docker_user
    local docker_pw
    local repo
    local login
    registry="$1"
    docker_user="$2"
    docker_pw="$3"
    repo="$4"

    if [ -z "$registry" ] || [ -z "$docker_user" ] || [ -z "$docker_pw" ] || [ -z "$repo" ] ; then
      echo "Warning: One or more fields are missing for registry login. Disabling publish for $registry" 1>&2
      return 1
    fi

    echo "Attempt login to $registry"
    login=$(docker login -u "$docker_user" -p "$docker_pw" "$registry")
    if [ $? -ne 0 ]; then
        return 1
    fi

    local auth
    local headers
    local exists
    local response_string
    local exists
    local http_code
    local response
    local errors
    local namespace
    local name
    local is_private
    local visibility
    local data
    local create
    local retry
    local max_retry
    auth=$(echo -n $docker_user:$docker_pw | base64)
    response_string="response_code="
    exists=$(curl -Ss -L -H Content-Type:application/json -H "Authorization: Basic $auth" -w "\n${response_string}%{http_code}\n" https://$registry/api/v0/repositories/$repo)
    http_code=$(echo "$exists" | grep "$response_string" | cut -d '=' -f 2)
    if [ "$http_code" -ne "200" ]; then
        # Make sure we have only 1 error for no repository
        response=$(echo "$exists" | grep -v "$response_string")
        errors=$(echo $response | jq '.errors[] | select (.code != "NO_SUCH_REPOSITORY")')
        if [ -n "$errors" ]; then
            echo "Error: Some errors encountered: $errors" 1>&2
            return 1
        fi
        # Add the missing repo
        namespace=${repo%%/*}
        name=${repo##*/}
        is_private=$(curl -XGET -L -sS -k https://github.hpe.com/api/v3/repos/$repo | jq -r '.private | false')
        visibility=$($is_private && echo private || echo public)
        data="{\"name\":\"$name\",\"visibility\":\"$visibility\"}"
        create=$(curl -Ss -L -H Content-Type:application/json -H "Authorization: Basic $auth" -w "\n${response_string}%{http_code}\n" -XPOST -d $data https://$registry/api/v0/repositories/$namespace)
        http_code=$(echo "$create" | grep "$response_string" | cut -d '=' -f 2)
        if [ "$http_code" -eq "200" ] || [ "$http_code" -eq "201" ]; then
            echo "Created $visibility repo '$registry:$repo'."
        else
            echo "Warning: Failed to create repo '$registry:$repo'." 1>&2
        fi
        # Wait for repo to exist
        http_code=1
        retry=0
        max_retry=8
        while [ "$http_code" -ne 200 ]; do
            exists=$(curl -Ss -L -H Content-Type:application/json -H "Authorization: Basic $auth" -w "\n${response_string}%{http_code}\n" https://$registry/api/v0/repositories/$repo)
            http_code=$(echo "$exists" | grep "$response_string" | cut -d '=' -f 2)
            retry=$(( $retry + 1 ))
            if [ "$retry" -ge "$max_retry" ]; then
              echo "Warning: Timed out waiting for repo '$registry:$repo' to be created." 1>&2
              break
            fi
        done
    fi
}

login_aws_create_repo() {
    if [ $# -ne 5 ]; then
      echo "Internal Error: $0 requires 5 argument" 1>&2
    fi
    local registry
    local key_id
    local key
    local repo
    local region
    local aws
    local login
    local retval
    registry="$1"
    key_id="$2"
    key="$3"
    repo="$4"
    region="$5"

    if [ -z $registry ] || [ -z $key_id ] || [ -z $key ] || [ -z $repo ] || [ -z $region ] ; then
      echo "Warning: One or more fields are missing for aws.ecr login. Disabling publish for $registry" 1>&2
      return 1
    fi

    local aws_acct_id=${registry%%\.*}
    login="$(aws ecr get-login --no-include-email --region $region --registry-ids $aws_acct_id | tr -d '\r')"
    echo "Attempt login to $registry"
    eval "$login"
    if [ $? -ne 0 ]; then
        return 1
    fi

    local repo_list
    local existing_registry
    local create
    local new_registry

    repo_list=$(aws ecr describe-repositories)
    # This allows for "registry" of 123456789012.dkr.ecr.us-west-1.amazonaws.com/user_id
    real_repo=$(cut -d '/' -f2- <<< $registry/$repo)
    existing_registry=$(echo "$repo_list" | jq -er --arg repo "$real_repo" '.repositories[] | select(.repositoryName == $repo) | .repositoryUri')
    if [ $? -gt 0 ]; then
        create=$(aws ecr create-repository --repository-name=$real_repo)
        new_registry=$(echo "$create" | jq -r '.repository.repositoryUri')
        if [ "$new_registry" != "$registry"/"$repo" ]; then
            echo "Error: Created '$new_registry', expecting '$registry"/"$repo'" 1>&2
            exit 1
        fi
        export REPOSITORY=$repo
        set-read-for-aws-ecr.sh
        if [ $? -gt 0 ]; then
            echo "Error: Problem setting read-only policy on '$registry"/"$repo'" 1>&2
            exit 1
        fi
    fi
}

publish () {
    if [ $# -ne 3 ]; then
      echo "Internal Error: $0 requires 3 argument" 1>&2
    fi
    local registry_info
    local repo
    local version
    local registry
    local branch
    local version2
    registry_info="$1"
    repo="$2"
    version="$3"
    registry=$(echo "$registry_info" | jq -r .uri)

    export_image $repo:$version

    if [ -z "$registry" ]; then
        print "Warning: REGISTRY is not set" 1>&2
        return
    fi

    docker tag $repo:$version $registry/$repo:$version > /dev/null
    docker push $registry/$repo:$version > /dev/null && echo "Published $registry/$repo:$version"
    docker rmi $registry/$repo:$version > /dev/null || true

    branch="${version%%-*}"
    version2="${version/$branch/latest}"
    if [ "$branch" = "master" ] ; then
        docker tag $repo:$version $registry/$repo:$version2 > /dev/null
        docker push $registry/$repo:$version2 > /dev/null && echo "Published $registry/$repo:$version2"
        docker rmi $registry/$repo:$version2 > /dev/null || true
   fi
}

export_image() {
    if [ $# -ne 1 ]; then
      echo "Internal Error: $0 requires 1 argument" 1>&2
    fi
    local tag
    tag="$1"
    repo=${tag%%:*}

    if [ -d /build_output/docker ] ; then
      mkdir -p /build_output/docker/$repo/ > /dev/null
      OUT="$(mktemp)"
      docker save $tag | gzip > $OUT
      chmod +r $OUT > /dev/null
      mv $OUT /build_output/docker/$tag.tar.gz > /dev/null
    fi
}

# Registry file precedence
# 1. -f option
# 2. user reg file
# 3. project reg file
# 4. program reg file
USER_FILE="$(readlink -e .dev/registry.json || echo '' )"
PROJECT_FILE="$(readlink -e registry.json || echo '' )"
PROGRAM_FILE_DIR=$(dirname "$(readlink -e $0)")
PROGRAM_FILE="$(readlink -e $PROGRAM_FILE_DIR/registry.json || echo '' )"
FILE="${USER_FILE:-${PROJECT_FILE:-${PROGRAM_FILE:-}}}"
VERBOSE=false
TAG_AS_SUBDIR=false
build=true
publish=${PUBLISH:=false}
PULL=true
while [ $# -gt 0 ] ; do
    case $1 in
        -f|--file)
            shift
            FILE=$(readlink -m "$1")
            if [ ! -f $FILE ]; then
                echo "Error: File not found: '$FILE'" 1>&2
                exit 1
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --no-pull)
            PULL=false
            ;;
        -q|--quiet)
            QUIET=true
            ;;
        -l|--list)
            LIST=true
            ;;
        -s|--scan)
            SCAN=true
            ;;
        -d|--dockerfile)
            shift
            DOCKERFILE_OVERRIDE=$1
            ;;
        -p|--publish)
            publish=true
            ;;
        -P|--publish-only)
            publish=true
            build=false
            ;;
        -v|--verbose)
            set -x
            VERBOSE=true
            ;;
        -t|--tag-as-subdir)
            TAG_AS_SUBDIR=true
            ;;
        -1)
            DOCKERFILE_OVERRIDE=Dockerfile
            ;;
        *)
            echo "Error: Unknown argument: $1" 1>&2
            show_help
            exit 1
            ;;
    esac
    shift
done

if [[ $QUIET == true ]] ; then
    DOCKERFILE=${DOCKERFILE_OVERRIDE:=Dockerfile}
    TAG=$(get_tag $DOCKERFILE)
    echo $TAG
    exit 0
fi

# '|| echo' is to ignore missing Dockerfile.*
DOCKERFILES=${DOCKERFILE_OVERRIDE:-$(ls Dockerfile Dockerfile.* 2>/dev/null || echo )}
if [[ $LIST == true ]] ; then
    for DOCKERFILE in $DOCKERFILES; do
        TAG=$(get_tag $DOCKERFILE)
        echo $TAG
    done
    exit 0
fi

# Not doing a publish on pull_request
if [ "$publish" = true ] && ([ "${DRONE_EVENT}" = "pull_request" ] || [ "${DRONE_BUILD_EVENT}" = "pull_request" ]) ; then
    echo "Warning: Publish is disabled for pull requests" 1>&2
    publish=false
fi

SRC_REPO=$(name_src_repo)
GIT_DESCRIBE=$(name_git_describe)
GIT_SHA=$(get_git_sha)
BUILD_DATE=$(date -u)

if [ "$build" = true ] && [ -n "$FILE" ]; then
    REG_FILE=$(readlink -e "$FILE")
    echo "Registry info for login found in $REG_FILE" 1>&2
    for reg_info in $(jq -c .registries[] "$REG_FILE"); do
        for DOCKERFILE in $DOCKERFILES; do
            TAG=$(get_tag $DOCKERFILE)
            REPO=$(cut -d ':' -f 1 <<< $TAG)
            set +e +x
            if [[ $CIRCLECI = true ]] ; then
                login $reg_info $REPO
            fi
            $VERBOSE && set -x
            set -e
            break
        done
    done
fi

if [ "$build" = true ]; then

    if [ $(echo $DOCKERFILES | wc -w) -gt 1 ]; then
      echo "WARNING: Multiple Dockerfiles will be built: '"$DOCKERFILES"'. If building in CI this should be parallelized." 1>&2
    fi
    for DOCKERFILE in $DOCKERFILES; do
        TAG=$(get_tag $DOCKERFILE)

        build_image $DOCKERFILE $TAG

        echo "TAG = $TAG"
        if [[ "$DOCKERFILE" == "Dockerfile" ]] || [[ ! -z $DOCKERFILE_OVERRIDE ]]; then
           new_tag=$(cut -d ':' -f 1 <<< $TAG):latest
           docker tag $TAG $new_tag
           echo "ADDITIONAL_TAG = $new_tag"
        fi
        echo "BUILD_DATE = $BUILD_DATE"
        echo "GIT_DESCRIBE = $GIT_DESCRIBE"
        echo "GIT_SHA = $GIT_SHA"
        echo "SRC_REPO = $SRC_REPO"
        echo "--------------------------------------"
    done
fi

if [ "$SCAN" = true ] ; then
    DOCKERFILE=${DOCKERFILE_OVERRIDE:=Dockerfile}
    TAG=$(get_tag $DOCKERFILE)
    echo "Starting dockle scan for: $TAG"
    dockle --exit-code=1 $TAG
fi

if [ "$publish" = true ] && [ -n "$FILE" ]; then
    REG_FILE=$(readlink -e "$FILE")
    for reg_info in $(cat "$REG_FILE" | jq -c .registries[]); do
        for DOCKERFILE in $DOCKERFILES; do
            TAG=$(get_tag $DOCKERFILE)
            VERSION=$(cut -d ':' -f 2 <<< $TAG)
            REPO=$(cut -d ':' -f 1 <<< $TAG)

            # Since repo may differ per dockerfile if TAG_AS_SUBDIR is set
            set +e +x
            login $reg_info $REPO
            if [ $? -eq 0 ]; then
                $VERBOSE && set -x
                publish $reg_info $REPO $VERSION
            fi
        done
        $VERBOSE && set -x
        set -e
    done
fi
