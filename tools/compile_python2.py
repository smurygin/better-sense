"""Invoked only by CPython 2.7: compile without executing game imports."""
from __future__ import print_function
import imp
import json
import marshal
import struct
import sys

if sys.version_info[:2] != (2, 7) or sys.subversion[0] != 'CPython':
    raise SystemExit('CPython 2.7 is required for game-compatible bytecode')

with open(sys.argv[1], 'rb') as stream:
    jobs = json.load(stream)
for job in jobs:
    with open(job['source'], 'rb') as stream:
        source = stream.read()
    source = source.replace('{{VERSION}}', job['version'].encode('ascii'))
    code = compile(source, job['filename'], 'exec')
    with open(job['output'], 'wb') as stream:
        stream.write(imp.get_magic())
        stream.write(struct.pack('<I', 0))
        marshal.dump(code, stream)
