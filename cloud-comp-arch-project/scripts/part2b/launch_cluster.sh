#!/bin/bash

set -e

kops create -f part2b.yaml
kops update cluster part2b.k8s.local --yes --admin
kops validate cluster --wait 10m


