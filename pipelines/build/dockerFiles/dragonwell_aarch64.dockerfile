ARG image

FROM $image

RUN \
    # Dragonewell 8 requires a dragonwell 8 BootJDK
    mkdir -p /opt/dragonwell; \
    wget https://github.com/alibaba/dragonwell8/releases/download/dragonwell-8.5.5_jdk8u275-b2/Alibaba_Dragonwell_8.5.5-FP1_Linux_aarch64.tar.gz; \
    tar -xf Alibaba_Dragonwell_8.5.5-FP1_Linux_aarch64.tar.gz -C /opt/; \
    mv /opt/jdk8u275-b2/ /opt/dragonwell8

ENV JDK7_BOOT_DIR="/opt/dragonwell8"