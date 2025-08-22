#!/bin/bash

# Cap quyen chay chmod +x 06-update_NFT_CIP_68_v2.sh
# Dừng script ngay khi có lỗi
set -e

# Bắt lỗi và in thông tin chi tiết
trap 'echo "==> Lỗi tại dòng $LINENO"; exit 1' ERR

#
#-------------------- Phan khai bao cho NFT -------------------
#

# Khai bao dia chi nguoi gui , dia chi nguoi nhan, ten token, so luong token tạo
token_name="NFT68V1"
token_hex=$(echo -n $token_name | xxd -p | tr -d '\n')

# IPFS hash cho metadata, có thể là bất kỳ hash nào bạn muốn
ipfs_hash="ipfs://QmbsU3bTQU9a8yZuDjE2bd9LLY2cgUQZco1mGD3p3DNKR4"
ipfs_hash_hex=$(echo -n "$ipfs_hash" | xxd -p | tr -d '\n')

echo "Starting script, 06-update NFT CIP-68 $token_name"

mkdir -p mint-$token_name
cd mint-$token_name

#
#----------------------- Phan khai cho nguoi nhan va nguoi gui -------------------
#

sender=$(cat ../alice.addr)
sender_key="../alice.skey"
ADA_amount=1700089

receiver_addr=$(cat ../bob.addr)
# cardano-cli query utxo --address $(cat alice.addr) --testnet-magic 2

#
#-------------------------Phan xay dung giao dich-----------------------
#

# Khai bao policy id
policy_id=$(cat $token_name.txt)

# Tao fle datum để gắn vào reference NFT
echo "{" > update_datum.json
echo "  \"constructor\": 0," >> update_datum.json
echo "  \"fields\": [" >> update_datum.json
echo "    {" >> update_datum.json
echo "      \"map\": [" >> update_datum.json
echo "        {" >> update_datum.json
echo "          \"k\": { \"bytes\": \"6e616d65\" }," >> update_datum.json
echo "          \"v\": { \"bytes\": \"$token_hex\" }" >> update_datum.json
echo "        }," >> update_datum.json
echo "        {" >> update_datum.json
echo "          \"k\": { \"bytes\": \"696d616765\" }," >> update_datum.json
echo "          \"v\": { \"bytes\": \"$ipfs_hash_hex\" }" >> update_datum.json
echo "        }," >> update_datum.json
echo "        {" >> update_datum.json
echo "          \"k\": { \"bytes\": \"6465736372697074696f6e\" }," >> update_datum.json
echo "          \"v\": { \"bytes\": \"$(echo -n 'datum has been updated' | xxd -p | tr -d '\n')\" }" >> update_datum.json
echo "        }" >> update_datum.json
echo "      ]" >> update_datum.json
echo "    }," >> update_datum.json
echo "    { \"int\": 1 }" >> update_datum.json
echo "  ]" >> update_datum.json
echo "}" >> update_datum.json


# Query UTXO và lưu tất cả UTXO vào file utxos.json
cardano-cli query utxo --address $sender --testnet-magic 2 --out-file utxos.json
# Lấy UTXO có số lượng ADA lớn hơn ADA_amount
tx_in=$(jq -r "to_entries[] | select(.value.value.lovelace > ($ADA_amount+1000000)) | \"\(.key)\"" utxos.json | head -n 1)
# Kiểm tra xem có UTXO nào phù hợp không
if [ -z "$tx_in" ]; then
    echo "No suitable UTXO found with sufficient ADA amount."
    exit 1
else
    echo "Found UTXO: $tx_in"
fi


echo "Start building transaction to send native assets..."
# Build Tx
cardano-cli conway transaction build \
    --testnet-magic 2 \
    --tx-in $tx_in \
    --tx-in 00979687859e2bf1d9e2ed9b245109ec3d2f15c67c838ca11e87b87aee9f5da0#1 \
    --tx-out $receiver_addr+$ADA_amount+"1 $policy_id.000643b0$token_hex" \
    --tx-out-datum-embed-file update_datum.json \
    --change-address $sender \
    --out-file update-NFT.build \

echo "Create Transaction draft created: update-NFT.build"
# Sign Tx
cardano-cli conway transaction sign \
    --testnet-magic 2 \
    --signing-key-file $sender_key \
    --tx-body-file update-NFT.build \
    --out-file update-NFT.signed

echo "Transaction signed..."

# Submit Tx
cardano-cli conway transaction submit \
    --testnet-magic 2 \
    --tx-file update-NFT.signed

echo "End script !"