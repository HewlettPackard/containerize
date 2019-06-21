#!/bin/bash -e
# Copyright 2017-2019 Hewlett Packard Enterprise Development LP

show_help() {
    echo "Usage:"
    echo "    $0 [-p|profile <aws_profile>] [-a|--all] <aws-acct>*"
    echo "    $0 [-h|--help]"
}

SCRIPT_DIR=$(readlink -vf $(dirname $0))
TARGET_ACCOUNTS=${TARGET_ACCOUNTS//,/ }
PROFILE=
FILE=
ALL=false
POLICY_NAME=${POLICY_NAME:-"readonly-accounts-policy"}
while [ $# -gt 0 ] ; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--profile)
            shift
            PROFILE="--profile $1"
            ;;
        -a|--all)
            ALL=true
            ;;
        -v|--verbose)
            set -x
            ;;
        -f|--file)
            shift
            FILE="$1"
            ;;
        *)
            TARGET_ACCOUNTS="$TARGET_ACCOUNTS $1"
            ;;
    esac
    shift
done
echo "starting: $TARGET_ACCOUNTS"

if [ -n "$FILE" ]; then
  while IFS= read -r rawline
  do
    line=$(echo -e "$rawline" | cut -d '#' -f 1 | xargs)
    [[ $line = \#* ]] && continue
    [[ ${#line} -eq 0 ]] && continue
    targets+="$line "
  done < "$FILE"
  TARGET_ACCOUNTS=$(echo -e "$TARGET_ACCOUNTS $targets" | xargs)
fi

EXIT=0
if [ -z $REPOSITORY ] && [ $ALL = false ] ; then
  echo "REPOSITORY variable is required"
  EXIT=1
fi
if [ -z "$PROFILE" ] ; then
    if [ -z $AWS_ACCESS_KEY_ID ] ; then
      echo "AWS_ACCESS_KEY_ID variable is required"
      EXIT=1
    fi
    if [ -z $AWS_SECRET_ACCESS_KEY ] ; then
      echo "AWS_SECRET_ACCESS_KEY variable is required"
      EXIT=1
    fi
    if [ -z $AWS_DEFAULT_REGION ] ; then
      echo "AWS_DEFAULT_REGION variable is required"
      EXIT=1
    fi
fi
if [ -z "$TARGET_ACCOUNTS" ] ; then
  echo "TARGET_ACCOUNTS variable is required"
  EXIT=1
fi
if [ $EXIT -eq 1 ] ; then
  exit 1
fi

AWS="aws $PROFILE"

echo "Begin validation/correction of aws ecr policy"
TARGET_ACCOUNTS="$(printf ',\"%s\"' ${TARGET_ACCOUNTS[*]})"
TARGET_ACCOUNTS=${TARGET_ACCOUNTS:1}
NEW_POLICY=$(echo "
    {
      \"Sid\": \"$POLICY_NAME\",
      \"Effect\": \"Allow\",
      \"Principal\": {
      \"AWS\": [$TARGET_ACCOUNTS]
      },
      \"Action\": [
        \"ecr:GetDownloadUrlForLayer\",
        \"ecr:BatchGetImage\",
        \"ecr:BatchCheckLayerAvailability\",
        \"ecr:ListImages\",
        \"ecr:DescribeRepositories\",
        \"ecr:DescribeImages\"
      ]
    }")

REPOSITORIES=
if [ $ALL = true ]; then
    REPOSITORIES="$( $AWS ecr describe-repositories --output json | jq -r .repositories[].repositoryName )"
else
    REPOSITORIES="$REPOSITORY"
fi
for REPO in $REPOSITORIES; do
    CURRENT_POLICY=$( $AWS ecr get-repository-policy --output json --repository-name $REPO 2>&1 || true )
    NON_EXISTENT=$( echo $CURRENT_POLICY | grep -c RepositoryPolicyNotFoundException 2>&1 || true )
    if [ $NON_EXISTENT -gt 0 ] ; then
      echo "Repository $REPO has no policy currently set"
      BASE='{"policyText":"{\"Statement\":[]}"}'
    else
      BASE=$CURRENT_POLICY
    fi

    TARGET_EXISTS=$( echo $BASE | jq -cr .policyText  |jq -cr '.Statement[].Sid' | grep $POLICY_NAME 2>/dev/null || echo "")
    if [ -n "$TARGET_EXISTS" ] ; then
      POLICY_TEXT="$(echo $BASE | jq -cr .policyText | jq ".Statement=[.Statement[] | select(.Sid==\"$POLICY_NAME\") |= $NEW_POLICY]")"
    else
      POLICY_TEXT="$(echo $BASE | jq -cr .policyText | jq -c --argjson NEW $(echo $NEW_POLICY | jq -r '. | @json' ) '.Statement |= . + [$NEW]')"
    fi
    FINAL_COMPLETE=$(echo $BASE | jq --arg policy "$(echo $POLICY_TEXT | jq -r '. | @json')" '.policyText=$policy')
    echo "FINAL policy"
    echo "$FINAL_COMPLETE"
    $AWS ecr set-repository-policy --repository-name=$REPO --cli-input-json "$FINAL_COMPLETE"
    while [ 1 ]; do
      set +e
      CHECK_POLICY=$( $AWS ecr get-repository-policy --repository-name $REPO | jq -cr .policyText | jq -r '.Statement[].Sid' | grep -c $POLICY_NAME )
      set -e
      if [ $CHECK_POLICY -gt 0 ]; then
    break
      fi
      sleep .1
    done
done


