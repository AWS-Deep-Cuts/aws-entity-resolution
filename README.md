このリポジトリは AWS Deep Cuts の、AWS Entity Resolution に関するハンズオンコンテンツです。

# AWS Deep Cutsとは
AWS Deep Cutsは、AWS の最新のサービスやニッチな機能、または高度にアカデミックな知識を要求するサービスなど、多くの人が知らない 『隠れた名曲 = **Deep Cuts**』 を深くまで掘り下げる技術シリーズです。

このようなサービスはWeb情報も少なく、初学者は気軽にキャッチアップできないのが実情です。

そこで AWS Deep Cuts シリーズでは、**前提知識も含めた分かりやすいサービス解説** と **手順通りに進めれば誰でも再現できるハンズオン** を提供します！

# ハンズオンのゴール
このハンズオンでは、CRMの登録データ（`registration_data.csv`）と、営業部の見込み顧客リスト（`lead_list.csv`）を照合します。

[registration_data.csv](./hands-on/registration_data.csv)と[lead_list.csv](./hands-on/lead_list.csv)のデータを確認してください。`A001`の山田太郎さんと、`B001`の山田太郎さんは同一人物ですが、大文字小文字や電話番号のハイフンの有無という**表記ゆれ**があります。今回のハンズオンでは AWS Entity Resolution を利用して、この表記ゆれデータをエンティティ解決することを目指します！

# ハンズオン手順
以降の手順は、ハンズオン用に用意したAWSアカウントで実施してください。

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
