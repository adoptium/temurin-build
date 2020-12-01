ARG image

FROM $image

RUN yum update -y
RUN yum groupinstall "Development Tools" -y
RUN yum install wget -y
RUN curl -O https://ftp.gnu.org/gnu/gcc/gcc-9.2.0/gcc-9.2.0.tar.gz
RUN tar xzf gcc-9.2.0.tar.gz
WORKDIR /gcc-9.2.0
RUN ./contrib/download_prerequisites
WORKDIR /
RUN mkdir gcc-build
WORKDIR /gcc-build
RUN ../gcc-9.2.0/configure                           \
    --enable-shared                                  \
    --enable-threads=posix                           \
    --enable-__cxa_atexit                            \
    --enable-clocale=gnu                             \
    --disable-multilib                               \
    --enable-languages=all
RUN make -j 50