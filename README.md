# OSのBrotliとPython/Nodeの関係を実機で確かめる

## 目的

Linux環境（OS）そのものにBrotliライブラリ（`libbrotli1`）がインストールされているとき、次のどちらになるのかを実環境で確かめる。

- Python/Node側で明示的にインストールしなければ、プログラムからは使われない
- 何らかのルートで自動的に使われてしまう

Brotliの脆弱性の影響範囲を判断するための調査である。
特定のCVEの再現ではなく、「Brotliのコードが実行される経路」を確認している。

## 結論

**Python**：OSに`libbrotli1`があるだけでは使われない。
標準ライブラリにBrotliは無く、`brotli`/`brotlicffi`モジュールがimportできたときだけ有効になる。
ただし、意図せずimportできてしまう経路と、別ライブラリ経由でOSのlibbrotliを読み込む経路がある。

**Node**：npmで何も入れなくても、Brotliは常に有効である（`zlib`と`fetch`）。
OSのlibbrotliを使うかどうかは、Nodeの入手元で決まる。
apt版はOSのライブラリを動的リンクし、公式バイナリ（公式Dockerイメージ）はBrotliを静的に同梱している。

## 測定方法

1シナリオごとにクリーンなコンテナを用意し、`lab/run.sh`で次の4点を測った。

- `brotli`/`brotlicffi`がimportできるか
- urllib3/requests/Node `fetch`が送る`Accept-Encoding`
- 常に`Content-Encoding: br`で応答するテストサーバ（`lab/server.py`）への問い合わせで、応答が自動展開されるか
- プロセスにBrotliの共有ライブラリがロードされたか（`/proc/self/maps`）

実験環境はUbuntu 24.04のホスト上のDocker 29.9.2で、イメージは`ubuntu:24.04`、`python:3.13-slim`、`node:22-slim`である（2026-11-09時点）。

## 結果

| シナリオ | brotliの使用 | 読み込まれたもの |
|---|---|---|
| S1 apt `libbrotli1`のみ＋pip requests | 使われない（`gzip, deflate`のみ送信し、br応答は生バイトのまま） | なし |
| S2 apt `python3-requests`（既定のRecommends込み） | 使われない（`python3-brotli`はurllib3の*Suggests*で、自動では入らない） | なし |
| S3 apt `python3-requests`＋`python3-brotli`（システムPython） | 自動で使われる（`gzip, deflate, br`を送信し、自動展開） | dist-packagesの`_brotli.so` |
| S4 公式`python:3.13-slim`＋apt `python3-brotli`＋pip requests | 使われない（`/usr/local`版Pythonはdist-packagesを見ない） | なし |
| S5 公式`python:3.13-slim`＋pip `requests brotli` | 自動で使われる | wheel側の`_brotli.so` |
| S6 venv（既定設定）＋apt `python3-brotli` | 使われない | なし |
| S7 venv `--system-site-packages`＋apt `python3-brotli` | 自動で使われる | dist-packagesの`_brotli.so` |
| S8 apt `nodejs`（Ubuntu版v18.19.1） | 常に使われる | OSの`libbrotlidec/enc/common.so.1.1.0`（動的リンク） |
| S9 公式`node:22-slim`（OSに`libbrotli1`あり） | 常に使われる | OSのものは使わない（バイナリに静的同梱） |

生ログは[`results/results.txt`](results/results.txt)にある。
S3のログには`SETUP-FAILED`が出ているが、これはセットアップ後に付けた`ldd | grep brotli`が一致しなかった（＝OSのlibbrotliにリンクしていない）ためで、インストール自体は成功している。

## 自動的に使われてしまう経路

### 1. urllib3/requestsによる自動検出

`brotli`がimportできれば、コードに何も書かなくても`Accept-Encoding: br`を送り、応答を展開する（S3、S5、S7）。
次の場合、意図せずimportできる状態になり得る。

- システムPythonにapt版`python3-brotli`が入っている
- venvを`--system-site-packages`で作っている
- `.pth`ファイルでaptのdist-packagesをパスに追加している

実際、調査に使ったホストでは`/usr/local/lib/python3.13/site-packages/apt-dist-packages.pth`によって、`/usr/local`版Pythonがaptのdist-packagesを参照していた。

### 2. 別のCライブラリ経由でOSのlibbrotliを読み込む

[`results/deps.txt`](results/deps.txt)の結果（Ubuntu 24.04）では次のとおりだった。

- apt版Pillow：フォントを読むだけで、freetype経由でOSの`libbrotlidec.so.1.1.0`がロードされた
- pycurl：libcurl経由でOSのlibbrotliがロードされる。br応答の展開は`ACCEPT_ENCODING`を指定したときだけだった
- `libbrotli1`に依存するパッケージは多い。libcurl4、libfreetype6、libnode109（apt版Node）、apache2-bin、libsoup、libqt6network6などである

### 3. Nodeは常に有効

`zlib.brotliDecompress`と`fetch()`は、追加インストールなしで使える。
`fetch()`は、平文httpで`Accept-Encoding`に`br`を含めていない場合でも、br応答を自動展開した。
apt版NodeはOSのlibbrotliを使うので、`libbrotli1`の脆弱性がそのまま影響する。

## 予想外だった点

Ubuntu 24.04の`python3-brotli`は、OSの`libbrotli1`にリンクしていない。
`_brotli.so`のリンク先はlibcのみで、Brotliのコードを内部に持っている。
したがって、`libbrotli1`を更新しても`python3-brotli`は直らず、別途更新が必要である。

同様に、pipの`brotli` wheelとpip版Pillowは自前のlibbrotliを同梱している（Pillowのwheelは1.2.0）。
これらはOS側の更新では直らず、逆にOS側の脆弱性の影響も受けない。

## 影響範囲の確認方法

「OSにlibbrotliがあるか」ではなく、実際に動いているプロセスを見る。

```bash
grep -i brotli /proc/<pid>/maps
```

```bash
python -c "import brotli; print(brotli.__file__)"
```

```bash
node -p process.versions.brotli
```

```bash
ldd "$(which node)" | grep -i brotli
```

1つ目でOSのlibbrotliを動的に読み込んでいるかが分かる。
2つ目が成功すれば、urllib3/requestsはBrotliを自動で使う。
3つ目と4つ目で、Nodeが同梱版かOSのlibbrotliを使っているかが分かる。

## 再現手順

前提はDockerとpython3、nodeである。
`lab/hello.br`はテストサーバが返すbrotli圧縮済みデータで、次のコマンドで再生成できる。

```bash
node -e 'require("fs").writeFileSync("lab/hello.br", require("zlib").brotliCompressSync("HELLO-FROM-BROTLI"))'
```

テストサーバを起動する（127.0.0.1:8765）。

```bash
cd lab && python3 -I server.py hello.br &
```

全シナリオを実行する。

```bash
cd lab && ./all.sh | tee ../results/results.txt
```

依存関係と間接経路を調べる。

```bash
docker run --rm --network host -v "$PWD/lab:/lab" -e DEBIAN_FRONTEND=noninteractive ubuntu:24.04 bash /lab/deps.sh
```

HTTPSのみを通すプロキシの内側で実行する場合は、`HTTPS_PROXY`と`CA_BUNDLE`（CA証明書ファイルのパス）を環境変数で渡す。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `lab/server.py` | 常にbrotli圧縮で応答し、受け取った`Accept-Encoding`を`ae.log`に記録するテストサーバ |
| `lab/probe.py` | Python側の計測（import可否、urllib3/requests/urllib、ロード済みライブラリ） |
| `lab/probe.js` | Node側の計測（`process.versions`、`zlib`、`fetch`、ロード済みライブラリ） |
| `lab/run.sh` | コンテナ内で各probeと`ldd`、`dpkg`を実行する |
| `lab/scen.sh` | 1シナリオ分のコンテナを起動する |
| `lab/all.sh` | S1〜S9を順に実行する |
| `lab/deps.sh` | パッケージ依存と間接経路（Pillow、pycurl、curl）の調査 |
| `results/` | 実行結果の生ログ |

## 未確認の点

- httpsでの`fetch()`の`Accept-Encoding`
- 特定CVEのペイロードによる実際の再現
