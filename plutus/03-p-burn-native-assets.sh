#!/bin/bash

# Cap quyen chay chmod +x 03-burn-native-assets.sh
# Dừng script ngay khi có lỗi
set -e

# Bắt lỗi và in thông tin chi tiết
trap 'echo "==> Lỗi tại dòng $LINENO"; exit 1' ERR

# Khai bao ten token, so luong token tạo
token_name="TokenPikachuPlutusV7"
token_hex=$(echo -n $token_name | xxd -p | tr -d '\n')

echo "Starting script, 03-burn native token $token_name"

mkdir -p mint-$token_name
cd mint-$token_name

#
#-------------------- Phan khai cho nguoi nhan va nguoi gui -------------------
#

sender=$(cat ../alice.addr)
sender_key="../alice.skey"
ADA_amount=1700000

token_amount=-29

receiver_addr=$(cat ../alice.addr)
# cardano-cli query utxo --address $(cat alice.addr) --testnet-magic 2

#
#-------------------------Phan xay dung giao dich-----------------------
#

# Khai bao policy id, redeemer, plutus script cua token muon chuyen
REDEEMER_FILE="redeemer.json"
mint_script_file_path="../free.plutus"

policy_id=$(cat $token_name.id)

# Query UTXO và lưu tất cả UTXO vào file utxos.json
cardano-cli query utxo --address $sender --testnet-magic 2 --out-file utxos.json
# Get the utxo with the lovelace is more than lovelace among
tx_in=$(jq -r "to_entries[] | select(.value.value.lovelace > ($ADA_amount+1000000)) | \"\(.key)\"" utxos.json | head -n 1)
# Kiểm tra xem có UTXO nào phù hợp không
if [ -z "$tx_in" ]; then
    echo "No suitable UTXO found with sufficient ADA amount."
    exit 1
else
    echo "Found UTXO: $tx_in"
fi

# Tìm và khai báo UTXO có token muốn chuyển
#tx_token_in=fd240eec8076915a979e7e18b8a6e43d0c781017d93472ae92d65ca6daf52829#1
tx_token_in=$(jq -r --arg token_name "$token_hex" '
  to_entries | .[] | 
  select(
    .value.value | 
    (.. | objects | has($token_name))
  ) | .key
' utxos.json)

# Kiểm tra xem có UTXO nào phù hợp không
if [ -z "$tx_token_in" ]; then
    echo "Có lỗi!! Truyền UTxO chứa token vào biến tx_token_in."
    exit 1
else
    echo "Found UTXO token: $tx_token_in"
fi


# Khai bao UTxO collateral , kiem tra da khai bao chua
tx_in_collateral=09d42611b68a65989c3bc8984d992e3e2b5018d4a0533ebbc918f63ba0589875#0

if [ -z "$tx_in_collateral" ]; then
    echo "Có lỗi!! Truyền UTxO chứa token vào biến tx_token_in."
    exit 1
else
    echo "Found UTXO Collateral: $tx_in_collateral"
fi


echo "Start building transaction to send native assets..."
# Build Tx
cardano-cli conway transaction build \
    --testnet-magic 2 \
    --tx-in $tx_token_in \
    --tx-in-collateral $tx_in_collateral \
    --mint "$token_amount $policy_id.$token_hex" \
    --mint-script-file $mint_script_file_path \
    --mint-redeemer-file $REDEEMER_FILE \
    --change-address $sender \
    --out-file send-native-assets.tx

echo "Create Transaction draft created: send-native-assets.tx"
# Sign Tx
cardano-cli conway transaction sign \
    --testnet-magic 2 \
    --signing-key-file $sender_key \
    --tx-body-file send-native-assets.tx \
    --out-file send-native-assets.signed

echo "Transaction signed..."

# Submit Tx
cardano-cli conway transaction submit \
    --testnet-magic 2 \
    --tx-file send-native-assets.signed

echo " End Script, Đã burn $token_amount token $token_name !"
#    