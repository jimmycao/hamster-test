#include<stdio.h>
#include<mpi.h>

int main(int argc, char *argv[]){
        int rankID, totalNumTasks;

        MPI_Init(&argc, &argv);
        MPI_Barrier(MPI_COMM_WORLD);
        double elapsed_time = -MPI_Wtime();

        MPI_Comm_rank(MPI_COMM_WORLD, &rankID);
        MPI_Comm_size(MPI_COMM_WORLD, &totalNumTasks);

        int sendRecvBuf[3] = {0, 0, 0};

        if(!rankID){
                sendRecvBuf[0] = 3;
                sendRecvBuf[1] = 6;
                sendRecvBuf[2] = 9;
        }

        int count = 3;
        int root = 0;
        MPI_Bcast(sendRecvBuf, count, MPI_INT, root, MPI_COMM_WORLD); //MPI_Bcast can be seen from all processes

        printf("my rankID = %d, sendRecvBuf = {%d, %d, %d}\n", rankID, sendRecvBuf[0], sendRecvBuf[1], sendRecvBuf[2]);

        elapsed_time += MPI_Wtime();
        if(!rankID){
                printf("total elapsed time = %10.6f\n", elapsed_time);
        }

        MPI_Finalize();
        return 0;
}
