#!/usr/bin/env python
"""dials_integrate_bounded.py — run dials.integrate with an explicit memory ceiling.

Usage: dials_integrate_bounded.py <mem_limit_mb> [normal dials.integrate args...]
"""

import sys

requested_mb = int(sys.argv[1])
del sys.argv[1]

import dials.util.system as dsys

requested_bytes = requested_mb * 1024 * 1024
actual_bytes = dsys.memory_limit()  # real system/cgroup/rlimit-derived value

effective = min(requested_bytes, actual_bytes)
if requested_bytes > actual_bytes:
    print(
        f"Warning: requested memory ceiling ({requested_mb} MB) exceeds actual "
        f"available memory ({actual_bytes / 1e6:.0f} MB); using the lower value.",
        file=sys.stderr,
    )
dsys.MEMORY_LIMIT = effective

from dials.command_line.integrate import run

sys.exit(run())
