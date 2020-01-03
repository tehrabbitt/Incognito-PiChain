#!/bin/sh bash

run()
{
  validator_key=12F27wGzDHAyGJLEVFFFi7JL1NWQpSFs87pjGkzaHFKS4Ujj3q8
  bootnode="mainnet-bootnode.incognito.org:9330"
  is_shipping_logs=0
  latest_tag="$1"
  current_tag="$2"
  data_dir="data"
  eth_data_dir="eth-mainnet-data"
  logshipper_data_dir="logshipper-mainnet-data"


  if [ -z "$node_port" ]; then
    node_port="9436";
  fi
  if [ -z "$rpc_port" ]; then
    rpc_port="9336";
  fi

  docker -v || bash -c "wget -qO- https://get.docker.com/ | sh"

  if [ ! -d "$PWD/${eth_data_dir}" ]
  then
    mkdir $PWD/${eth_data_dir}
    chmod -R 777 $PWD/${eth_data_dir}
  fi

  balena rm -f inc_mainnet
  balena rm -f eth_mainnet
  if [ "$current_tag" != "" ]
  then
    balena image rm -f incognitochain/incognito-mainnet-arm:${current_tag}
  fi

  #pull armv8 version of geth-client
  balena pull ffaerber/go-ethereum
  #pull incognito arm version
  balena pull incognitochain/incognito-mainnet-arm:arm64_20191210_1
  balena network create --driver bridge inc_net || true

  #balena run -ti --emulate --restart=always --net inc_net -d -p 8545:8545  -p 30303:30303 -p 30303:30303/udp -v $PWD/${eth_data_dir}:/home/parity/.local/share/io.parity.ethereum/ --name eth_mainnet  parity/parity:stable --light --jsonrpc-interface all --jsonrpc-hosts all  --jsonrpc-apis all --mode last --base-path=/home/parity/.local/share/io.parity.ethereum/
  balena run -d $node_port:$node_port -p $rpc_port:$rpc_port -v /usr/src/eth-mainnet-data:/root/.ethereum ffaerber/go-ethereum
  cid=$(balena ps -laq) 
  balena exec -d $cid geth -syncmode light -rpc -rpcaddr 0.0.0.0
  balena run --restart=always --net inc_net -p $node_port:$node_port -p $rpc_port:$rpc_port -e NODE_PORT=$node_port -e RPC_PORT=$rpc_port -e BOOTNODE_IP=$bootnode -e GETH_NAME=eth_mainnet -e MININGKEY=${validator_key} -e TESTNET=false -v $PWD/${data_dir}:/data -d --name inc_mainnet incognitochain/incognito-mainnet-arm:arm64_20191210_1

  if [ $is_shipping_logs -eq 1 ]
  then
    if [ ! -d "$PWD/${logshipper_data_dir}" ]
    then
      mkdir $PWD/${logshipper_data_dir}
      chmod -R 777 $PWD/${logshipper_data_dir}
    fi
    balena image rm -f incognitochain/logshipper:1.0.0
    balena run --restart=always -d --name inc_logshipper -e RAW_LOG_PATHS=/tmp/*.txt -e JSON_LOG_PATHS=/tmp/*.json -e LOGSTASH_ADDRESSES=34.94.14.147:5000 --mount type=bind,source=$PWD/${data_dir},target=/tmp --mount type=bind,source=$PWD/${logshipper_data_dir},target=/usr/share/filebeat/data incognitochain/logshipper:1.0.0
  fi
}

# kill existing run.sh processes
ps aux | grep '[r]un.sh' | awk '{ print $2}' | grep -v "^$$\$" | xargs kill -9

current_latest_tag=""
while [ 1 = 1 ]
do
  tags=`curl -X GET https://registry.hub.docker.com/v1/repositories/incognitochain/incognito-mainnet/tags  | sed -e 's/[][]//g' -e 's/"//g' -e 's/ //g' | tr '}' '\n'  | awk -F: '{print $3}' | sed -e 's/\n/;/g'`

  sorted_tags=($(echo ${tags[*]}| tr " " "\n" | sort -rn))
  latest_tag=${sorted_tags[0]}

  if [ "$current_latest_tag" != "$latest_tag" ]
  then
    run $latest_tag $current_latest_tag
    current_latest_tag=$latest_tag
  fi

  sleep 3600s

done &
