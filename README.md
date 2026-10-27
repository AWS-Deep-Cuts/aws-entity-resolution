このリポジトリは AWS Deep Cuts の、AWS Entity Resolution に関するハンズオンコンテンツです。

AWS Entity Resolutionの解説記事(Qiita)は[こちら](https://qiita.com/kenken38/items/25a78d5e0041ca2f1cd2)

# AWS Deep Cutsとは
AWS Deep Cutsは、AWS の最新のサービスやニッチな機能、または高度にアカデミックな知識を要求するサービスなど、多くの人が知らない 『隠れた名曲 = **Deep Cuts**』 を深くまで掘り下げる技術シリーズです。

このようなサービスはWeb情報も少なく、初学者は気軽にキャッチアップできないのが実情です。

そこで AWS Deep Cuts シリーズでは、**前提知識も含めた分かりやすいサービス解説** と **手順通りに進めれば誰でも再現できるハンズオン** を提供します！

# ハンズオンのゴール
このハンズオンでは、CRMの登録データ（`registration_data.csv`）と、営業部の見込み顧客リスト（`lead_list.csv`）を照合します。

[registration_data.csv](./hands-on/registration_data.csv)と[lead_list.csv](./hands-on/lead_list.csv)のデータを確認してください。`A001`の山田太郎さんと、`B001`の山田太郎さんは同一人物ですが、大文字小文字や電話番号のハイフンの有無という**表記ゆれ**があります。今回のハンズオンでは AWS Entity Resolution を利用して、この表記ゆれデータをエンティティ解決することを目指します！

# ハンズオン手順
以降の手順は、ハンズオン用に用意したAWSアカウントで実施してください。


### 認証について

スクリプトは [CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html) での実行を推奨します。CloudShell はマネジメントコンソールのサインイン情報をそのまま使うため、**IAM Identity Center (AWS SSO) 経由でサインインしている場合も追加設定なしで動作します**。

ローカル PC から実行する場合は、AWS CLI v2 で以下のいずれかを設定してから実行してください。

| 認証方式 | 事前に実行するコマンド |
| -- | -- |
| IAM Identity Center (AWS SSO) | `aws configure sso` → `aws sso login --profile <プロファイル名>` → `export AWS_PROFILE=<プロファイル名>` |
| `aws login`（コンソールの認証情報でサインイン） | `aws login` |
| IAM ユーザーのアクセスキー | `aws configure` |

スクリプトは最初に認証を確認し、失敗した場合は **原因（SSO セッション切れ・プロファイル名の誤り・一時キーの期限切れなど）と対処コマンド** を表示して停止します。成功すると、どのアカウント・どのユーザー/ロールで実行するかが表示されるので、意図したアカウントか確認してください。

## １．事前準備

AWS Entity Resolution は、入力データを AWS Glue のテーブルとして用意する必要があります。これらの事前作業は本ハンズオンの本質ではないため、スクリプト化されているものを利用します。

[CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html)で以下のコマンドを実行してください。

```bash
# このリポジトリをクローン
git clone https://github.com/AWS-Deep-Cuts/aws-entity-resolution
cd aws-entity-resolution/hands-on

# セットアップスクリプトの実行
bash ./setup.sh

# 以下の文言が表示されればセットアップ成功です
# ✅ セットアップが完了しました！
```

## ２．Schema mappingの作成

ここから実際に AWS Entity Resolution の設定をしていきます！
まずは、Glueテーブルのどの列が「名前」や「メールアドレス」に該当するのかをAWS Entity Resolutionに教える必要があります。これが Schema mapping です。

1. マネジメントコンソールから `AWS Entity Resolution` を開きます。

2. 左メニューから **スキーママッピング** を選び、スキーママッピングの作成画面に進みます。

3. スキーマ詳細設定画面で、以下の通りに入力します。

| 項目 | 設定値 |
| -- | -- |
| スキーママッピング名 | `registration-schema` |
| 作成方法 | AWS Glue からインポート |
| AWS Glue データベース | `aws_er_handson_db` |
| AWS Glue テーブル | `registration_data` |
| 一意の ID | `id` |
| 入力フィールド | `email, name, phone` |

4. 入力フィールドマッピングの設定画面で、以下の通りに入力します。

| 入力フィールド | 属性タイプ | マッチキー名 |
| -- | -- | -- |
| email | `Email address` | `Email address` |
| name | `Full name` | `Name` |
| phone | `Phone number` | `Phone` |

5. 同様の手順で、もう一つのテーブル(`lead_list`)用にも `lead-schema` を作成します。

## ３．Matching workflowの作成

続いて、名寄せのルールを作ります。今回は表記ゆれを吸収するために「**ファジーマッチング**」を試してみましょう。

1. マネジメントコンソールから `AWS Entity Resolution` を開きます。

2. 左メニューから **マッチングワークフロー** を選び、マッチングワークフローの作成画面に進みます。

3. マッチングワークフローの詳細設定画面で、以下の通りに入力します。

| 項目 | 設定値 |
| -- | -- |
| マッチングワークフロー名 | `fuzzy-matching-workflow` |

4. 「データ入力」の欄で、以下の通りに入力します。

| AWS リージョン | AWS Glue データベース | AWS Glue テーブル | スキーママッピング | データを正規化 |
| -- | -- | -- | -- | -- |
| 東京 | `aws_er_handson_db` | `registration_data` | `registration-schema` | o |
| 東京 | `aws_er_handson_db` | `lead_list` | `lead-schema` | o |

5. マッチング手法の設定画面で、以下の通りに入力します。

| 項目 | 設定値 |
| -- | -- |
| Resolution タイプ | ルールベースのマッチング |
| ルールタイプ | 詳細 |

6. マッチングルールの設定画面で、以下の通りに入力します。

| 項目 | 設定値 |
| -- | -- |
| ルール名 | `fuzzy_name_and_email` |
| ルール条件 | `Exact("Email address") AND Soundex(Name)` |

7. データ出力先の設定画面で、以下の通りに入力します。

| 項目 | 設定値 |
| -- | -- |
| データ出力場所 | `Amazon S3` |
| Amazon S3 の場所 | `s3://aws-er-handson-{ACCOUNT_ID}-{YYYYMMDD-HHMMSS}/output/` |

「作成して実行」を選択して、ワークフローを実行します。
（実行完了には数分かかります）

## ４．結果の確認

ステータスが完了になったら、S3の `output` フォルダに出力されたCSVファイルを確認してみましょう。

**【出力結果のイメージ】**

| id | MatchID | name | phone |
| --- | --- | --- | --- |
| A001 | **65096a2423c7e1822c63cf2004e1e512** | yamadataro | 8011112222 |
| B001 | **65096a2423c7e1822c63cf2004e1e512** | yamadataro | 080-1111-2222 |
| A002 | 44ee89ddcd5f4a79d7db65e1d103f55b | satohanako | 9022223333 |
| B002 | 7d34682bd789dcebf929992ac9d360c9 | suzukiichiro | 7033334444 |

大文字小文字やハイフンの違いという「表記ゆれ」を乗り越え、**山田太郎さんのA001とB001に、全く同じ `MatchID` が付与されています！** このように、AWS Entity Resolutionを使うと複雑なコードを書かずに、GUIのルール設定だけで精度の高いデータ統合（Customer 360の基盤作り）が実現できます。

## ５．後片付け

検証が終わったら、無駄な課金を防ぐためにリソースを削除しましょう。

CloudShellで以下のコマンドを実行することで、今回作成したリソースを綺麗に削除することができます！

```bash
cd aws-entity-resolution/hands-on
bash ./cleanup.sh

# 以下の文言が表示されればクリーンアップ成功です
# ✅ すべてのリソースの削除が完了しました！

cd ../..
sudo rm -rf aws-entity-resolution
```

# トラブルシューティング

| 表示・症状 | 主な原因 | 対処 |
| -- | -- | -- |
| IAM Identity Center (SSO) のセッションが切れているか... | SSO のアクセストークン失効 | `aws sso login --profile <プロファイル名>` |
| AWS の認証情報が見つかりません | ローカルで認証未設定 / `AWS_PROFILE` 未設定 | 上記「認証について」を参照 |
| 前回の setup.sh の設定ファイル(.setup_config)が残っています | setup.sh の再実行 | `bash ./cleanup.sh` を実行してから再度 setup.sh |
| AccessDenied（S3 / Glue） | 許可セット・IAM ポリシーの権限不足 | S3・Glue・Entity Resolution の権限を付与 |
| マッチングワークフロー作成時にサービスロールを作成できない | `PowerUserAccess` などの許可セットには IAM ロール作成権限 (`iam:CreateRole` など) が無い | IAM ロールを作成できる権限（`AdministratorAccess` など）で実施するか、管理者にサービスロールの作成を依頼 |
| setup.sh 実行したアカウント と 現在の認証情報のアカウント が異なります | cleanup.sh を別プロファイルで実行 | setup.sh 実行時と同じ `AWS_PROFILE` で実行 |
