#!/usr/bin/env python3
"""Sign a development build, or use an explicitly configured local identity."""
import os
import subprocess

identity = os.environ.get("HIDECELL_SIGNING_IDENTITY", "-")
args = ["codesign", "--force", "--sign", identity]
if identity == "-":
    args += ["--timestamp=none"]
    print("Development-only ad hoc signing; permissions may need renewal after updates.")
else:
    args += ["--options", "runtime", "--timestamp"]
args += ["Hidecell.app"]
subprocess.run(args, check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", "Hidecell.app"], check=True)
