#!/bin/sh

rmq_wait ()
{
while ! nc -zw2 127.0.0.1 5672 || ! nc -zw2 127.0.0.1 4369 || ! nc -zw2 127.0.0.1 25672; do
sleep 2
done
}

etcd_wait()
{
while ! nc -zw2 ${ETCD_HOST} ${ETCD_PORT} || [ $(curl -s -I -w %{http_code} -o /dev/null ${ETCD_HOST}:${ETCD_PORT}/v2/keys?recursive=true) -ne 200 ]; do
sleep 2
done
}

discovery()
{
curl -s -o /dev/null ${ETCD_HOST}:${ETCD_PORT}/v2/keys/resolv/`hostname` -XPUT -d value="`hostname -i`"
while [ $(curl -s ${ETCD_HOST}:${ETCD_PORT}/v2/keys/resolv?recursive=true | jq '.node.nodes | length') -lt 2 ]; do 
sleep 2
done
curl -s ${ETCD_HOST}:${ETCD_PORT}/v2/keys/resolv?recursive=true > /tmp/etcd.resolv
for i in `seq 1 $(cat /tmp/etcd.resolv | jq '.node.nodes | length')`
do 
cat /tmp/etcd.resolv | jq .node.nodes[`expr $i - 1`].key,.node.nodes[`expr $i - 1`].value | tr '\n' ' ' | tr -d \" | cut -f3 -d/ | awk '{print $2,$1}' | sudo -u root sh -c "cat >> /etc/hosts"
done
}

unset http_proxy
unset https_proxy
etcd_wait
discovery

RABBITMQ_COOKIE=~/.erlang.cookie
chmod 600 $RABBITMQ_COOKIE
echo -n CHYSFBZRLKFFCHCBDFCH > $RABBITMQ_COOKIE
chmod 400 $RABBITMQ_COOKIE

$RABBITMQ_HOME/sbin/rabbitmq-server &
RABBITMQ_PID=$!
rmq_wait

if [ ! -z "$RMQ_USER" ] && [ ! -z "$RMQ_PASS" ]; then
$RABBITMQ_HOME/sbin/rabbitmqctl add_user $RMQ_USER $RMQ_PASS
$RABBITMQ_HOME/sbin/rabbitmqctl set_user_tags $RMQ_USER administrator
$RABBITMQ_HOME/sbin/rabbitmqctl set_permissions $RMQ_USER ".*" ".*" ".*"
fi

$RABBITMQ_HOME/sbin/rabbitmqctl set_policy -p / ha-all '.*' '{"ha-mode":"all", "ha-sync-mode":"automatic"}'
wait $RABBITMQ_PID 2>/dev/null
