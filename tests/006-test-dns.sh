#!/bin/bash

job_name=dns

test_dns_nomad_job() {
    pushd ~/go/src/github.com/Roblox/nomad-driver-containerd/example

    echo "INFO: Starting nomad $job_name job using nomad-driver-containerd."
    nomad job run $job_name.nomad

    # Even though $(nomad job status) reports job status as "running"
    # The actual container process might not be running yet.
    # We need to wait for actual container to start running before trying exec.
    echo "INFO: Wait for ${job_name} container to get into RUNNING state, before trying exec."
    is_${job_name}_container_active

    echo "INFO: Checking status of $job_name job."
    job_status=$(nomad job status -short $job_name|grep Status|awk '{split($0,a,"="); print a[2]}'|tr -d ' ')
    if [ "$job_status" != "running" ];then
        echo "ERROR: Error in getting ${job_name} job status."
        return 1
    fi

    echo "INFO: Checking servers info in /etc/resolv.conf."
    output=$(nomad alloc exec -job ${job_name} cat /etc/resolv.conf)
    for ip in 127.0.0.1 127.0.0.2 ; do
        echo -e "$output" |grep "nameserver $ip" &>/dev/null
        if [ $? -ne 0 ];then
           echo "ERROR: nameserver $ip not found."
           return 1
        fi
    done

    echo "INFO: Checking searches info in /etc/resolv.conf."
    echo -e "$output" |grep "search internal.corp" &>/dev/null
    if [ $? -ne 0 ];then
       echo "ERROR: 'search internal.corp' not found."
       return 1
    fi

    echo "INFO: Checking options info in /etc/resolv.conf."
    echo -e "$output" |grep "options ndots:2" &>/dev/null
    if [ $? -ne 0 ];then
        echo "ERROR: 'options ndots:2' not found."
       return 1
    fi

    echo "INFO: Stopping nomad ${job_name} job."
    nomad job stop ${job_name}
    job_status=$(nomad job status -short ${job_name}|grep Status|awk '{split($0,a,"="); print a[2]}'|tr -d ' ')
    if [ $job_status != "dead(stopped)" ];then
        echo "ERROR: Error in stopping ${job_name} job."
        exit 1
    fi

    echo "INFO: purge nomad ${job_name} job."
    nomad job stop -purge ${job_name}
    popd
}

is_dns_container_active() {
        i="0"
        while test $i -lt 5
        do
                sudo CONTAINERD_NAMESPACE=nomad ctr task ls|grep -q RUNNING
                if [ $? -eq 0 ]; then
                        echo "INFO: ${job_name} container is up and running"
                        sleep 5s
                        break
                fi
                echo "INFO: ${job_name} container is down, sleep for 4 seconds."
                sleep 4s
                i=$[$i+1]
        done

        if [ $i -ge 5 ]; then
                echo "ERROR: ${job_name} container didn't come up. exit 1."
                exit 1
        fi
}

test_dns_nomad_job
