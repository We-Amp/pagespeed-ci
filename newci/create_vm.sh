#!/bin/bash
set -e

TEMPLATE="unknown"
VM_NAME="unknown"
REF="unkown"
SHA="unknown"

while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    -t|--template)
    export TEMPLATE="$2"
    shift # past argument
    ;;
    -n|--name)
    export VM_NAME="$2"
    shift # past argument
    ;;
    -s|--script)
    export TEST_SCRIPT="$2"
    shift # past argument
    ;;
    -r|--ref)
    export REF="$2"
    shift # past argument
    ;;
    -c|--commit)
    export SHA="$2"
    shift # past argument
    ;;
    --default)
    DEFAULT=YES
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done
echo TEMPLATE    = "${TEMPLATE}"
echo VM_NAME     = "${VM_NAME}"
echo TEST_SCRIPT = "${TEST_SCRIPT}"
echo REF = "${REF}"
echo SHA = "${SHA}"

if [[ -n $1 ]]; then
    echo "Last line of file specified as non-opt/last argument:"
    tail -1 $1
fi

if [ ! -f $TEST_SCRIPT ]; then
    echo "Test script not found"
    exit 1
fi

virt-addr() {
    VM="$1"
    for mac in `virsh domiflist ${VM} |grep -o -E "([0-9a-f]{2}:){5}([0-9a-f]{2})"` ; do
	arp -e |grep $mac  |grep -o -P "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"
    done
}

function cleanup {
    set +x
    set +e
    virsh destroy "${VM_NAME}" > /dev/null
    virsh undefine --remove-all-storage "${VM_NAME}" > /dev/null
    echo "Finished CI run for ${IP}"
}

export IP=""
#echo "Cloning ${TEMPLATE} VM to ${VM_NAME}"
count=1

until virt-clone -o "${TEMPLATE}" -n "${VM_NAME}" --auto-clone
do
  if [ $count -eq 30 ]
  then
       printf "Clone failed: max retries exceeded: ${count}\n"
       exit 1
  fi
  sleep 10
  ((count++))
done

trap cleanup EXIT
virsh start "${VM_NAME}" > /dev/null

echo "Waiting for ${VM_NAME} to get an ip address "
while [ -z "$IP" ]; do
    sleep 0.2
    export IP=$(virt-addr "${VM_NAME}" || echo "")
    printf "."
done

printf "\n"
echo "VM Ip is: ${IP}: Start CI RUN. Wait for ssh server to wake up "

while ! ssh ubuntu@$IP -- bash << EOF
exit
EOF
do
    sleep 0.2
    printf "."
done

set -e
set -x
printf "\n"
echo "Start CI run for ${IP}"
$TEST_SCRIPT
