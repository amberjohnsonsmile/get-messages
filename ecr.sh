#!/bin/bash
# Build docker image and upload to ECR repository
# Used in TravisCI so no crazy dependencies
# set -x for some debugging
set -e

function join_by { local IFS="$1"; shift; echo "$*"; }

# Default, required ENV vars
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:=us-east-1}"
export AWS_REGION="${AWS_REGION:=$AWS_DEFAULT_REGION}"
export AWS_ACCOUNT_NUMBER="${AWS_ACCOUNT_NUMBER:=264606497040}"

AWS_ECR_HOST="${AWS_ACCOUNT_NUMBER}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"

# Login to ECR via docker.
docker run -e AWS_DEFAULT_REGION -e AWS_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN --rm amazon/aws-cli ecr get-login-password | docker login --username AWS --password-stdin "$AWS_ECR_HOST"

# Usage: $0 [repository] <image_tag ...>
# The repo name is required to push to ECR. the current git rev is used as a primary unique key. additional tags can be specified (eg build number)
# Example: ecr.sh kubernetes-deploy-demo build_number
repo="${1:-affiliate-tools}"
fullrepo="${AWS_ECR_HOST}/${repo}"
tags=("${@:2}")

#get current git information
export GIT_REV="git-$(git describe --match="" --dirty="-$(date +%F-%H%M%S)" --always)"
remotetag="${fullrepo}:${GIT_REV}"

# Build and push image via docker
docker build -t "$fullrepo" -t "$remotetag" \
  --build-arg GIT_REV --build-arg TAGS="$(join_by , ${tags[@]})" \
  --build-arg NPM_REPO_LOGIN --build-arg GEM_REPO_LOGIN .

echo "Pushing image: ${remotetag}"
docker push "$remotetag"

# Now add custom tags to existing ECR image by re-putting just the manifest via ecr API
for t in ${tags[@]}; do
  remotetag="${fullrepo}:${t}"

  echo "Tagging image: $remotetag"
  docker tag "$fullrepo" "$remotetag"
  docker push "$remotetag"
done
