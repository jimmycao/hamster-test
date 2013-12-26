#!/bin/bash

nfs_dir=""
working_dir=""
ompi_prefix=""

avro_url=""
ompi_url=""


function check_exitcode() {
    if [ $? -ne 0 ]; then
        echo "Error: exit unexpectedly."
        exit -1
    fi
}
###################################################
#         init                                    #
###################################################
tmp=$(cat hamster.conf|grep nfs_dir)
nfs_dir=${tmp##*=}
working_dir=${nfs_dir}/working
ompi_prefix=${working_dir}/ompi_home

tmp=$(cat hamster.conf|grep avro_url)
avro_url=${tmp##*=}

tmp=$(cat hamster.conf|grep ompi_url)
ompi_url=${tmp##*=}


:<< INIT_END
#---------------------------
rm -rf ${working_dir}
mkdir -p ${working_dir}

INIT_END
:<< AVRO_END
###################################################
#         install avro                           #
###################################################
cd ${working_dir}
wget ${avro_url}
massh all verbose rpm -ivh ${working_dir}/avro-1.7.5-1.x86_64.rpm

AVRO_END
:<< OMPI_END
###################################################
#         install openmpi-1.7.2                   #
###################################################
cd ${working_dir}
wget ${ompi_url}
tar -zxvf openmpi-1.7.2.tar.gz
cd openmpi-1.7.2
echo "***************** 2.1 start installing openmpi ***************"
echo "=======./configure --prefix=${ompi_prefix} --with-devel-headers --enable-debug"
./configure --prefix=${ompi_prefix} --with-devel-headers --enable-debug
check_exitcode
echo "======= make -j4 ====== for installing openmpi1.7.2 ============"
make -j4 
check_exitcode
echo "======= make install ====== for installing openmpi1.7.2 ============"
make install

export PATH=${ompi_prefix}/bin:$PATH
export LD_LIBRARY_PATH=${ompi_prefix}/lib:${ompi_prefix}/openmpi/lib:$LD_LIBRARY_PATH
export C_INCLUDE_PATH=${ompi_prefix}/include:${ompi_prefix}/include/openmpi:${ompi_prefix}/include/openmpi/opal/mca/event/libevent2019/libevent

OMPI_END
:<< GIT_END
###################################################
#         git clone  hamster                      #
###################################################
echo "***************** 2.2 start cloning hamster form git repo **************" 
cd ${working_dir}
git clone git@git.greenplum.com:hamster/hamster.git 
cd ${working_dir}/hamster
git checkout hamster-1.0 

GIT_END
:<< OMPI_PLUGIN_END

echo "****************** start autogen.sh for ompi-plugin **************"
cd ${working_dir}/hamster/ompi-plugin
./autogen.sh
check_exitcode
echo "=== ./configure --prefix=${ompi_prefix} --with-ompi=1.7 ==== for ompi-plugin ===="
./configure --prefix=${ompi_prefix} --with-ompi=1.7
check_exitcode
echo "==== make ==== for  ompi-plugin========"
make 
check_exitcode
echo "==== make install ===== for ompi-plugin ===="
make install
check_exitcode


OMPI_PLUGIN_END
: << CORE_END

echo "******************* mvn clean package -DskipTests for hamster-core"
cd ${working_dir}/hamster/hamster-core
mvn clean package -DskipTests

CORE_END

echo "============== revise hamster-core conf/hamster-site.xml ======"
origin_hamster_site=${working_dir}/hamster/hamster-core/conf/hamster-site.xml
hamster_site=${working_dir}/hamster/hamster-core/target/hamster-core-1.0.0-SNAPSHOT-bin/conf/hamster-site.xml

slash_ompi_prefix=$(echo ${ompi_prefix} | sed 's_/_\\/_g')
echo $slash_ompi_prefix
rm -f ${hamster_site}
sed "s/\/path\/of\/Hamster\/pre-installed/${slash_ompi_prefix}/g" ${origin_hamster_site} > ${hamster_site}


echo '==== which hamster ======'
export PATH=${working_dir}/hamster/hamster-core/target/hamster-core-1.0.0-SNAPSHOT-bin/bin:$PATH
which hamster
if [ $? -ne 0 ]; then
    echo "Error: hamster in not found in PATH, please check!"
    exit -1
fi

#hamster -v -np 2 /usr/local/hamster/build/installs/LdXD/tests/testsuite/osu-micro-benchmarks-4.2/mpi/pt2pt/osu_mbw_mr
###################################################
#         git clone  hamster                      #
###################################################


