# Combined instructions from several places
# 1. Livebook repo: https://github.com/livebook-dev/livebook/blob/4d809ec0d6e9ca6ceb081caa4ba08edc9e6cb5d4/Dockerfile#L4
# 2. Chris McCord example: https://gist.github.com/chrismccord/59a5e81f144a4dfb4bf0a8c3f2673131
# 3. script to push livebook docker images to ghcr https://github.com/livebook-dev/livebook/blob/4d809ec0d6e9ca6ceb081caa4ba08edc9e6cb5d4/docker/build_and_push.sh
#
# And added modifications to check out particular livebook version from git
# 
# Notes
# - The livebook -cude images use an official image from NVIDIA as the base image, but 
#   I went with Chris McCords's gist anyway (even though it seems more fiddly), because
#   it uses the newer version of Ubuntu that fly.io recommends for their GPUs

# Set these to pick base image from hexpm in docker hub
ARG ELIXIR_VERSION=1.15.7
ARG ERLANG_VERSION=26.1.2
ARG UBUNTU_VERSION=jammy-20231004
ARG BASE_IMAGE=hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-ubuntu-${UBUNTU_VERSION}
ARG CUDA_VERSION=12-2


# Change these to suit your needs. Private repos won't work unless you set up git authentication in the build stage
ARG LIVEBOOK_GIT_REPO=https://github.com/livebook-dev/livebook
ARG LIVEBOOK_GIT_COMMIT=main

# Available packages here: https://github.com/orgs/livebook-dev/packages/container/package/utils
# Stage 1 (from livebook Dockerfile)
# Builds the Livebook release
FROM ${BASE_IMAGE} AS build

# From the livebook docker file
RUN apt-get update && apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
        build-essential git && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Jonas added this line to support specific version of livebook to be used
# This was killing me! Apparently args have to be redeclared inside a build stage to be used there!
ARG LIVEBOOK_GIT_REPO
ARG LIVEBOOK_GIT_COMMIT
RUN git clone -b ${LIVEBOOK_GIT_COMMIT} --single-branch ${LIVEBOOK_GIT_REPO} .

# This flag disables JIT behaviour that causes a segfault under QEMU.
# Note that we set this runtime flag only during the build stage and
# it has no impact when running the final image. See [1] for more
# information.
#
# [1]: https://github.com/erlang/otp/pull/6340
ENV ERL_FLAGS="+JMsingle true"

# Install hex and rebar
RUN mix local.hex --force && \
   mix local.rebar --force

# Build for production
ENV MIX_ENV=prod

# Install mix dependencies
RUN mix do deps.get, deps.compile

# Compile and build the release
RUN mix do compile, release livebook

# Stage 2 (from livebook Dockerfile)
# Prepares the runtime environment and copies over the release.
# We use the same base image, because we need Erlang, Elixir and Mix
# during runtime to spawn the Livebook standalone runtimes.
# Consequently the release doesn't include ERTS as we have it anyway.
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
        # Runtime dependencies
        build-essential ca-certificates libncurses5-dev \
        # In case someone uses `Mix.install/2` and point to a git repo
        git \
        # Additional standard tools
        wget \
        # In case someone uses Torchx for Nx
        cmake && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*


# # [START] From Chris McCord https://gist.github.com/chrismccord/59a5e81f144a4dfb4bf0a8c3f2673131
RUN apt update -q && apt install -y ca-certificates wget && \
    wget -qO /cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /cuda-keyring.deb && apt update -q

# As above, need to pull argument in to scope in this stage
ARG CUDA_VERSION    

# install build dependencies
RUN apt update -y && apt-get install -y software-properties-common
RUN apt install -y git cuda-nvcc-${CUDA_VERSION} libcublas-${CUDA_VERSION} libcudnn8
RUN add-apt-repository ppa:rabbitmq/rabbitmq-erlang
RUN apt-get update -y && apt-get install -y elixir erlang-dev build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# set runner ENV
ENV SHELL=/bin/bash
ENV ERL_AFLAGS "-proto_dist inet6_tcp"
ENV MIX_ENV="prod"
ENV PORT="8080"
ENV XLA_TARGET="cuda120"
ENV MIX_HOME="/data/mix"
ENV MIX_INSTALL_DIR="/data/mix"
ENV BUMBLEBEE_CACHE_DIR="/data/cache/bumblebee"
ENV XLA_CACHE_DIR="/data/cache/xla"

# [END] From Chris McCord

# Run in the /data directory by default, makes for
# a good place for the user to mount local volume
WORKDIR /data

ENV HOME=/home/livebook
# Make sure someone running the container with `--user`
# has permissions to the home dir (for `Mix.install/2` cache)
RUN mkdir $HOME && chmod 777 $HOME

# Install hex and rebar for `Mix.install/2` and Mix runtime
RUN mix local.hex --force && \
    mix local.rebar --force

# Override the default 127.0.0.1 address, so that the app
# can be accessed outside the container by binding ports
ENV LIVEBOOK_IP 0.0.0.0

ENV LIVEBOOK_HOME=/data

# Copy the release build from the previous stage
COPY --from=build /app/_build/prod/rel/livebook /app

# Make release files available to any user, in case someone
# runs the container with `--user`
RUN chmod -R go=u /app
# Make all home files available (specifically .mix/)
RUN chmod -R go=u $HOME

CMD [ "/app/bin/livebook", "start" ]