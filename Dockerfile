# Eiscat tools image build
#
# Build tested with:
# TMPDIR=${HOME}/tmp/ podman build --format=docker --build-arg
#  MATLAB_RELEASE=r2023a --build-arg MATLAB_PRODUCT_LIST="MATLAB"
#  --build-arg LICENSE_SERVER="27000@licence" --build-arg
#  MW_CONTEXT_TAGS="MATLAB_PROXY:JUPYTER:MPM:V1" --build-arg
#  GIT_USER=<myname> --build-arg GIT_TOKEN=<secret>
# -t eiscat-tools-cfe .

# Run with
# podman run -v work:/home/jovyan/work --rm --name jupyter -p 8888:8888 eiscat-tools-cfe

#FROM jupyter/scipy-notebook AS base_jupyter_image
FROM jupyter/datascience-notebook AS base_jupyter_image
ARG LICENSE_SERVER
ENV MLM_LICENSE_FILE=${LICENSE_SERVER}

# Switch to root user
USER root
ENV DEBIAN_FRONTEND="noninteractive" TZ="Etc/UTC"

## Installing Dependencies for Ubuntu
# For MATLAB : Get base-dependencies.txt from matlab-deps repository on GitHub
# For mpm : wget, unzip, ca-certificates
# For MATLAB Integration for Jupyter : xvfb
ARG MATLAB_RELEASE
ARG MATLAB_PRODUCT_LIST

# List of MATLAB Dependencies for specified Ubuntu version MATLAB_RELEASE
ARG MATLAB_DEPS_REQUIREMENTS_FILE="https://raw.githubusercontent.com/mathworks-ref-arch/container-images/main/matlab-deps/${MATLAB_RELEASE}/ubuntu20.04/base-dependencies.txt"
ARG MATLAB_DEPS_REQUIREMENTS_FILE_NAME="matlab-deps-${MATLAB_RELEASE}-base-dependencies.txt"

# Install dependencies
## MATLAB versions older than 22b need libpython3.9 which is only present in the deadsnakes PPA on ubuntu:22.04
RUN wget ${MATLAB_DEPS_REQUIREMENTS_FILE} -O ${MATLAB_DEPS_REQUIREMENTS_FILE_NAME} \
    && apt-get update \
    && export isJammy=`cat /etc/lsb-release | grep DISTRIB_RELEASE=22.04 | wc -l` \
    && export needsPy39=`cat ${MATLAB_DEPS_REQUIREMENTS_FILE_NAME} | grep libpython3.9 | wc -l` \
    && if [[ isJammy -eq 1 && needsPy39 -eq 1 ]] ; then apt-get install -y software-properties-common && add-apt-repository ppa:deadsnakes/ppa ; fi \
    && xargs -a ${MATLAB_DEPS_REQUIREMENTS_FILE_NAME} -r apt-get install --no-install-recommends -y \
    unzip ca-certificates build-essential cmake gfortran \
    libfftw3-3 libfftw3-dev \
    && apt-get clean \
    && apt-get -y autoremove \
    && rm -rf /var/lib/apt/lists/* ${MATLAB_DEPS_REQUIREMENTS_FILE_NAME}

# Installing MATLAB Engine for Python
RUN apt-get update \
    && apt-get install --no-install-recommends -y python3-distutils \
    && apt-get clean \
    && apt-get -y autoremove \
    && rm -rf /var/lib/apt/lists/* \
    && cd /opt/matlab/extern/engines/python \
    && python setup.py install || true

# Run mpm to install MATLAB in the target location and delete the mpm installation afterwards
RUN wget -q https://www.mathworks.com/mpm/glnxa64/mpm && \ 
    chmod +x mpm && \
    ./mpm install \
    --release ${MATLAB_RELEASE} \
    --destination /opt/matlab \
    --products ${MATLAB_PRODUCT_LIST} && \
    rm -f mpm /tmp/mathworks_root.log && \
    ln -s /opt/matlab/bin/matlab /usr/local/bin/matlab

RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install --no-install-recommends -y \
    dbus-x11 xfce4 xfce4-panel xfce4-session xfce4-settings xorg xvfb xubuntu-icon-theme websockify \
    && apt-get clean \
    && apt-get -y autoremove \
    && chown -R $NB_UID:$NB_GID $HOME \
    && rm -rf /var/lib/apt/lists/*

# Install pithia tools
ARG GIT_USER
ARG GIT_TOKEN
RUN cd /opt && git clone https://${GIT_USER}:${GIT_TOKEN}@git.eiscat.se/cvs/guisdap9.git guisdap \
    && git clone https://${GIT_USER}:${GIT_TOKEN}@git.eiscat.se/cvs/remtg.git remtg \
    && cd /opt/guisdap && bash libinstall.sh \
    && ln -s /opt/guisdap/bin/guisdap /usr/local/bin/guisdap \
    && echo "content_disposition = on" >> /etc/wgetrc
COPY pkgs/*.m /opt/matlab/toolbox/local/
COPY pkgs/mrc /tmp
RUN cd /tmp && cat mrc >> /opt/matlab/toolbox/local/matlabrc.m && rm mrc

## jupyter-remote-desktop-proxy recommends TurboVNC for best compatibility
# Install TurboVNC (https://github.com/TurboVNC/turbovnc)
ARG TURBOVNC_VERSION=3.0.3
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc.deb \
     && apt-get install -y -q ./turbovnc.deb \
     # remove light-locker to prevent screen lock
     && apt-get remove -y -q light-locker \
     && rm ./turbovnc.deb \
     && ln -s /opt/TurboVNC/bin/* /usr/local/bin/


# Switch back to notebook user
USER $NB_USER
WORKDIR /home/${NB_USER}

# Install integration
RUN python -m pip install jupyter-remote-desktop-proxy
RUN python -m pip install jupyter-matlab-proxy
RUN python -m pip install madrigalWeb

# Fix an issue with TurboVNC: needs explicit display and port no
COPY scripts/__init__.py /opt/conda/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/

# RUN python -m pip install jupyterlab jupyter-dash jupyterlab-dash \
# jupyterlab_widgets "ipywidgets>=7,<8"
# RUN jupyter labextension install jupyterlab-dash
RUN python -m pip install jupyterlab jupyterlab_widgets ipywidgets

# Make JupyterLab the default environment
ENV JUPYTER_ENABLE_LAB="yes"
ARG MW_CONTEXT_TAGS
ENV MW_CONTEXT_TAGS=${MW_CONTEXT_TAGS}
