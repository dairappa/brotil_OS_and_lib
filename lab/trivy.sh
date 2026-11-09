#!/bin/bash
# Trivyで「どこまで検知できるか」を確かめる。
# 1) 検証用イメージを作成  2) Trivy(公式Dockerイメージ)でスキャン  3) brotli/node関連を要約
# プロキシ環境では HTTPS_PROXY と CA_BUNDLE を設定して実行する。
set -e
D=$(dirname $(readlink -f $0)); OUT=$D/../results/trivy; mkdir -p $OUT
CACHE=${TRIVY_CACHE:-$HOME/.cache/trivy-lab}; mkdir -p $CACHE
PX=(); [ -n "$HTTPS_PROXY" ] && PX+=(-e HTTPS_PROXY=$HTTPS_PROXY -e https_proxy=$HTTPS_PROXY)
CA=(); [ -n "$CA_BUNDLE" ] && CA+=(-v "$CA_BUNDLE:/ca.crt:ro" -e SSL_CERT_FILE=/ca.crt -e NODE_EXTRA_CA_CERTS=/ca.crt -e npm_config_cafile=/ca.crt)

build(){ # build <tag> <base> <cmd>
  docker image inspect t-$1 >/dev/null 2>&1 && return
  docker rm -f tmp-$1 >/dev/null 2>&1 || true
  docker run --name tmp-$1 --network host -v $D:/lab "${PX[@]}" "${CA[@]}" -e DEBIAN_FRONTEND=noninteractive $2 bash -c "$3; rm -f /etc/apt/apt.conf.d/99ca" >/dev/null
  docker commit tmp-$1 t-$1 >/dev/null; docker rm tmp-$1 >/dev/null; echo "built t-$1"
}
build aptnode    ubuntu:24.04  ". /lab/aptfix.sh && apt-get install -y -qq nodejs"
build npmbrotli  node:22-slim  "mkdir /app && cd /app && npm init -y >/dev/null && npm install -s brotli brotli-wasm"
build oldbrotli  ubuntu:20.04  ". /lab/aptfix.sh && apt-get install -y -qq --allow-downgrades libbrotli1=1.0.7-6build1"
build react2shell node:22-slim "mkdir /app && cd /app && npm init -y >/dev/null && npm install -s react@19.0.0 react-dom@19.0.0 react-server-dom-webpack@19.0.0"
if ! docker image inspect t-tarnode >/dev/null 2>&1; then  # 公式nodeバイナリをパッケージ管理外でコピーしただけのUbuntu
  docker create --name tmpn node:22-slim >/dev/null; docker cp tmpn:/usr/local/bin/node $OUT/.node-bin; docker rm tmpn >/dev/null
  docker create --name tmpt ubuntu:24.04 >/dev/null; docker cp $OUT/.node-bin tmpt:/usr/local/bin/node; docker commit tmpt t-tarnode >/dev/null; docker rm tmpt >/dev/null; rm $OUT/.node-bin
fi

IMAGES="t-aptnode t-oldbrotli node:22-slim node:20.0.0-slim t-tarnode t-npmbrotli t-react2shell"
for i in $IMAGES; do
  f=$(echo $i | tr ':/' '__')
  docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock -v $CACHE:/root/.cache -v $OUT:/out "${PX[@]}" "${CA[@]}" \
    aquasec/trivy:${TRIVY_VERSION:-latest} image -q --scanners vuln --list-all-pkgs -f json -o /out/$f.json $i
done
python3 -I $D/trivy_summary.py $OUT/*.json | tee $OUT/summary.txt
rm -f $OUT/*.json   # 生JSONは大きいので要約のみ残す
