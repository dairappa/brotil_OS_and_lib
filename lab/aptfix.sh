# コンテナ内の apt 準備。HTTPSのみ通すプロキシ環境向けに、apt取得先をhttpsへ変更しCAを登録する
if [ -n "$HTTPS_PROXY" ]; then
  sed -i 's#http://#https://#g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null
fi
if [ -f /ca.crt ]; then
  echo 'Acquire::https::CAInfo "/ca.crt";' > /etc/apt/apt.conf.d/99ca
  export PIP_CERT=/ca.crt REQUESTS_CA_BUNDLE=/ca.crt
fi
apt-get update -qq
