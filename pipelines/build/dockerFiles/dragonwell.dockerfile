ARG image

FROM $image

RUN mkdir -p /opt/dragonwell
COPY --from=dragonwelljdk/build_jdk:8u /opt/dragonwell_8.3.3_boot /opt/dragonwell8
COPY --from=dragonwelljdk/build_jdk:11u /opt/dragonwell_11.0.5.1 /opt/dragonwell11
# COPY --from=joeylee97/dragonwell:v1 /opt/dragonwell/dragonwell8 /root/jenkins/workspace/build-scripts/jobs/jdk8u/jdk8u-linux-x64-dragonwell/workspace/dragonwell8
# COPY --from=joeylee97/dragonwell:v1 /opt/dragonwell/.gradle /root/.gradle
# COPY --from=joeylee97/dragonwell:v1 /root/buildfiles /root/buildfiles

ENV \
    JDK8_BOOT_DIR="/opt/dragonwell8" \
    JDK11_BOOT_DIR="/opt/dragonwell11"