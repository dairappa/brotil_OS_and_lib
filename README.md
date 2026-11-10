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
これらはOS側の更新では直らない。
OS側のライブラリの状態とは無関係に、同梱しているバージョンそのものが脆弱かどうかで影響が決まる。
Pillow 13.0.0が同梱する1.2.0はCVE-2026-111497の影響範囲に入っている（後述の再検証を参照）。

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
Nodeは修正をバックポートしていてもこの表示を変えないので、Brotliのバージョンではなく、Nodeのバージョンを公式のセキュリティリリースと照らし合わせる必要がある。

Node.js公式のアドバイザリ（[October 2026 Security Releases](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)、2026-10-21）では、次のように書かれている。

- 対象はNodeに同梱しているBrotliデコーダで、`node:zlib`で攻撃者が用意したbrデータを展開するとメモリ破壊につながる（high）
- 影響を受けるのは22.x、24.x、26.xである
- 修正版はv22.23.4、v24.22.1、v26.12.1である
- サポートが終了したバージョン（20.x以前、23.x、25.x）は修正されない

したがって、上の表の`node:22-slim`（v22.23.4）は修正済みで、`node:22.20.0-slim`と`node:24.10.0-slim`は影響を受ける。

apt版Nodeの場合、検知されるのは`libbrotli1`であって`nodejs`ではない。
apt版NodeはOSのライブラリを使うので、これで正しい。
`libbrotli1`を更新し、Nodeのプロセスを再起動すれば修正が効く。

## 再検証（2026-11-10）

ここまでの結論を、一次情報と追加の実機確認で検証し直した。
結果は[`results/verify/summary.txt`](results/verify/summary.txt)にある。

### 一次情報で裏付けが取れた点

- Node.js公式：対象は「Nodeに同梱しているBrotliデコーダ」で、22.x、24.x、26.xが影響を受ける。v22.23.4のリリースノートには`deps: brotli: cherry-pick 0ed4268a…`とあり、Brotliのバージョンを上げずに修正コミットだけを取り込んでいる
- Ubuntu公式（CVEページ）：`nodejs`は22.04以降で「not-affected」とされ、理由は「システムのbrotliを使うため」と書かれている。apt版NodeがOSの`libbrotli1`を使うという実験結果と一致する。20.04の`nodejs`は同梱のbrotliを使うため「Vulnerable」で、修正版は出ていない
- Ubuntu公式（USN-8956-1）：修正対象のバイナリパッケージは`brotli`、`libbrotli1`、`python3-brotli`で、24.04の修正版は1.1.0-2ubuntu0.1である

### 修正の有無をバイナリから見分ける

修正では、新しいエラーコード`BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH`が追加されている。
バイナリにこの文字列が含まれるかを見れば、バージョン表示が変わらなくても修正の有無が分かる（`lab/verify/marker.py`）。
攻撃データは使っていない。

| 対象 | 目印 |
|---|---|
| 公式Node 22.20.0、24.10.0 | なし（未修正） |
| 公式Node 22.23.4 | あり（修正済み） |
| pip `brotli` 1.1.0 | なし |
| pip `brotli` 1.2.1 | あり |
| Ubuntu 24.04 `libbrotli1`／`python3-brotli` 1.1.0-2build2 | なし |
| Ubuntu 24.04 `libbrotli1`／`python3-brotli` 1.1.0-2ubuntu0.1 | あり |
| pip Pillow 13.0.0同梱の`libbrotlidec` | **なし** |

Ubuntuの修正済み`libbrotli1`も、`BrotliDecoderVersion()`は1.1.0のままだった。
バージョンの数字では、修正の有無を判断できない。

### 新たに分かった点：pip版Pillowが未修正のBrotliを同梱している

最新のPillow 13.0.0のwheelは、Brotli 1.2.0のデコーダを同梱しており、修正の目印が無い。
Trivyでも検知されなかった。

ただし、PillowがBrotliを使うのは、FreeTypeがWOFF2フォントを読むときだけである。
信頼できないフォントファイルを`ImageFont`で読み込む処理が無ければ、攻撃経路にはならない。
上流では[python-pillow/Pillow#10337](https://github.com/python-pillow/Pillow/issues/10337)で、同梱Brotliを1.2.1へ上げる対応が求められている。

### その他の確認

- Ubuntuの`python3-brotli`はBrotliを内部に持つが、Trivyは修正前のバージョンを正しく検知した（ソースパッケージ`brotli`として照合される）
- Trivyを`--detection-priority comprehensive`にしても、修正前の公式Nodeは検知されなかった
- Express 5.3.0（body-parser 2.4.0）は、`Content-Encoding: br`のリクエストボディを自動で展開した。素の`http`サーバは展開しなかった（`lab/verify/express.js`）

### 結論の修正点

- 「同梱版はOS側の脆弱性の影響を受けない」という以前の記述は不正確だった。同梱しているバージョン自体が脆弱なら影響を受ける
- 「`package.json`に無くてもNode本体経由で影響を受ける」「公式NodeはTrivyで検知できない」という結論は、再検証でも変わらなかった

## 世の中の状況：更新していない環境はどれくらいあるか

2026-11-10時点の公開情報を調べた。
ここは実機での検証ではなく、各社の報告の引用である。

### 見逃しが広くあることを示すデータ

- Akamaiは、自社の観測で61%のネットワークに影響を受けるバージョンのNode.jsがあるとしている（[Akamai](https://www.akamai.com/blog/security-research/inside-node2shell-closer-look-cve-2026-111497)）
- Wizは、クラウド環境の91%に脆弱なリソースがあり、82%では外部に公開されたリソースにあるとしている。これは[Brandefense](https://brandefense.io/blog/node2shell-nodejs-brotli-rce-cve-2026-111497/)による二次引用で、Wiz自身の調査では確認していない
- サポートが終了したNode.js 20.x以前、23.x、25.xには修正が出ない。HeroDevsは20.20.2に脆弱なデコーダがあることを確認している（[HeroDevs](https://www.herodevs.com/blog-posts/cve-2026-111497-node2shell-node-js-brotli-rce)）

### 悪用の状況

- ELLIOがセンサーで攻撃通信を観測している（[ELLIO](https://ellio.tech/en/blog/node2shell-cve-2026-111497-rce-on-stock-nodejs-builds/)）
- CISAは2026-10-27に、悪用が確認された脆弱性の一覧（KEV）へ追加した（[Help Net Security](https://www.helpnetsecurity.com/2026/10/27/node2shell-broccoli2shell-vulnerability-cve-2026-111497/)）
- Impervaは、公式イメージ`node:24.22.0-slim`でコード実行を実証し、24.22.1では同じ入力が拒否されたとしている（[Cybersecurity News](https://cybersecuritynews.com/node2shell-vulnerability/)）

観測されているのは攻撃の試行である。
組織名が挙がった被害事例や、侵害に成功したと確認された事例は、調べた範囲では見つからなかった。

### 見逃しが起きやすい環境

この調査の結果と合わせると、次の環境で見逃しが起きやすい。

1. ベースイメージのタグを固定している。`FROM node:22.20.0-slim`のように固定していると、再ビルドしても古いままで、Trivyでも検知されない
2. `npm audit`やDependabotだけで管理している。Node本体は対象外なので、警告が出ない
3. サポート終了版を使い続けている。修正版が無いので、メジャーバージョンを上げるしかない
4. Node以外の同梱先がある。Bun（1.4.4より前）、.NET、Envoy、pip版Pillowなどにも同じBrotliが入っている（[Cycode](https://cycode.com/blog/node2shell-cve-2026-111497/)）

調べた解説記事はどれも「Node本体を上げる必要がある」とは書いている。
一方、「脆弱性スキャナでは公式Nodeが検知されない」ことに触れた記事は、検索では見つからなかった。

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
| `lab/verify/marker.py` | バイナリに修正の目印（`BLOCK_SWITCH`のエラーコード名）があるかを調べる |
| `lab/verify/ver.py` | 共有ライブラリの`BrotliDecoderVersion()`を表示する |
| `lab/verify/express.js` | Express 5と素のhttpサーバが、brのリクエストボディを展開するかを調べる |
| `lab/trivy_summary.py` | TrivyのJSONからbrotli、node、react関連だけを抜き出す |
| `results/` | 実行結果の生ログ。`results/trivy/summary.txt`がTrivyの要約 |

## 未確認の点

- httpsでの`fetch()`の`Accept-Encoding`
- Vulsでの検知範囲
- 特定CVEのペイロードによる実際の再現
