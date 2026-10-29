#!/usr/bin/env python3
"""Has the lab fallen behind? Run weekly by .github/workflows/upstream.yml.

Compares what the lab installs with what's current:

- Kubernetes: the newest minor the README installs or upgrades to (from its
  pkgs.k8s.io repository lines). Fails once that minor is out of upstream
  support (older than the newest three); a newer minor alone is a notice.
- Calico: the version in the README's manifest URL. A newer release is a notice.
- Ubuntu: the cloud image in cka-builder.tf. Fails if it isn't a supported LTS;
  a newer LTS is a notice.

Dependabot keeps the Terraform provider and module current, so they aren't
checked here. Standard library only.
"""

import json
import os
import re
import sys
import urllib.request

README = "README.md"
TERRAFORM = "cka-builder.tf"

problems = []


def fetch(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": "cka-d-upstream-check", **(headers or {})})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode()


def notice(msg):
    print(f"::notice::{msg}")


def fail(msg):
    print(f"::error::{msg}")
    problems.append(msg)


def minor(version):
    return int(version.lstrip("v").split(".")[1])


readme = open(README, encoding="utf-8").read()
terraform = open(TERRAFORM, encoding="utf-8").read()

# Kubernetes
stable = fetch("https://dl.k8s.io/release/stable.txt").strip()
latest_minor = minor(stable)
used = [int(m) for m in re.findall(r"pkgs\.k8s\.io/core:/stable:/v1\.(\d+)/", readme)]
if not used:
    fail(f"The README doesn't install Kubernetes from pkgs.k8s.io (current release: {stable}).")
else:
    newest = max(used)
    if newest < latest_minor - 2:
        fail(f"The README's newest Kubernetes is 1.{newest}, which is out of support (current: {stable}).")
    elif newest < latest_minor:
        notice(f"Kubernetes 1.{latest_minor} is out; the README goes up to 1.{newest}.")
    else:
        print(f"Kubernetes: the README goes up to 1.{newest}, current is {stable}.")

# Calico
headers = {"Accept": "application/vnd.github+json"}
if os.environ.get("GH_TOKEN"):
    headers["Authorization"] = f"Bearer {os.environ['GH_TOKEN']}"
calico = json.loads(fetch("https://api.github.com/repos/projectcalico/calico/releases/latest", headers))["tag_name"]
m = re.search(r"projectcalico/calico/(v\d+\.\d+\.\d+)/", readme)
if not m:
    fail("The README has no Calico manifest URL to check.")
elif m.group(1) != calico:
    notice(f"Calico {calico} is out; the README uses {m.group(1)}.")
else:
    print(f"Calico: the README uses {calico}, the newest.")

# Ubuntu: supported LTS releases from Ubuntu's own release list
supported, dist = [], None
for line in fetch("https://changelogs.ubuntu.com/meta-release-lts").splitlines():
    if line.startswith("Dist: "):
        dist = line.split()[1]
    elif line.startswith("Supported: 1") and dist:
        supported.append(dist)
m = re.search(r"cloud-images\.ubuntu\.com/([a-z]+)/", terraform)
if not m:
    fail("cka-builder.tf has no Ubuntu cloud image URL to check.")
elif m.group(1) not in supported:
    fail(f"cka-builder.tf uses Ubuntu {m.group(1)}, which isn't a supported LTS ({', '.join(supported)}).")
elif supported and m.group(1) != supported[-1]:
    notice(f"Ubuntu {supported[-1]} is the newest LTS; cka-builder.tf uses {m.group(1)}.")
else:
    print(f"Ubuntu: cka-builder.tf uses {m.group(1)}, the newest LTS.")

sys.exit(1 if problems else 0)
