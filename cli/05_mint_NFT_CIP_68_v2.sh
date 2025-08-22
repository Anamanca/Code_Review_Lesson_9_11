#!/bin/bash

# Cap quyen chay chmod +x 05_mint_NFT_CIP_68_v2.sh
# Dừng script ngay khi có lỗi
set -e

# Bắt lỗi và in thông tin chi tiết
trap 'echo "==> Lỗi tại dòng $LINENO"; exit 1' ERR

#
#-------------------------- Phan khai bao cho NFT -------------------
#

# Khai bao dia chi nguoi gui , dia chi nguoi nhan, ten token, so luong token tạo
token_name="NFT68V3Test"
token_hex=$(echo -n $token_name | xxd -p | tr -d '\n')

# IPFS hash cho metadata, có thể là bất kỳ hash nào bạn muốn
ipfs_hash="ipfs://QmdYCdupoPDK13wxsiXwjePqSGwy3bEcUsBDiaEhxrPCfw"
ipfs_hash_hex=$(echo -n "$ipfs_hash" | xxd -p | tr -d '\n')

echo "Starting script, 05-minting NFT CIP-68 $token_name"

mkdir -p mint-$token_name
cd mint-$token_name

#
#-------------------- Phan khai cho nguoi nhan va nguoi gui -------------------
#

sender=$(cat ../alice.addr)
sender_key="../alice.skey"
ADA_amount=2000089

receiver_addr=$(cat ../bob.addr)
# cardano-cli query utxo --address $(cat alice.addr) --testnet-magic 2

#
#-------------------------Phan xay dung giao dich-----------------------
#

# B1 :Tạo ra cặp key mới , để quản lý policy id và minting script
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

# B2: Tạo minting script từ PKH
echo "Creating minting script from public key hash..."

echo "{
    \"keyHash\": \"$(cat mint-$token_name.pkh)\",
    \"type\": \"sig\"
}" > mint-$token_name.script

# Hoặc có thể tạo minting script với nhiều khóa, 
# 
# {
#     "type": "all",
#     "scripts": [
#         { "keyHash": "<keyHash1>", "type": "sig" },
#         { "keyHash": "<keyHash2>", "type": "sig" }
#     ]
# }

# Tạo policy id từ minting script
# policy id là hash của minting script
echo "Generating policy ID from minting script..."
cardano-cli conway transaction policyid \
    --script-file mint-$token_name.script > $token_name.txt

# Set variables
mint_script_file_path=mint-$token_name.script
mint_signing_key_file_path=mint-$token_name.skey
policy_id=$(cat $token_name.txt)

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

# Tao meatadata cho NFT theo chuẩn CIP-25
echo "{" > metadata.json
echo "  \"721\": {" >> metadata.json
echo "    \"$policy_id\": {" >> metadata.json
echo "      \"$token_hex\": {" >> metadata.json
echo "        \"name\": \"My CIP68 NFT\"," >> metadata.json
echo "        \"image\": \"$ipfs_hash\"," >> metadata.json
echo "        \"description\": \"Đây là một NFT theo chuẩn CIP-68\"" >> metadata.json
echo "      }" >> metadata.json
echo "    }" >> metadata.json
echo "  }" >> metadata.json
echo "}" >> metadata.json


# Tao file datum để gắn vào NFT theo chuẩn CIP-68
echo "{" > datum.json
echo "  \"constructor\": 0," >> datum.json
echo "  \"fields\": [" >> datum.json
echo "    {" >> datum.json
echo "      \"map\": [" >> datum.json
echo "        {" >> datum.json
echo "          \"k\": { \"bytes\": \"6e616d65\" }," >> datum.json
echo "          \"v\": { \"bytes\": \"$token_hex\" }" >> datum.json
echo "        }," >> datum.json
echo "        {" >> datum.json
echo "          \"k\": { \"bytes\": \"696d616765\" }," >> datum.json
echo "          \"v\": { \"bytes\": \"$ipfs_hash_hex\" }" >> datum.json
echo "        }," >> datum.json
echo "        {" >> datum.json
echo "          \"k\": { \"bytes\": \"6465736372697074696f6e\" }," >> datum.json
echo "          \"v\": { \"bytes\": \"$(echo -n 'This is NFT CIP-68 for testing' | xxd -p | tr -d '\n')\" }" >> datum.json
echo "        }" >> datum.json
echo "      ]" >> datum.json
echo "    }," >> datum.json
echo "    { \"int\": 1 }" >> datum.json
echo "  ]" >> datum.json
echo "}" >> datum.json

echo "File metadata.json và datum.json đã được tạo thành công."

echo "Start building transaction to mint NFT assets..."
# Build Tx
cardano-cli conway transaction build \
    --testnet-magic 2 \
    --tx-in $tx_in \
    --tx-out $receiver_addr+$ADA_amount+"1 $policy_id.000de140$token_hex" \
    --tx-out $sender+$ADA_amount+"1 $policy_id.000643b0$token_hex" \
    --tx-out-datum-embed-file datum.json \
    --mint "1 $policy_id.000643b0$token_hex + 1 $policy_id.000de140$token_hex" \
    --mint-script-file $mint_script_file_path \
    --change-address $sender \
    --required-signer $mint_signing_key_file_path \
    --out-file mint-native-assets.build
    #--metadata-json-file metadata.json # gắn metadata nếu muốn tạo NFT

echo "Create Transaction draft created: mint-native-assets.tx"
# Sign Tx
cardano-cli conway transaction sign \
    --testnet-magic 2 \
    --signing-key-file $sender_key \
    --signing-key-file $mint_signing_key_file_path \
    --tx-body-file mint-native-assets.build \
    --out-file mint-native-assets.signed

echo "Transaction signed..."

# Submit Tx
cardano-cli conway transaction submit \
    --testnet-magic 2 \
    --tx-file mint-native-assets.signed

echo "End script !"

#     --tx-out-datum-embed-file-index 1 \