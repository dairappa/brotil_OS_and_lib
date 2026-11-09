#!/bin/bash
cd /lab; : > ae.log
PY=${PY:-python3}; command -v $PY >/dev/null && $PY -I probe.py 2>&1
command -v node >/dev/null && node probe.js hello.br 2>&1
for b in $PY node; do p=$(command -v $b) && echo "[ldd $b] $(ldd $(readlink -f $p) | grep -i brotli | awk '{print $1}' | tr '\n' ' ' ; true)"; done
echo "[server] Accept-Encoding received: $(paste -sd'|' ae.log)"
echo "[dpkg brotli] $(dpkg -l 2>/dev/null | awk '/^ii.*brotli/{print $2"="$3}' | tr '\n' ' ')"
