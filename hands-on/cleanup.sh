#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# AWS 認証チェック (AWS CLI のページャー無効化もここで行う)
source "${SCRIPT_DIR}/aws_auth_check.sh"

# setup.shで保存した設定ファイルを読み込む
if [[ ! -f .setup_config ]]; then
  echo "❌ Error: 設定ファイル(.setup_config)が見つかりません。" >&2
  echo "   setup.sh を実行した hands-on ディレクトリで実行してください。" >&2
  exit 1
fi

source .setup_config
export AWS_REGION AWS_DEFAULT_REGION="${AWS_REGION}"

CREATED_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
aws_auth_check "${AWS_REGION}" || exit 1

# setup.sh と別のアカウントで実行して、無関係なリソースを消さないようにする
if [[ "${AWS_ACCOUNT_ID}" != "${CREATED_ACCOUNT_ID}" ]]; then
  echo "❌ Error: setup.sh を実行したアカウント (${CREATED_ACCOUNT_ID}) と、現在の認証情報のアカウント (${AWS_ACCOUNT_ID}) が異なります。" >&2
  echo "   setup.sh 実行時と同じプロファイル (${SETUP_AWS_PROFILE:-default}) で実行してください。" >&2
  echo "   例: export AWS_PROFILE=${SETUP_AWS_PROFILE:-default}" >&2
  exit 1
fi

echo "以下のリソースを削除します:"
echo "  AWS Region: ${AWS_REGION}"
echo "  S3 Bucket: ${S3_BUCKET_NAME}"
echo "  Glue Database: ${GLUE_DB_NAME}"
echo ""

# Entity Resolutionのリソース削除
for workflow in fuzzy-matching-workflow; do
  if aws entityresolution get-matching-workflow --workflow-name "${workflow}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws entityresolution delete-matching-workflow --workflow-name "${workflow}" --region "${AWS_REGION}"
    echo "✅ Matching workflowを削除しました: ${workflow}"
  else
    echo "ℹ️  Matching workflowは存在しません: ${workflow}"
  fi
done

for schema in registration-schema lead-schema; do
  if aws entityresolution get-schema-mapping --schema-name "${schema}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws entityresolution delete-schema-mapping --schema-name "${schema}" --region "${AWS_REGION}"
    echo "✅ Schema mappingを削除しました: ${schema}"
  else
    echo "ℹ️  Schema mappingは存在しません: ${schema}"
  fi
done

# Glueテーブルの削除
for table in registration_data lead_list; do
  if aws glue get-table --database-name "${GLUE_DB_NAME}" --name "${table}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws glue delete-table --database-name "${GLUE_DB_NAME}" --name "${table}" --region "${AWS_REGION}"
    echo "✅ Glueテーブルを削除しました: ${table}"
  else
    echo "ℹ️  Glueテーブルは存在しません: ${table}"
  fi
done

# Glueデータベースの削除
if aws glue get-database --name "${GLUE_DB_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws glue delete-database --name "${GLUE_DB_NAME}" --region "${AWS_REGION}"
  echo "✅ Glueデータベースを削除しました: ${GLUE_DB_NAME}"
else
  echo "ℹ️  Glueデータベースは存在しません: ${GLUE_DB_NAME}"
fi

# S3バケットの削除
if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive --region "${AWS_REGION}"
  aws s3 rb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
  echo "✅ S3バケットを削除しました: ${S3_BUCKET_NAME}"
else
  echo "ℹ️  S3バケットは存在しません: ${S3_BUCKET_NAME}"
fi

# 設定ファイルの削除
rm -f .setup_config
echo ""
echo "✅ すべてのリソースの削除が完了しました！"