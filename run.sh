#!/bin/bash
##########################################################
#                     configuration                      #
##########################################################
VERBOSE=0
COMMON_NP=20
GRAPHLAB_HOME=/usr/local/hamster/graphlab
HDFS_IP_PORT=hdfs://10.37.7.101:8020
##########################################################
# preparation for example_test and orte_test             #
##########################################################
TEST_DIR="example_test orte_test"
PWD=$(pwd)
TEST_RESULT_FILE=test_result.txt
EXAMPLE_PROG="broadcast buffon_mpi communicator_mpi monte_carlo_pi prime_mpi ring sum_mpi"
ORTE_PROG_FINISHED="mpi_no_op mpi_barrier hello hello_barrier crisscross"
ORTE_PROG_FAILED="abort multi_abort delayed_abort loop_child bad_exit pubsub accept connect ziatest slave"

rm -f $TEST_RESULT_FILE

out=$(which hamster)
if [ $? -ne 0 ]; then
    echo $out
    exit -1
fi

for dir in $TEST_DIR; do
    cd $dir; make clean; make; cd -
done

##########################################################
#                        functions                       #
##########################################################
function check_program() {
    if [ ! -f $PROG ]; then
        echo "$PROG is not existed, please check."    
        exit -1
    fi
}

function run_program() {
    echo $CMD
    OUT=`$CMD 2>&1`
    EXIT_CODE=$?  
    HTTP_LINE=$(echo "$OUT"|grep http)
    AFTER_HTTP=${HTTP_LINE##*http}
    APP_ID=$(echo $AFTER_HTTP|cut -d'/' -f5)

    if [ $VERBOSE -eq 1 ]; then
        echo "OUT = $OUT"
        echo "EXIT_CODE = $EXIT_CODE"
        echo "AFTER_HTTP= $AFTER_HTTP"
        echo "APP_ID = $APP_ID"
    fi 
}

function check_PROG_if_finished() {
    if [ $EXIT_CODE -eq 0 ]; then
        echo "$PROG is passed" >> $TEST_RESULT_FILE 
    else
        echo "======== $PROG should be finished, but now failed, so it is not passed, APP_ID = $APP_ID, please check!" >> $TEST_RESULT_FILE 
    fi
}

function check_PROG_if_failed() {
    if [ $EXIT_CODE -eq 0 ]; then
        echo "======= $PROG should be failed, but now finished, so it is not passed, APP_ID = $APP_ID, please check!" >> $TEST_RESULT_FILE 
    else
        echo "$PROG is passed" >> $TEST_RESULT_FILE 
    fi
}


:<< "END_example"
##########################################################
#  test example_test/*,  expected: finished              # 
##########################################################
echo "##########################################################"  >> $TEST_RESULT_FILE
echo "#  test example_test/*,  expected: finished              #"  >> $TEST_RESULT_FILE
echo "##########################################################"  >> $TEST_RESULT_FILE
for program in $EXAMPLE_PROG; do
    PROG="$PWD/example_test/$program"
    check_program
    CMD="hamster -v -np $COMMON_NP $PROG"
    run_program
    check_PROG_if_finished
done

END_example

:<< END_orte_finished 
##########################################################
#     test orte_test/*-1  expected: finished             #
##########################################################
echo "##########################################################"  >> $TEST_RESULT_FILE
echo "#     test orte_test/*-1  expected: finished             #"  >> $TEST_RESULT_FILE
echo "##########################################################"  >> $TEST_RESULT_FILE
for program in $ORTE_PROG_FINISHED; do
    PROG="$PWD/orte_test/$program"
    check_program
    CMD="hamster -v -np $COMMON_NP $PROG"
    if [ "x$program" = "xcrisscross" ]; then
        CMD="hamster -v -np 2 $PROG"
    fi
    run_program
    check_PROG_if_finished
done

END_orte_finished

:<< END_orte_failed
##########################################################
#     test orte_test/*-2  expected: failed               #
##########################################################
echo "##########################################################"  >> $TEST_RESULT_FILE
echo "#     test orte_test/*-2  expected: failed               #"  >> $TEST_RESULT_FILE
echo "##########################################################"  >> $TEST_RESULT_FILE
for program in $ORTE_PROG_FAILED; do
    PROG="$PWD/orte_test/$program"
    check_program
    CMD="hamster -v -np $COMMON_NP $PROG"
    run_program
    check_PROG_if_failed
done

END_orte_failed
:<< END_policy_finished
##########################################################
#     test allocation-1 expected: finished               #
##########################################################
echo "##########################################################"  >> $TEST_RESULT_FILE
echo "#     test allocation-1 expected: finished               #"  >> $TEST_RESULT_FILE
echo "##########################################################"  >> $TEST_RESULT_FILE
PROG=$PWD/orte_test/hello
check_program
CMDs="hamster -v -p cl -np 1 -p cl $PROG|hamster -v -np 5 -p cl $PROG|hamster -v -np 5 -p cl -min-ppn 5 -max-ppn 5 $PROG|hamster -v -np 1 -p cl -min-ppn 1 -max-ppn 1 $PROG|hamster -v -np 1 $PROG|hamster -v -np 10 $PROG|hamster -v -np 4  -p cl -min-ppn 2 -max-ppn 2 $PROG|hamster -v -np 7 -p cl -min-ppn 3 -max-ppn 5 $PROG|hamster -v -p gl -np 2 $PROG|hamster -v -p cl -max-ppn 1 -np 2 $PROG"
OLD_IFS="$IFS"
IFS="|"
CMD_ARRAY=($CMDs)
for CMD in ${CMD_ARRAY[@]}; do
    IFS="$OLD_IFS"
    run_program
    if [ $EXIT_CODE -eq 0 ]; then
        echo "$CMD is passed" >> $TEST_RESULT_FILE 
    else
        echo "========= $CMD should be finished, but now failed, so it is not passed, APP_ID = $APP_ID, please check!" >> $TEST_RESULT_FILE 
    fi
done

END_policy_finished
:<< END_policy_failed
##########################################################
#     test allocation-2 expected: failed                 #
##########################################################
echo "##########################################################" >> $TEST_RESULT_FILE
echo "#     test allocation-2 expected: failed                 #" >> $TEST_RESULT_FILE
echo "##########################################################" >> $TEST_RESULT_FILE
#echo "============== test allocation-2 expected: failed ========"  

PROG=$PWD/orte_test/hello
check_program
CMDs="hamster -np 5 -p cl -min-ppn 5 -max-ppn 4 $PROG|hamster -np 24 -p cl -min-ppn 10 -max-ppn 11 $PROG|hamster -min-ppn 3 -max-ppn 5 -np 5 $PROG|hamster -p generic -min-ppn 3 -np 5 $PROG|hamster -p gl -min-ppn 3 -np 5 $PROG|hamster -np 1000 -max-at 10000 $PROG"
OLD_IFS="$IFS"
IFS="|"
CMD_ARRAY=($CMDs)
for CMD in ${CMD_ARRAY[@]}; do
    IFS="$OLD_IFS"
    run_program
    if [ $EXIT_CODE -ne 0 ]; then
        echo "$CMD is passed" >> $TEST_RESULT_FILE 
    else
        echo "======== $CMD should be failed, but now finished, so it is not passed, APP_ID = $APP_ID, please check!" >> $TEST_RESULT_FILE 
    fi
done

END_policy_failed
##########################################################
#                prepare GraphLab2.2                     #
##########################################################
hadoop fs -rm -r /user/root/graphlab
hadoop fs -mkdir -p /user/root/graphlab
hadoop fs -put graphlab_data/* /user/root/graphlab/

:<< END_cf 
##########################################################
# test GraphLab2.2-1: collaborative-filtering            #
##########################################################
echo "##########################################################" >> $TEST_RESULT_FILE
echo "# test GraphLab2.2-1: collaborative-filtering            #" >> $TEST_RESULT_FILE
echo "##########################################################" >> $TEST_RESULT_FILE

CF_PATH="$GRAPHLAB_HOME/release/toolkits/collaborative_filtering"
#--------------------------als---------------------
PROG=$CF_PATH/als
check_program
CMD="hamster -np 4 -mem 2048 $PROG --matrix $HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix --D=20 --lambda=0.065 --max_iter=5 --predictions=$HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix/out"
run_program
check_PROG_if_finished
#----------------------sgd--------------------------
hadoop fs -rm /user/root/graphlab/cf/smallnetflix/out*
PROG=$CF_PATH/sgd
check_program
CMD="hamster -v -np 2 $PROG --matrix $HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix --D=20 --lambda=0.065 --max_iter=3 --minval=1 --maxval=5 --predictions=$HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix/out"
run_program
check_PROG_if_finished
#-------------------biassgd--------------------------
hadoop fs -rm /user/root/graphlab/cf/smallnetflix/out*
PROG=$CF_PATH/biassgd
check_program
CMD="hamster -v -np 2 $PROG --matrix $HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix --D=20 --lambda=0.065 --max_iter=3 --minval=1 --maxval=5 --predictions=$HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix/out"
run_program
check_PROG_if_finished
#-------------------svd++--------------------------
hadoop fs -rm /user/root/graphlab/cf/smallnetflix/out*
PROG=$CF_PATH/svdpp
check_program
CMD="hamster -v -np 4 $PROG --matrix $HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix --D=20 --max_iter=3 --minval=1 --maxval=5 --predictions=$HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix/out"
run_program
check_PROG_if_finished
#-------------------weighted-als--------------------------
hadoop fs -rm /user/root/graphlab/cf/smallnetflix/out*
PROG=$CF_PATH/wals
check_program
CMD="hamster -v -np 2 $PROG --matrix $HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix --D=20 --lambda=0.065 --max_iter=3 --minval=1 --maxval=5 --predictions=$HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix/out"
run_program
check_PROG_if_finished
#-------------------sparse-als--------------------------
hadoop fs -rm /user/root/graphlab/cf/smallnetflix/out*
PROG=$CF_PATH/sparse_als
check_program
CMD="hamster -v -np 2 $PROG --matrix $HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix --D=20 --lambda=0.065 --max_iter=3 --minval=1 --maxval=5 --predictions=$HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix/out"
run_program
check_PROG_if_finished
#-------------------svd--------------------------
hadoop fs -rm /user/root/graphlab/cf/smallnetflix/out*
PROG=$CF_PATH/svd
check_program
CMD="hamster -v -np 2 $PROG --matrix $HDFS_IP_PORT/user/root/graphlab/cf/smallnetflix/smallnetflix_mm.train --rows=100000 --cols=5000 --nsv=4 --nv=4 --max_iter=3 --ncpus=1"
run_program
check_PROG_if_finished

END_cf
:<< END_ga 
##########################################################
#        test GraphLab2.2-2: graph-analytics             #
##########################################################
echo "##########################################################" >> $TEST_RESULT_FILE
echo "#        test GraphLab2.2-2: graph-analytics             #" >> $TEST_RESULT_FILE
echo "##########################################################" >> $TEST_RESULT_FILE

GA_PATH="$GRAPHLAB_HOME/release/toolkits/graph_analytics"
#-------------------pagerank--------------------------
PROG=$GA_PATH/pagerank
check_program
CMD="hamster -v -np 2 $PROG --graph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --format=adj"
run_program
check_PROG_if_finished
#-------------------format conversion--------------------------
PROG=$GA_PATH/format_convert
check_program
CMD="hamster -v -np 2 $PROG --ingraph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --informat=adj --outgraph=$HDFS_IP_PORT/user/root/graphlab/ga/out.tsv --outformat=tsv --outgzip=0"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/ga/out*
#-------------------Undirected-Triangle-Counting--------------------------
PROG=$GA_PATH/undirected_triangle_count
check_program
CMD="hamster -v -np 2 $PROG --graph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --format=adj --per_vertex=$HDFS_IP_PORT/user/root/graphlab/ga/out"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/ga/out*
#-------------------Directed-Triangle-Counting--------------------------
PROG=$GA_PATH/directed_triangle_count
check_program
CMD="hamster -v -np 2 $PROG --graph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --format=adj --per_vertex=$HDFS_IP_PORT/user/root/graphlab/ga/out"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/ga/out*
#------------------KCore Decomposition-------------------------
PROG=$GA_PATH/kcore
check_program
CMD="hamster -v -np 2 $PROG --graph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --format=adj --savecores=$HDFS_IP_PORT/user/root/graphlab/ga/out"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/ga/out*
#------------------Graph-Coloring-------------------------
PROG=$GA_PATH/simple_coloring
check_program
CMD="hamster -v -np 2 $PROG --graph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --format=adj --output=$HDFS_IP_PORT/user/root/graphlab/ga/out"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/ga/out*
#------------------07-Connected-Component-------------------------
PROG=$GA_PATH/connected_component
check_program
CMD="hamster -v -np 2 $PROG --graph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --format=adj --saveprefix=$HDFS_IP_PORT/user/root/graphlab/ga/out"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/ga/out*
#------------------08-Approximate-Diameter------------------------
PROG=$GA_PATH/approximate_diameter
check_program
CMD="hamster -v -np 2 $PROG --graph=$HDFS_IP_PORT/user/root/graphlab/ga/input.adj --format=adj"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/ga/out*
#--------------09-Graph-Partitioning-----failed------------------
#need revise the hard-coded cmd in graphlab/toolkits/graph_analytics/partitioning.cpp

END_ga
:<< END_cluster 
##########################################################
#        test GraphLab2.2-3: clustering                  #
##########################################################
echo "##########################################################" >> $TEST_RESULT_FILE
echo "#        test GraphLab2.2-3: clustering                  #" >> $TEST_RESULT_FILE
echo "##########################################################" >> $TEST_RESULT_FILE

BIN_PATH="$GRAPHLAB_HOME/release/toolkits/clustering"
#------------------01-KMeans++------------------------
PROG=$BIN_PATH/kmeans
check_program
CMD="hamster -v -np 2 $PROG --data=$HDFS_IP_PORT/user/root/graphlab/clustering/synthetic.txt --clusters=2 --output-clusters=$HDFS_IP_PORT/user/root/graphlab/clustering/out_cluster.txt --output-data=$HDFS_IP_PORT/user/root/graphlab/clustering/out_data.txt"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/clustering/out*

END_cluster

##########################################################
#        test GraphLab2.2-4: topic_modeling              #
##########################################################
echo "##########################################################" >> $TEST_RESULT_FILE
echo "#        test GraphLab2.2-4: topic_modeling              #" >> $TEST_RESULT_FILE
echo "##########################################################" >> $TEST_RESULT_FILE

BIN_PATH="$GRAPHLAB_HOME/release/toolkits/topic_modeling"
#cgs_lda proc cannot finished properly, need by manual, and 'yarn application -kill #application_id' 

##########################################################
#        test GraphLab2.2-5: Linear-Solvers              #
##########################################################
echo "##########################################################" >> $TEST_RESULT_FILE
echo "#        test GraphLab2.2-5: Linear-Solvers              #" >> $TEST_RESULT_FILE
echo "##########################################################" >> $TEST_RESULT_FILE

BIN_PATH="$GRAPHLAB_HOME/release/toolkits/linear_solvers"
#---------------------01-Jacobi-----------------------

:<< END_gm
##########################################################
#        test GraphLab2.2-6: graphical-model             #
##########################################################
echo "##########################################################" >> $TEST_RESULT_FILE
echo "#        test GraphLab2.2-6: graphical-model             #">> $TEST_RESULT_FILE
echo "##########################################################" >> $TEST_RESULT_FILE

BIN_PATH="$GRAPHLAB_HOME/release/toolkits/graphical_models"
#---------------------01-Structured-Prediction----------------------
PROG=$BIN_PATH/lbp_structured_prediction
check_program
CMD="hamster -v -np 2 $PROG \
     --prior $HDFS_IP_PORT/user/root/graphlab/graphical_model/synth_vdata.tsv \
     --graph $HDFS_IP_PORT/user/root/graphlab/graphical_model/synth_edata.tsv \
     --output $HDFS_IP_PORT/user/root/graphlab/graphical_model/out_posterior_vdata.tsv"
run_program
check_PROG_if_finished
hadoop fs -rm /user/root/graphlab/graphical_model/out*
END_gm

##########################################################
#                        cleanup                         #
##########################################################
for dir in $TEST_DIR; do
    cd $dir; make clean; cd -
done

exit 0
