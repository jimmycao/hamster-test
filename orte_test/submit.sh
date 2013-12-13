#!/bin/bash
param=$@
DIR=/usr/local/hamster/mpi/orte_test

#program=mpi_no_op  
#program=mpi_barrier
#program=hello
#program=abort
#program=multi_abort
#program=delayed_abort
#program=loop_child
#program=bad_exit
#program=pubsub
#program=hello_barrier
#program=accept
#program=connect
#program=crisscross  #hamster -v -np 2  $DIR/$program 
#program=ziatest
#program=slave



hamster -v -np 20  $DIR/$program 


