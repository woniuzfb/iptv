FROM ubuntu:bionic

# remove sed command ?
RUN sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
  && apt-get update && apt-get install -y \
  autoconf \
  automake \
  build-essential \
  cmake \
  zlib1g-dev \
  libtool \
  pkg-config \
  texinfo \
  frei0r-plugins-dev \
  libopencore-amrnb-dev \
  libopencore-amrwb-dev \
  libtheora-dev \
  libvo-amrwbenc-dev \
  libxvidcore-dev \
  libssl-dev \
  libva-dev \
  libvdpau-dev \
  libxcb1-dev \
  libxcb-shm0-dev \
  libxcb-xfixes0-dev \
  flex \
  bison \
  libharfbuzz-dev \
  libfontconfig-dev \
  libfreetype6-dev \
  python3 \
  python3-pip \
  python3-setuptools \
  python3-wheel \
  ninja-build \
  doxygen \
  git \
  libxext-dev \
  libsndfile1-dev \
  libasound2-dev \
  curl \
  graphviz && rm -rf /var/lib/apt/lists/*

COPY build.sh /root/ffmpeg_sources/

VOLUME /root/ffmpeg_sources/
WORKDIR /root/ffmpeg_sources/
CMD /bin/bash
