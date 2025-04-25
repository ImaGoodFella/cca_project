#!/bin/bash

set -e

# kops create -f part2a.yaml
kops update cluster part2a.k8s.local --yes --admin
kops validate cluster --wait 10m


