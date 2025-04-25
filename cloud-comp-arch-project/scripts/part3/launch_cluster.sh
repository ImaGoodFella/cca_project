#!/bin/bash

set -e

# kops create -f part3.yaml
kops update cluster part3.k8s.local --yes --admin
kops validate cluster --wait 10m


