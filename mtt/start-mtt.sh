#!/bin/bash
pwd=$(pwd)

export current_dir=$pwd

function check() {
    which $program
    if [ $? -ne 0 ]; then
        echo "Error: $program is not installed on your system." 
        exit -1
    else 
        echo "$program found"
    fi
}

#############################################
#  check wget, autotools, git, mvn          #
#############################################
for program in wget git mvn massh; do
    check
done

scratch_dir=$pwd/build
rm -rf ${scratch_dir}


echo "mtt -v -d --print-time --scratch ${scratch_dir} --file $pwd/hamster.ini"
#exit
mtt -v -d --print-time --scratch ${scratch_dir} --file $pwd/hamster.ini
