#!/bin/bash

# Cap quyen chay chmod +x 03-burn-native-assets.sh
# Dừng script ngay khi có lỗi
set -e

# Bắt lỗi và in thông tin chi tiết
trap 'echo "==> Lỗi tại dòng $LINENO"; exit 1' ERR

# Khai bao ten token, so luong token tạo
token_name="TokenPikachuV5"
token_hex=$(echo -n $token_name | xxd -p | tr -d '\n')

echo "Starting script, 03-burn native token $token_name"

mkdir -p mint-$token_name
cd mint-$token_name

#
#-------------------- Phan khai cho nguoi nhan va nguoi gui -------------------
#

sender=$(cat ../alice.addr)
sender_key="../alice.skey"
ADA_amount=10000089
token_amount=-200

receiver_addr=$(cat ../alice.addr)
# cardano-cli query utxo --address $(cat alice.addr) --testnet-magic 2

#
#-------------------------Phan xay dung giao dich-----------------------
#

# Khai bao policy id cua token muon chuyen
mint_script_file_path=mint-$token_name.script
mint_signing_key_file_path=mint-$token_name.skey
policy_id=$(cat $token_name.id)

# Query UTXO và lưu tất cả UTXO vào file utxos.json
cardano-cli query utxo --address $sender --testnet-magic 2 --out-file utxos.json
# Get the utxo with the lovelace is more than lovelace among
tx_in=$(jq -r "to_entries[] | select(.value.value.lovelace > ($ADA_amount*2+1000000)) | \"\(.key)\"" utxos.json | head -n 1)
# Kiểm tra xem có UTXO nào phù hợp không
if [ -z "$tx_in" ]; then
    echo "No suitable UTXO found with sufficient ADA amount."
    exit 1
else
    echo "Found UTXO: $tx_in"
fi

# Lấy UTXO có token muốn chuyển
#tx_token_in=fd240eec8076915a979e7e18b8a6e43d0c781017d93472ae92d65ca6daf52829#1

# Cần phải lấy đúng UTxO có token muốn chuyển
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

echo "Start building transaction to send native assets..."
# Build Tx
cardano-cli conway transaction build \
    --testnet-magic 2 \
    --tx-in $tx_token_in \
    --mint "$token_amount $policy_id.$token_hex" \
    --mint-script-file $mint_script_file_path \
    --required-signer $mint_signing_key_file_path \
    --change-address $sender \
    --out-file send-native-assets.tx

echo "Create Transaction draft created: send-native-assets.tx"
# Sign Tx
cardano-cli conway transaction sign \
    --testnet-magic 2 \
    --signing-key-file $sender_key \
    --signing-key-file $mint_signing_key_file_path \
    --tx-body-file send-native-assets.tx \
    --out-file send-native-assets.signed

echo "Transaction signed..."

# Submit Tx
cardano-cli conway transaction submit \
    --testnet-magic 2 \
    --tx-file send-native-assets.signed

echo " End Script, Đã burn $token_amount token $token_name !"
#    