#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# AWS 認証チェック (CloudShell / IAM Identity Center / aws login / アクセスキー に対応)
source "${SCRIPT_DIR}/aws_auth_check.sh"

# 各種パラメータの設定
readonly AWS_REGION=ap-northeast-1
# プロファイルにリージョンが無い場合 (Identity Center のプロファイルなど) でも動くように固定
export AWS_REGION AWS_DEFAULT_REGION="${AWS_REGION}"

aws_auth_check "${AWS_REGION}" || exit 1
readonly AWS_ACCOUNT_ID

fail() {
  echo "❌ Error: $1" >&2
  aws_permission_hint
  exit 1
}

# 前回の setup.sh の設定が残っている場合は、リソースの二重作成を防ぐため停止
if [[ -f .setup_config ]]; then
  echo "❌ Error: 前回の setup.sh の設定ファイル(.setup_config)が残っています。" >&2
  echo "   作成済みのリソースを削除する場合は bash ./cleanup.sh を実行してから、再度 setup.sh を実行してください。" >&2
  exit 1
fi
readonly S3_BUCKET_NAME=aws-er-handson-${AWS_ACCOUNT_ID}-$(date +%Y%m%d-%H%M%S)
readonly GLUE_DB_NAME=aws_er_handson_db

# パラメータを設定ファイルに保存
cat > .setup_config << EOF
SETUP_AWS_PROFILE=${AWS_PROFILE:-default}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
GLUE_DB_NAME=${GLUE_DB_NAME}
EOF

# CSVファイルの存在確認
for csv_file in registration_data.csv lead_list.csv; do
  if [[ ! -f "${csv_file}" ]]; then
    echo "❌ Error: ${csv_file}が見つかりません。" >&2
    exit 1
  fi
done

# S3バケットの作成
if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "ℹ️  S3バケットは既に存在します: ${S3_BUCKET_NAME}"
else
  aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}" || fail "S3バケットの作成に失敗しました。"
  echo "✅ S3バケットを作成しました: ${S3_BUCKET_NAME}"
fi

# S3へCSVファイルをアップロード
aws s3 cp registration_data.csv "s3://${S3_BUCKET_NAME}/input/registration_data/" --region "${AWS_REGION}" || fail "registration_data.csvのアップロードに失敗しました。"
aws s3 cp lead_list.csv "s3://${S3_BUCKET_NAME}/input/lead_list/" --region "${AWS_REGION}" || fail "lead_list.csvのアップロードに失敗しました。"
echo "✅ CSVファイルをアップロードしました"

# 空のoutputフォルダを作成
aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "output/" --region "${AWS_REGION}" >/dev/null || fail "outputフォルダの作成に失敗しました。"
echo "✅ outputフォルダを作成しました"

# Glueデータベースの作成
if aws glue get-database --name "${GLUE_DB_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "ℹ️  Glueデータベースは既に存在します: ${GLUE_DB_NAME}"
else
  aws glue create-database \
    --database-input "{\"Name\":\"${GLUE_DB_NAME}\"}" \
    --region "${AWS_REGION}" || fail "Glueデータベースの作成に失敗しました。"
  echo "✅ Glueデータベースを作成しました: ${GLUE_DB_NAME}"
fi

# Glueテーブルの作成
for table_name in registration_data lead_list; do
  if aws glue get-table --database-name "${GLUE_DB_NAME}" --name "${table_name}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "ℹ️  Glueテーブルは既に存在します: ${table_name}"
  else
    aws glue create-table \
      --database-name "${GLUE_DB_NAME}" \
      --region "${AWS_REGION}" \
      --table-input "{
        \"Name\":\"${table_name}\",
        \"StorageDescriptor\":{
          \"Columns\":[
            {\"Name\":\"id\",\"Type\":\"string\"},
            {\"Name\":\"name\",\"Type\":\"string\"},
            {\"Name\":\"email\",\"Type\":\"string\"},
            {\"Name\":\"phone\",\"Type\":\"string\"}
          ],
          \"Location\":\"s3://${S3_BUCKET_NAME}/input/${table_name}/\",
          \"InputFormat\":\"org.apache.hadoop.mapred.TextInputFormat\",
          \"OutputFormat\":\"org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat\",
          \"SerdeInfo\":{
            \"SerializationLibrary\":\"org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe\",
            \"Parameters\":{\"separatorChar\":\",\"}
          }
        }
      }" || fail "Glueテーブル(${table_name})の作成に失敗しました。"
    echo "✅ Glueテーブルを作成しました: ${table_name}"
  fi
done

echo ""
echo "✅ セットアップが完了しました！"
echo "   S3バケット: ${S3_BUCKET_NAME}"
echo "   Glueデータベース: ${GLUE_DB_NAME}"