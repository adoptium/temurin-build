ARG image

FROM $image

RUN \
    # Dragonewell 8 requires a dragonwell 8 BootJDK
    mkdir -p /opt/dragonwell8; \
    wget https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.5.5_jdk8u275-b2/Alibaba_Dragonwell_8.5.5-FP1_Linux_aarch64.tar.gz; \
    test $(md5sum Alibaba_Dragonwell_8.5.5-FP1_Linux_aarch64.tar.gz | cut -d ' ' -f1) = "ab80c4f638510de8c7211b7b7734f946" || exit 1; \
    tar -xf Alibaba_Dragonwell_8.5.5-FP1_Linux_aarch64.tar.gz -C /opt/dragonwell8 --strip-components=1

ENV JDK7_BOOT_DIR="/opt/dragonwell8"