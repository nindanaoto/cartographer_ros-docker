# Copyright 2016 The Cartographer Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM ros:kinetic

ARG CARTOGRAPHER_VERSION=0.3.0

# Xenial's base image doesn't ship with sudo.
RUN apt-get update && apt-get install -y sudo && rm -rf /var/lib/apt/lists/*

# First, we invalidate the entire cache if googlecartographer/cartographer has
# changed. This file's content changes whenever master changes. See:
# http://stackoverflow.com/questions/36996046/how-to-prevent-dockerfile-caching-git-clone
ADD https://api.github.com/repos/googlecartographer/cartographer/git/refs/heads/master \
    cartographer_ros/cartographer_version.json

# wstool needs the updated rosinstall file to clone the correct repos.
RUN echo "- git: {local-name: cartographer, uri: 'https://github.com/googlecartographer/cartographer.git'}\n- git: {local-name: cartographer_ros, uri: 'https://github.com/googlecartographer/cartographer_ros.git'}\n- git: {local-name: ceres-solver, uri: 'https://ceres-solver.googlesource.com/ceres-solver.git', version: '1.13.0'}" >> cartographer_ros/cartographer_ros.rosinstall 
COPY scripts/prepare_catkin_workspace.sh cartographer_ros/scripts/
RUN CARTOGRAPHER_VERSION=$CARTOGRAPHER_VERSION \
    cartographer_ros/scripts/prepare_catkin_workspace.sh

# rosdep needs the updated package.xml files to install the correct debs.
COPY cartographer_ros/package.xml catkin_ws/src/cartographer_ros/cartographer_ros/
COPY cartographer_ros_msgs/package.xml catkin_ws/src/cartographer_ros/cartographer_ros_msgs/
COPY cartographer_rviz/package.xml catkin_ws/src/cartographer_ros/cartographer_rviz/
COPY scripts/install_debs.sh cartographer_ros/scripts/
RUN cartographer_ros/scripts/install_debs.sh && rm -rf /var/lib/apt/lists/*

# Install proto3.
RUN /catkin_ws/src/cartographer/scripts/install_proto3.sh

# Build, install, and test all packages individually to allow caching. The
# ordering of these steps must match the topological package ordering as
# determined by Catkin.
COPY scripts/install.sh cartographer_ros/scripts/
COPY scripts/catkin_test_results.sh cartographer_ros/scripts/

COPY cartographer_ros_msgs catkin_ws/src/cartographer_ros/cartographer_ros_msgs/
RUN cartographer_ros/scripts/install.sh --pkg cartographer_ros_msgs && \
    cartographer_ros/scripts/install.sh --pkg cartographer_ros_msgs \
        --catkin-make-args run_tests && \
    cartographer_ros/scripts/catkin_test_results.sh build_isolated/cartographer_ros_msgs

RUN cartographer_ros/scripts/install.sh --pkg ceres-solver

RUN cartographer_ros/scripts/install.sh --pkg cartographer && \
    cartographer_ros/scripts/install.sh --pkg cartographer --make-args test

COPY cartographer_ros catkin_ws/src/cartographer_ros/cartographer_ros/
RUN cartographer_ros/scripts/install.sh --pkg cartographer_ros && \
    cartographer_ros/scripts/install.sh --pkg cartographer_ros \
        --catkin-make-args run_tests && \
    cartographer_ros/scripts/catkin_test_results.sh build_isolated/cartographer_ros

COPY cartographer_rviz catkin_ws/src/cartographer_ros/cartographer_rviz/
RUN cartographer_ros/scripts/install.sh --pkg cartographer_rviz && \
    cartographer_ros/scripts/install.sh --pkg cartographer_rviz \
        --catkin-make-args run_tests && \
    cartographer_ros/scripts/catkin_test_results.sh build_isolated/cartographer_rviz

COPY scripts/ros_entrypoint.sh /
# A BTRFS bug may prevent us from cleaning up these directories.
# https://btrfs.wiki.kernel.org/index.php/Problem_FAQ#I_cannot_delete_an_empty_directory
RUN rm -rf cartographer_ros catkin_ws || true
