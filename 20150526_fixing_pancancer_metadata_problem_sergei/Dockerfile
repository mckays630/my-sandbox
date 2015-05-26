# Set the base image to Ubuntu
FROM ubuntu:14.04

# File Author / Maintainer
MAINTAINER Brian OConnor <boconnor@oicr.on.ca>

USER root

RUN apt-get -m update && apt-get install -y \
  apt-utils \
  tar \
  git \
  curl \
  wget \
  dialog \
  net-tools \
  tabix \
  build-essential \
  zlib1g-dev \
  samtools \
  libjson-perl

COPY data /root/data
COPY scripts /root/scripts
