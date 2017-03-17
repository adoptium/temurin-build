exit_script() {
    if [[ -z ${KEEP} ]] ; then
      docker ps -a | awk '{ print $1,$2 }' | grep $CONTAINER | awk '{print $1 }' | xargs -I {} docker rm -f {}
    fi
    echo "${error}Process exited${normal}"
    trap - SIGINT SIGTERM # clear the trap
    kill -- -$$ # Sends SIGTERM to child/sub processes
}

trap exit_script SIGINT SIGTERM 
