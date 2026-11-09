#!/bin/bash
# usage: scen.sh <title> <image> <setup-cmd>
# 1シナリオ = 1クリーンコンテナ。setup実行後に run.sh で計測する。
# プロキシ環境では HTTPS_PROXY と CA_BUNDLE(CAファイルのパス) を設定して実行する。
D=$(dirname $(readlink -f $0))
echo "=================== $1  ($2)"
echo "    setup: $3"
EXTRA=()
if [ -n "$CA_BUNDLE" ]; then EXTRA+=(-v "$CA_BUNDLE:/ca.crt:ro" -e PIP_CERT=/ca.crt); fi
if [ -n "$HTTPS_PROXY" ]; then EXTRA+=(-e https_proxy=$HTTPS_PROXY -e HTTPS_PROXY=$HTTPS_PROXY -e no_proxy=127.0.0.1,localhost -e NO_PROXY=127.0.0.1,localhost); fi
docker run --rm --network host -v $D:/lab "${EXTRA[@]}" -e DEBIAN_FRONTEND=noninteractive $2 \
  bash -c "{ . /lab/aptfix.sh; $3; } >/tmp/setup.log 2>&1 || { echo SETUP-FAILED; tail -5 /tmp/setup.log; }; [ -f /v/bin/python3 ] && export PY=/v/bin/python3; unset https_proxy HTTPS_PROXY; /lab/run.sh"
