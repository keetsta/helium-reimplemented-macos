#!/bin/bash -eux

# Simple script for setting up all toolchain dependencies for building Helium on macOS

brew install ninja coreutils --overwrite

# Install Python dependencies from PyPI
pip3 install httplib2==0.22.0 requests pillow --break-system-packages
npm i -g appdmg@0.6.6
