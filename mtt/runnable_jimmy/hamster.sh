#!/bin/bash

###################################################
#         global variables                        #
###################################################
ini_path=""

nfs_dir=""
working_dir=""
ompi_prefix=""

avro_url=""
ompi_url=""

mtt_path=""
mtt_build_dir=""
###################################################
#         functions                               #
###################################################
function get_value_from_config_file() {
	tmp=$(cat ${ini_path}/hamster.conf|grep $1)
	echo ${tmp##*=}
}

function check_exitcode() {
    if [ $? -ne 0 ]; then
        echo "Error: exit unexpectedly when $1."
        exit -1
    fi
}

function check_program() {
    which $1
    if [ $? -ne 0 ]; then
        echo "Error: $1 is not installed on your system." 
        exit -1
    else 
        echo "$1 found"
    fi  
}

#############################################
#  check wget, git, mvn      			    #
#############################################
echo "####################### 0. check program if installed #########################"
for program in wget git mvn massh; do
    check_program $program
done

###################################################
#         init                                    #
###################################################
echo "####################### 1. start initing #########################"
ini_path=$(cd $(dirname $0); pwd)
nfs_dir=$(get_value_from_config_file 'nfs_dir')
working_dir=${nfs_dir}/working
ompi_prefix=${working_dir}/ompi_home

avro_url=$(get_value_from_config_file 'avro_url')
ompi_url=$(get_value_from_config_file 'ompi_url')


mtt_path=$(get_value_from_config_file 'mtt_path')
mtt_build_dir=${working_dir}/build
#:<< INIT_END
rm -rf ${working_dir}
mkdir -p ${working_dir}

rm -rf ${build_dir}
#INIT_END
#:<< AVRO_END
###################################################
#         install avro                           #
###################################################
echo "####################### 2. start installing avro #########################"
cd ${working_dir}
wget ${avro_url}
massh all verbose rpm -ivh ${working_dir}/avro-1.7.5-1.x86_64.rpm

#AVRO_END
#:<< OMPI_END
###################################################
#         install openmpi-1.7.2                   #
###################################################
echo "################## 3. start installing ompi-1.7.2 ####################"
cd ${working_dir}
wget ${ompi_url}
tar -zxvf openmpi-1.7.2.tar.gz
cd openmpi-1.7.2
echo "######## 3.1 ./configure --prefix=${ompi_prefix} --with-devel-headers --enable-debug"
./configure --prefix=${ompi_prefix} --with-devel-headers --enable-debug
check_exitcode  './configure --prefix=${ompi_prefix} --with-devel-headers --enable-debug'
echo "######## 3.2 make -j4 #### for installing openmpi1.7.2 ################"
make -j4 
check_exitcode 'make -j4'
echo "######## 3.3 make install #####  for installing openmpi1.7.2 ##########"
make install
check_exitcode 'make install'

#OMPI_END

export PATH=${ompi_prefix}/bin:$PATH
export LD_LIBRARY_PATH=${ompi_prefix}/lib:${ompi_prefix}/openmpi/lib:$LD_LIBRARY_PATH
export C_INCLUDE_PATH=${ompi_prefix}/include:${ompi_prefix}/include/openmpi:${ompi_prefix}/include/openmpi/opal/mca/event/libevent2019/libevent

#:<< GIT_END
###################################################
#         git clone  hamster                      #
###################################################
echo "############ 4 start cloning hamster form git repo ###################" 
cd ${working_dir}
git clone git@git.greenplum.com:hamster/hamster.git 
cd ${working_dir}/hamster
git checkout hamster-1.0 

#GIT_END
#:<< OMPI_PLUGIN_END

echo "################# 4.1  start autogen.sh for ompi-plugin ##############"
cd ${working_dir}/hamster/ompi-plugin
./autogen.sh
check_exitcode './autogen.sh for ompi-plugin'
echo "###### ./configure --prefix=${ompi_prefix} --with-ompi=1.7 ### for ompi-plugin "
./configure --prefix=${ompi_prefix} --with-ompi=1.7
check_exitcode './configure --prefix=${ompi_prefix} --with-ompi=1.7'
echo "#####  make ######## for  ompi-plugin"
make 
check_exitcode 'make'
echo "##### make install ######## for ompi-plugin" 
make install
check_exitcode  'make install'


#OMPI_PLUGIN_END
#: << CORE_END

echo "############ 4.2  mvn clean package -DskipTests for hamster-core"
cd ${working_dir}/hamster/hamster-core
mvn clean package -DskipTests

#CORE_END

echo "########### 4.2.1 revise hamster-core conf/hamster-site.xml #############"
origin_hamster_site=${working_dir}/hamster/hamster-core/conf/hamster-site.xml
hamster_site=${working_dir}/hamster/hamster-core/target/hamster-core-1.0.0-SNAPSHOT-bin/conf/hamster-site.xml

slash_ompi_prefix=$(echo ${ompi_prefix} | sed 's_/_\\/_g')
echo $slash_ompi_prefix
rm -f ${hamster_site}
sed "s/\/path\/of\/Hamster\/pre-installed/${slash_ompi_prefix}/g" ${origin_hamster_site} > ${hamster_site}


echo '########## 4.2.2 which hamster ###############'
export PATH=${working_dir}/hamster/hamster-core/target/hamster-core-1.0.0-SNAPSHOT-bin/bin:$PATH
which hamster
if [ $? -ne 0 ]; then
    echo "Error: hamster in not found in PATH, please check!"
    exit -1
fi

###################################################
#         start mtt 	                          #
###################################################
echo "############ 5 start mtt  ###################" 
echo "############ 5.1 {mtt_path}/mtt -d -v --print-time --scratch ${mtt_build_dir} --file ${ini_path}/hamster.ini ###################" 
${mtt_path}/mtt -d -v --print-time --scratch ${mtt_build_dir} --file ${ini_path}/hamster.ini
