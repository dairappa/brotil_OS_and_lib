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

## Nodeの依存関係はどこに書かれているか

apt版では、`nodejs`パッケージ自体にはBrotliへの依存が書かれていない。
Node本体は`libnode109`という共有ライブラリにあり、そちらに`Depends: libbrotli1 (>= 1.0.0)`と書かれている。

公式バイナリ（nodejs.org、nvm、公式Dockerイメージ）には、依存関係としての記載が無い。
Brotliはソースツリーの`deps/brotli`を一緒にビルドして取り込んだ部品という扱いで、手がかりは`process.versions.brotli`と、配布物の`LICENSE`にあるbrotliの項だけである。

Brotliは`zlib`モジュールに組み込まれた機能なので、`package.json`や`package-lock.json`には出てこない。
そのため`npm audit`、Dependabot、`npm sbom`の対象外である。

## 脆弱性スキャナ（Trivy）で検知できる範囲

Trivy 0.76.2（公式Dockerイメージ`aquasec/trivy`）で各イメージをスキャンした。
要約は[`results/trivy/summary.txt`](results/trivy/summary.txt)にある（2026-11-09時点のTrivy DB）。

| イメージ | 検知結果 |
|---|---|
| Ubuntu 24.04＋apt `nodejs` | 検知できる。`libbrotli1`、`libnode109`、`nodejs`がOSパッケージとして出て、Node本体のCVE（`CVE-2024-27983` HTTP/2 CONTINUATION DoSなど7件）も出た |
| Ubuntu 20.04＋古い`libbrotli1`（1.0.7-6build1） | 検知できる。`CVE-2020-8927`（Brotliのバッファオーバーフロー、修正版1.0.7-6ubuntu0.1）が出た |
| `node:22-slim`（公式） | Node本体は出ない。npmに付属するnpmパッケージだけが出る |
| `node:20.0.0-slim`（既知のCVEが多い古いNode） | Node本体のCVEは0件。67件の脆弱性はすべてnpm付属のパッケージ（`brace-expansion`、`tar`など） |
| Ubuntu＋公式nodeバイナリをコピーしただけ | Nodeの存在自体が出ない |
| `node:22-slim`＋npm `brotli` `brotli-wasm` | 検知できる。npmパッケージとして出る |
| `node:22-slim`＋npm `react-server-dom-webpack@19.0.0` | 検知できる。React2Shell（`CVE-2025-55182`、CRITICAL）などが出る |

Trivyで検知できるのは「OSパッケージ」と「npmパッケージ」だけである。
公式バイナリのNodeは、Node本体の脆弱性も、同梱しているBrotliやnghttp2の脆弱性も検知されない。

この部分は別の方法で管理する必要がある。

- `node -p process.versions`で、Node本体と同梱ライブラリ（`brotli`、`nghttp2`、`openssl`など）のバージョンを確認する
- Node公式のセキュリティリリースを追う
- ベースイメージのタグを最新に保つ

Vulsは未検証である。
仕組み上、OSパッケージは検知できるはずだが、パッケージ管理外の公式バイナリはCPEを手動で登録しない限り対象外と考えられる。

## CVE-2026-111497（HTTP2Shell/Node2Shell）での検証

CVE-2026-111497は、Google Brotliのデコーダ（`c/dec/decode.c`）の範囲外書き込みである。
影響バージョンはBrotli 1.0.3〜1.2.0で、修正版は1.0.10、1.1.1、1.2.1である。
細工したbr圧縮データで、認証なしにリモートからコード実行できる可能性があり（CRITICAL）、CISAのKEVにも登録されている。

修正前と修正後のイメージを用意し、Trivyでこのイメージを検知できるかを確かめた（`lab/cve-2026-111497.sh`）。
結果は[`results/cve-2026-111497/summary.txt`](results/cve-2026-111497/summary.txt)にある（2026-11-09時点のTrivy DB）。

| イメージ | 中身 | Trivyの検知 |
|---|---|---|
| `node:22.20.0-slim` | 修正前の公式Node | 検知されない |
| `node:24.10.0-slim` | 修正前の公式Node | 検知されない |
| `node:22-slim`（v22.23.4） | 現行の公式Node | 検知されない |
| Ubuntu 24.04＋apt `nodejs`、`libbrotli1=1.1.0-2build2` | 修正前のOSライブラリ | 検知される（`libbrotli1`、修正版1.1.0-2ubuntu0.1） |
| Ubuntu 24.04＋apt `nodejs`、`libbrotli1=1.1.0-2ubuntu0.1` | 修正済みのOSライブラリ | 検知されない（正しい） |
| `python:3.13-slim`＋pip `brotli==1.1.0` | 修正前のPythonパッケージ | 検知される（修正版1.2.1） |
| `python:3.13-slim`＋pip `brotli`（1.2.1） | 修正済みのPythonパッケージ | 検知されない（正しい） |

公式Nodeは、修正前のバージョンでも検知されなかった。
公式Nodeを使っている場合、CVEのスキャン結果だけでは、このCVEの影響を受けるかどうか判断できない。

また、`process.versions.brotli`は修正前のv22.20.0でも現行のv22.23.4でも`1.1.0`のままだった。
Nodeは修正をバックポートしていてもこの表示を変えないので、Brotliのバージョンではなく、Nodeのバージョンを公式のセキュリティリリース（2026年10月）と照らし合わせる必要がある。

apt版Nodeの場合、検知されるのは`libbrotli1`であって`nodejs`ではない。
apt版NodeはOSのライブラリを使うので、これで正しい。
`libbrotli1`を更新し、Nodeのプロセスを再起動すれば修正が効く。

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

Trivyで検知範囲を確認する（検証用イメージの作成、スキャン、要約まで行う）。

```bash
lab/trivy.sh
```

CVE-2026-111497の検知を確かめる。

```bash
lab/cve-2026-111497.sh
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
| `lab/trivy.sh` | 検証用イメージを作成し、Trivyでスキャンして要約する |
| `lab/cve-2026-111497.sh` | CVE-2026-111497の修正前と修正後のイメージを作成し、Trivyで検知できるか確かめる |
| `lab/trivy_summary.py` | TrivyのJSONからbrotli、node、react関連だけを抜き出す |
| `results/` | 実行結果の生ログ。`results/trivy/summary.txt`がTrivyの要約 |

## 未確認の点

- httpsでの`fetch()`の`Accept-Encoding`
- Vulsでの検知範囲
- 特定CVEのペイロードによる実際の再現
