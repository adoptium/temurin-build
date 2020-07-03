ARG image

FROM $image

# Install cuda headers https://github.com/eclipse/openj9/blob/master/buildenv/docker/mkdocker.sh#L586-L593
RUN mkdir -p /usr/local/cuda-9.0/nvvm
COPY --from=nvidia/cuda:9.0-devel-ubuntu16.04 /usr/local/cuda-9.0/include /usr/local/cuda-9.0/include
COPY --from=nvidia/cuda:9.0-devel-ubuntu16.04 /usr/local/cuda-9.0/nvvm/include /usr/local/cuda-9.0/nvvm/include

ENV CUDA_HOME="/usr/local/cuda-9.0"