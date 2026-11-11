#!/usr/bin/env bash

# Workaround
#curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
#    -o /tmp/cloudflare-warp.pub

# repo set
curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo |
    run0 tee /etc/yum.repos.d/cloudflare-warp.repo

# refresh
run0 rpm-ostree refresh-md

echo "Run `rpm-ostree install cloudflare-warp -y --apply-live`"
