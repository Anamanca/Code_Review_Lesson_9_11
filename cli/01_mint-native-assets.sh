#!/bin/bash

# Cap quyen chay chmod +x 01_mint-native-assets.sh
# Dừng script ngay khi có lỗi
set -e

# Bắt lỗi và in thông tin chi tiết
trap 'echo "==> Lỗi tại dòng $LINENO"; exit 1' ERR

# cardano-cli query utxo --address $(cat alice.addr) --testnet-magic 2 --out-file alice.json
# cardano-cli query utxo --address $(cat bob.addr) --testnet-magic 2 --out-file bob.json
#
#-------------------------- Phan khai bao cho Native Token -------------------
#

# Khai bao ten token, so luong token tạo
token_name="TokenPikachuV5"
token_hex=$(echo -n $token_name | xxd -p | tr -d '\n')
token_amount=500

# IPFS hash cho metadata , hinh anh
ipfs_hash="ipfs://QmdYCdupoPDK13wxsiXwjePqSGwy3bEcUsBDiaEhxrPCfw"
ipfs_hash_hex=$(echo -n "$ipfs_hash" | xxd -p | tr -d '\n')

echo "* Starting script, 01-minting native token $token_name"

mkdir -p mint-$token_name
cd mint-$token_name

#
#-------------------- Phan khai cho nguoi nhan va nguoi gui -------------------
#

sender=$(cat ../alice.addr)
sender_key="../alice.skey"
ADA_amount=8000047

receiver_addr=$(cat ../bob.addr)
# cardano-cli query utxo --address $(cat alice.addr) --testnet-magic 2

#
#-------------------------Phan xay dung giao dich-----------------------
#

# Tạo ra cặp key mới , để quản lý policy id và minting script
if [ -f "mint-$token_name.skey" ]; then
    echo "File mint-$token_name.skey đã tồn tại, bỏ qua lệnh key-gen."
else
    cardano-cli address key-gen \
        --verification-key-file mint-$token_name.vkey \
        --signing-key-file mint-$token_name.skey

    echo "Đã tạo file mint-$token_name.vkey và mint-$token_name.skey."
    
    # Tạo public key hash (PKH) từ khóa xác minh vkey, sử dụng để tạo minting script và policy id
    cardano-cli address key-hash \
        --payment-verification-key-file mint-$token_name.vkey \
        --out-file mint-$token_name.pkh
fi

# Tạo minting script từ PKH
echo "* Creating minting script from public key hash..."

echo "{
    \"keyHash\": \"$(cat mint-$token_name.pkh)\",
    \"type\": \"sig\"
}" > mint-$token_name.script

# Hoặc có thể tạo minting script với nhiều khóa
# {
#     "type": "all",
#     "scripts": [
#         { "keyHash": "<keyHash1>", "type": "sig" },
#         { "keyHash": "<keyHash2>", "type": "sig" }
#     ]
# }

# Tạo policy id từ minting script
echo "* Generating policy ID from minting script..."

cardano-cli conway transaction policyid \
    --script-file mint-$token_name.script > $token_name.id

# Set variables
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

#Tạo metadata và lưu vào file metadata.json , trường hợp muốn tạo NFT
echo "{" > metadata.json
echo "  \"721\": {" >> metadata.json
echo "    \"$policy_id\": {" >> metadata.json
echo "      \"$(echo $token_name)\": {" >> metadata.json
echo "        \"description\": \"NFT for testing\"," >> metadata.json
echo "        \"name\": \"Cardano foundation NFT guide token\"," >> metadata.json
echo "        \"id\": \"1\"," >> metadata.json
echo "        \"image\": \"$(echo $ipfs_hash)\"" >> metadata.json
echo "      }" >> metadata.json
echo "    }" >> metadata.json
echo "  }" >> metadata.json
echo "}" >> metadata.json


echo "* Start building transaction to mint native assets..."
# Build Tx
cardano-cli conway transaction build \
    --testnet-magic 2 \
    --tx-in $tx_in \
    --mint "$token_amount $policy_id.$token_hex" \
    --mint-script-file $mint_script_file_path \
    --required-signer $mint_signing_key_file_path \
    --change-address $sender \
    --out-file mint-native-assets.tx \
#    --metadata-json-file metadata.json # gắn metadata nếu muốn tạo NFT

echo "* Create Transaction draft created: mint-native-assets.draft"
# Sign Tx
cardano-cli conway transaction sign \
    --testnet-magic 2 \
    --signing-key-file $sender_key \
    --signing-key-file $mint_signing_key_file_path \
    --tx-body-file mint-native-assets.tx \
    --out-file mint-native-assets.signed

echo "* Transaction signed..."

# Submit Tx
cardano-cli conway transaction submit \
    --testnet-magic 2 \
    --tx-file mint-native-assets.signed

echo "* End script, Đã mint $token_amount token $token_name !"
