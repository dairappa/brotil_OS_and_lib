#!/bin/bash
S=./scen.sh
$S "S1 OSにlibbrotliのみ + pipでrequests(brotli無し)" ubuntu:24.04 "apt-get install -y -qq python3 python3-pip libbrotli1 && pip install -q --break-system-packages requests"
$S "S2 apt python3-requests (既定のRecommends込み)" ubuntu:24.04 "apt-get install -y -qq python3-requests"
$S "S3 apt python3-requests + python3-brotli" ubuntu:24.04 "apt-get install -y -qq python3-requests python3-brotli"
$S "S4 公式python:3.13-slim + apt python3-brotli + pip requests" python:3.13-slim "apt-get install -y -qq python3-brotli && pip install -q requests"
$S "S5 公式python:3.13-slim + pip requests brotli" python:3.13-slim "pip install -q requests brotli"
$S "S6 venv(--system-site-packagesなし) + apt python3-brotli" ubuntu:24.04 "apt-get install -y -qq python3-venv python3-brotli && python3 -m venv /v && /v/bin/pip install -q requests" 
$S "S7 venv --system-site-packages + apt python3-brotli" ubuntu:24.04 "apt-get install -y -qq python3-venv python3-brotli && python3 -m venv --system-site-packages /v && /v/bin/pip install -q requests"
$S "S8 apt nodejs (Ubuntu配布版)" ubuntu:24.04 "apt-get install -y -qq nodejs"
$S "S9 公式node:22-slim + apt libbrotli1" node:22-slim "apt-get install -y -qq libbrotli1"
