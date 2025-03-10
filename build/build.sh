#!/bin/bash

REPO="newsnowlabs/dockside"
DOCKERFILE="Dockerfile"
TAG_DATE="$(date -u +%Y%m%d%H%M%S)"
BUILDER=buildkit
PLATFORMS_DEFAULT_DEPOT="linux/amd64,linux/arm64,linux/arm/v7"
DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..

usage() {
  echo "$0: [[--stage <stage>] [--tag <tag>] [--theia <version>]] [--push|--load] [--no-cache] [--force-rm] [--progress-plain] [--repo <repo>] [--builder [depot|buildx|buildkit]] [--platforms <platforms>] | [--clean] | [--list]" >&2
  exit
}

push() {
  [ -z "$PUSH" ] && return
  
  for t in ${TAGS[@]}
  do
    docker push $t
  done
}

list() {
  local FILTERS="--filter=reference=$REPO "
  
  docker image ls $FILTERS "$@"
}

clean() {
  local IMAGES=$(list -q | sort -u)
  [ -z "$IMAGES" ] && return
  docker rmi -f $IMAGES
}

parse_commandline() {
  local opt
  local val

  while [ "$#" -gt 0 ]
  do
    case "$1" in
      --*=*) opt="${1%%=*}"; val="${1#*=}"; shift; ;;
        --*) opt="$1"; val=""; shift; ;;
          *) break; ;;
    esac

    case "$opt" in
      --stage|--target) [ -z "$val" ] && val="$1" && shift; STAGE="$val"; continue; ;;
                 --tag) [ -z "$val" ] && val="$1" && shift; TAGS+=("$REPO:$val"); continue; ;;
                --repo) [ -z "$val" ] && val="$1" && shift; REPO="$val"; continue; ;;
            --progress) [ -z "$val" ] && val="$1" && shift; PROGRESS="$val"; continue; ;;
               --theia) [ -z "$val" ] && val="$1" && shift; THEIA_VERSION="$val"; continue; ;;

             --builder) [ -z "$val" ] && val="$1" && shift; BUILDER="$val"; continue; ;;
           --platform*) [ -z "$val" ] && val="$1" && shift; PLATFORMS="$val"; continue; ;;
	    
            --no-cache) NO_CACHE="1"; continue; ;;
            --force-rm) FORCE_RM="1"; continue; ;;
      --progress-plain) PROGRESS="plain"; continue; ;;
      
               --clean) clean; exit 0; ;;
           --list|--ls) list "$@"; exit 0; ;;
	 
                --push) PUSH="1"; ;;
                --load) LOAD="1"; ;;
	      
             -h|--help) usage; ;;
                     *) break; ;;
    esac
  done
}

build_env() {
  TAG_DATE="$(date -u +%Y%m%d%H%M%S)"

  if [ -z "${TAGS[0]}" ]; then
    if [ -n "$STAGE" ] && [ "$STAGE" != "production" ]; then
      # If no --tag <tag> provided, and --stage <stage> is provided and <stage> != "production", then use the stage for a tag
      TAGS+=("$REPO:$STAGE")
    else
      # If no --tag <tag> provided and no --stage <stage> is provided, then tag with 'latest'
      TAGS+=("$REPO:latest")
    fi
  fi

  for t in ${TAGS[@]}
  do
    DOCKER_OPTS_TAGS+=" --tag $t"
  done

  DOCKER_OPTS=()
  DOCKER_OPTS+=("--label=com.newsnow.dockside.build.date=$TAG_DATE")
  DOCKER_OPTS+=("--build-arg=OPT_PATH=/opt/dockside")

  [ -n "$NO_CACHE" ] && DOCKER_OPTS+=("--no-cache")
  [ -n "$FORCE_RM" ] && DOCKER_OPTS+=("--force-rm")
  [ -n "$PULL" ] && DOCKER_OPTS+=("--pull")
  [ -n "$STAGE" ] && DOCKER_OPTS+=("--target=$STAGE")
  [ -n "$PROGRESS" ] && DOCKER_OPTS+=("--progress=$PROGRESS")
  [ -n "$TAG" ] && DOCKER_OPTS+=("--label" "com.newsnow.dockside.build.tag=$TAG")
  
  if [ -n "$PLATFORMS" ]; then
    DOCKER_OPTS+=("--platform=$PLATFORMS")
  elif [ "$BUILDER" = "depot" ]; then    
    DOCKER_OPTS+=("--platform=$PLATFORMS_DEFAULT_DEPOT")
  fi
}

parse_commandline "$@"

build_env

[ -z "$DOCKER_BUILDKIT" ] && DOCKER_BUILDKIT=1
export DOCKER_BUILDKIT

echo "$0: Changing directory to '$DIR'" >&2
cd $DIR || exit 1

case "$BUILDER" in

  buildkit)
  
    # Build using Docker Build (https://docs.docker.com/build/)

    if [[ "$PLATFORMS" =~ , ]]; then
      echo "$0: Error, --platforms=$PLATFORMS but must use --platforms=<platform> with only one platform at a time, with the '$BUILDER' builder; try changing builder or specifying only one platform; aborting" >&2
      exit -1
    fi

    docker build "${DOCKER_OPTS[@]}" $DOCKER_OPTS_TAGS -f "$DOCKERFILE" . || exit -1
    [ "$PUSH" == "1" ] && push
    ;;

  buildx)
  
    # Build using Docker Buildx (https://github.com/docker/buildx)

    [ "$PUSH" == "1" ] && DOCKER_OPTS+=("--push")
    [ "$LOAD" == "1" ] && DOCKER_OPTS+=("--load")
    
    docker buildx build "${DOCKER_OPTS[@]}" $DOCKER_OPTS_TAGS -f "$DOCKERFILE" . || exit -1
    ;;

  depot)
  
    # Build using Depot (https://depot.dev/), for building Docker images faster and smarter, in the cloud.

    [ "$PUSH" == "1" ] && DOCKER_OPTS+=("--push")
    [ "$LOAD" == "1" ] && DOCKER_OPTS+=("--load")

    if [ -z "$(which depot)" ]; then
       echo "$0: Error, depot CLI not installed (see https://depot.dev/), aborting" >&2
       exit -1
    fi
    depot build "${DOCKER_OPTS[@]}" $DOCKER_OPTS_TAGS -f "$DOCKERFILE" . || exit -1
    ;;

  *)
    echo "$0: Error, unknown builder '$BUILDER', aborting." >&2
    exit -1
    ;;

esac

exit 0