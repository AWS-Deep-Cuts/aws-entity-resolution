#!/bin/bash
set -euo pipefail

# 各種パラメータの設定
readonly AWS_REGION=ap-northeast-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
  echo "❌ Error: AWS認証情報が取得できません。AWS CLIの設定を確認してください。" >&2
  exit 1
}
readonly AWS_ACCOUNT_ID
readonly S3_BUCKET_NAME=aws-er-handson-${AWS_ACCOUNT_ID}-$(date +%Y%m%d_%H%M%S)
readonly GLUE_DB_NAME=aws_er_handson_db

# パラメータを設定ファイルに保存
cat > .setup_config << EOF
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
if aws s3 ls "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  echo "ℹ️  S3バケットは既に存在します: ${S3_BUCKET_NAME}"
else
  aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}" || {
    echo "❌ Error: S3バケットの作成に失敗しました。" >&2
    exit 1
  }
  echo "✅ S3バケットを作成しました: ${S3_BUCKET_NAME}"
fi

# S3へCSVファイルをアップロード
aws s3 cp registration_data.csv "s3://${S3_BUCKET_NAME}/input/registration_data/" || {
  echo "❌ Error: registration_data.csvのアップロードに失敗しました。" >&2
  exit 1
}
aws s3 cp lead_list.csv "s3://${S3_BUCKET_NAME}/input/lead_list/" || {
  echo "❌ Error: lead_list.csvのアップロードに失敗しました。" >&2
  exit 1
}
echo "✅ CSVファイルをアップロードしました"

# Glueデータベースの作成
if aws glue get-database --name "${GLUE_DB_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  echo "ℹ️  Glueデータベースは既に存在します: ${GLUE_DB_NAME}"
else
  aws glue create-database \
    --database-input "{\"Name\":\"${GLUE_DB_NAME}\"}" \
    --region "${AWS_REGION}" || {
    echo "❌ Error: Glueデータベースの作成に失敗しました。" >&2
    exit 1
  }
  echo "✅ Glueデータベースを作成しました: ${GLUE_DB_NAME}"
fi

# Glueテーブルの作成
for table_name in registration_data lead_list; do
  if aws glue get-table --database-name "${GLUE_DB_NAME}" --name "${table_name}" --region "${AWS_REGION}" 2>/dev/null; then
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
      }" || {
      echo "❌ Error: Glueテーブル(${table_name})の作成に失敗しました。" >&2
      exit 1
    }
    echo "✅ Glueテーブルを作成しました: ${table_name}"
  fi
done

echo ""
echo "✅ セットアップが完了しました！"
echo "   S3バケット: ${S3_BUCKET_NAME}"
echo "   Glueデータベース: ${GLUE_DB_NAME}"