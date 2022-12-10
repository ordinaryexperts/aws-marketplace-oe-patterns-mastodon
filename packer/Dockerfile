FROM ubuntu:20.04

ENV IN_DOCKER=true
COPY ubuntu_2004_preinstall.sh /tmp/ubuntu_2004_preinstall.sh
RUN bash /tmp/ubuntu_2004_preinstall.sh
RUN rm -f /tmp/ubuntu_2004_preinstall.sh

COPY ubuntu_2004_appinstall.sh /tmp/ubuntu_2004_appinstall.sh
RUN bash /tmp/ubuntu_2004_appinstall.sh
RUN rm -f /tmp/ubuntu_2004_appinstall.sh

COPY ubuntu_2004_postinstall.sh /tmp/ubuntu_2004_postinstall.sh
RUN bash /tmp/ubuntu_2004_postinstall.sh
RUN rm -f /tmp/ubuntu_2004_postinstall.sh
