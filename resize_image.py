#!/usr/bin/python
import sys
import os

with open(sys.rgv[0], 'w') as f:
    f.seek((int(sys.argv[1]) * 1024 * 1024 * 1024) - 1, os.SEEK_SET)
    f.write(0)
