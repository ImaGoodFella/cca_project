#!/bin/bash

set -e 

kubectl create -f memcache-t1-cpuset.yaml
kubectl expose pod some-memcached --name some-memcached-11211 \
  --type LoadBalancer --port 11211 \
  --protocol TCP
sleep 60
kubectl get service some-memcached-11211
