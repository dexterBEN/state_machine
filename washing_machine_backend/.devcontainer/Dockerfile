FROM mcr.microsoft.com/devcontainers/base:ubuntu

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y \
        ghdl \
        gtkwave \
        make \
        git \
        curl \
        wget \
        build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*