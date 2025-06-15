#!/usr/bin/env bash
cluster_names=$(kind get clusters)
for cluster_name in $cluster_names; do $(kind delete cluster --name $cluster_name) ; done