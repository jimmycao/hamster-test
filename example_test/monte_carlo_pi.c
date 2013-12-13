/* pi_montecarlo.c
 * PARALLEL [MPI] C PROGRAM TO COMPUTE THE VALUE OF 'PI' USING MONTE CARLO 
 * [DARTBOARD ALGORITHM] METHOD. MASTER COLLECTS THE RESULTS FROM THE WORKERS 
 * USING MPI_Reduce AND AVERAGES THEM.
 *
 * TESTED SUCCESSFULLY WITH MPICH2 (1.3.1) COMPILED AGAINST GCC (4.1.2) 
 * IN A LINUX BOX WITH QUAD CORE INTEL XEON PROCESSOR (1.86 GHz) & 4GB OF RAM.
 *
 * FIRST WRITTEN : GOWTHAM; Fri, 19 Nov 2010 01:11:34 -0500
 * LAST MODIFIED : GOWTHAM; Fri, 19 Nov 2010 03:53:31 -0500
 *
 * URL:
 * http://sgowtham.net/blog/2010/12/02/mpi-c-monte-carlo-method-of-finding-pi/ 
 *
 * COMPILATION:
 * mpicc -g -Wall -lm pi_montecarlo.c -o pi_montecarlo.x 
 *
 * EXECUTION:
 * mpirun -np NPROC -machinefile MACHINEFILE ./pi_montecarlo.x
 *
 * NPROC       : NUMBER OF PROCESSORS ALLOCATED TO RUNNING THIS PROGRAM
 * MACHINEFILE : FILE LISTING THE HOSTNAMES OF PROCESSORS ALLOCATED TO
 *               RUNNING THIS PROGRAM
 *
*/
 
 
/* STANDARD HEADERS AND DEFINITIONS 
 * REFERENCE: http://en.wikipedia.org/wiki/C_standard_library
*/
#include <stdio.h>  /* Core input/output operations                         */
#include <stdlib.h> /* Conversions, random numbers, memory allocation, etc. */
#include <math.h>   /* Common mathematical functions                        */
#include <time.h>   /* Converting between various date/time formats         */
#include <mpi.h>    /* MPI functionality                                    */
#include <sys/time.h> 

#define MASTER             0   /* Process ID of MASTER                      */
#define PI      3.1415926535   /* Known vaue of PI                          */
int  NDARTS =  100000;   /* Number of darts thrown                    */
 
/* FUNCTION 'pseudo_random' BEGINS
 * GIVEN TWO NUMBERS, llimit & ulimit, THIS FUNCTION GENERATES A RANDOM
 * NUMBER BETWEEN llimit & ulimit. SEED FOR rand() COMES FROM THE
 * PARENT FUNCTION, 'pi_dartboard'.
*/
double pseudo_random(double a, double b) {
 
  /* VARIABLE DECLARATION & INITIALIZATION */
  double r;  /* Random number */
 
  /* GENERATE RANDOM NUMBER BETWEEN llimit & ulimit
   * rand() IS USUALLY AN INTEGER & SO IS RAND_MAX
   * (double) rand() and (double) RAND_MAX CONVERTS THEM TO DOUBLE PRECISION
   * USING LINEAR SCALING [REFER TO CLASS NOTES/SLIDES], RANDOM NUMBER IS
   * SCALED TO LIE BETWEEN llimit & ulimit
  */
  r = ((b - a) * ((double) rand()/(double) RAND_MAX)) + a;
 
  /* RETURN THE VALUE OF RANDOM NUMBER
   * INDICATE THE TERMINATION OF THIS MODULE/FUNCTION
  */
  return r;
} /* FUNCTION 'pseudo_random' ENDS */
 
 
/* MAIN PROGRAM BEGINS */
int main (int argc, char *argv[]) {
 
  /* VARIABLE DECLARATION & INITIALIZATION */
  int    proc_id,       /* Process ID                           */
         n_procs,       /* Number of processors                 */
         llimit,        /* Lower limit for random numbers       */
         ulimit,        /* Upper limit for random numbers       */
         n_circle,      /* Number of darts that hit the circle  */
         i;             /* Dummy/Running index                  */
 
  double pi_current,    /* PI calculated by each WORKER         */
         pi_sum,        /* Sum of PI values from each WORKER    */
         x,             /* x coordinate, betwen -1 & +1         */
         y,             /* y coordinate, betwen -1 & +1         */
         z,             /* Sum of x^2 and y^2                   */
         error,         /* Error in calculation of PI           */
         start_time,    /* Wall clock - start time              */
         end_time;      /* Wall clock - end time                */
 
  struct timeval stime;
 
  llimit   = -1;
  ulimit   = 1;
  n_circle = 0;

  if (argc == 2) {
  	NDARTS = atoi(argv[1]);
  }
  /* INITIALIZE MPI */
  MPI_Init(&argc, &argv);
 
  /* GET THE PROCESS ID AND NUMBER OF PROCESSORS */
  MPI_Comm_rank(MPI_COMM_WORLD, &proc_id);
  MPI_Comm_size(MPI_COMM_WORLD, &n_procs);
 
  /* IF MASTER, THEN DO THE FOLLOWING:
   * ACCEPT THE VALUE OF NDARTS FROM COMMAND LINE
   * PRINT THE MESSAGE TO THE SCREEN
   * START THE WALL CLOCK
  */ 
  if (proc_id == MASTER) {
    printf("\n  Monte Carlo method of finding PI\n\n");
    printf("    Number of processors : %d\n", n_procs);
    printf("    Number of darts      : %d\n\n", NDARTS);
 
    /* START THE CLOCK */
    start_time = MPI_Wtime();
  }
 
 
  /* ALL PROCESSORS, INCLUDING MASTER, DO THE FOLLOWING:
   * SEED THE RANDOM NUMBER GENERATOR
   * THROW DARTS AT THE BOARD [FOR LOOP]
   *   COORDINATES OF THE DART [x, y] ARE GENERATED AT RANDOM
   *   CHECK IF THE DART LANDED IN THE CIRCLE
   *   IF YES, INCREMENT THE COUNT
   * CALCULATE THE VALUE OF PI
  */
 
  /* SEED FOR RANDOM NUMBER GENERATOR */
  /* RESULTS IN THE FOLLOWING WARNING - MAY BE IGNORED
   * warning: implicit declaration of function ‚Äògettimeofday‚Äô
  */
  gettimeofday(&stime, NULL);
  srand(stime.tv_usec * stime.tv_usec * stime.tv_usec * stime.tv_usec);
 
  /* THROW NDARTS LOOP BEGINS */
  for (i = 1; i <= NDARTS; i++) {
 
    /* GENERATE RANDOM NUMBERS x & y BETWEEN -1 & +1 */
    x = pseudo_random(llimit, ulimit);
    y = pseudo_random(llimit, ulimit);
 
    /* CALCULATE x^2 + y^2 */
    z = pow(x, 2) + pow(y, 2);
 
    /* IF THE DART IS IN THE CIRCLE, INCREMENT n_circle */
    if (z <= 1.0) {
       n_circle++;
    }
 
  } /* THROW NDARTS LOOP ENDS */
 
  /* CALCULATE THE VALUE OF PI */
  pi_current = 4.0 * (double)n_circle/(double)NDARTS;
 
 
  /* USE MPI_Reduce TO SUM VALUES OF pi_current ACROSS ALL WORKERS
   * THIS HAPPENS ONLY ON MASTER
  */ 
  MPI_Reduce(&pi_current, &pi_sum, 1, MPI_DOUBLE, MPI_SUM, MASTER, MPI_COMM_WORLD);
 
 
  /* IF MASTER, THEN DO THE FOLLOWING
   * CALCULATE THE AVERAGE VALUE OF PI 
   * CALCULATE THE ERROR ASSOCIATED WITH THE COMPUTED VALUE OF PI
   * STOP THE WALL CLOCK
   * PRINT THE RESULTS TO THE SCREEN
  */
  if (proc_id == MASTER) {
 
    /* AVERAGE VALUE OF COMPUTED PI */
    pi_sum = pi_sum / n_procs;
 
    /* % ERROR ASSOCIATED WITH COMPUTED VALUE OF PI */
    error = fabs((pi_sum - PI)/PI) * 100;
 
    /* STOP THE CLOCK */
    end_time = MPI_Wtime();
 
    /* PRINT THE RESULTS TO THE SCREEN */
    printf("    Known value of  PI   : %11.10f\n", PI);
    printf("    Average value of PI  : %11.10f\n", pi_sum);
    printf("    Percentage Error     : %10.8f\n", error);
    printf("    Time elapsed (sec)   : %10.8f\n\n", end_time - start_time);
  }
 
  /* FINALIZE MPI */
  MPI_Finalize();
 
  /* INDICATE THE TERMINATION OF THE PROGRAM */
  return 0;
 
} /* MAIN PROGRAM ENDS */
