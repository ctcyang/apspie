// Provides utility functions

#include <ctime>
#include <iostream>
#include <sys/resource.h>
#include <time.h>

template<typename T>
void print_end_interesting( T *array, int length ) {
    int count=0;
    for( int j=length-1;j>=0; j-- ) {
        if( array[(int)j]!=-1) {
            std::cout << "[" << j << "]:" << array[j] << " ";
            count++;
            if( count==9 ) break;
        }
    }
    std::cout << "\n";
}

template<typename T>
void print_end( T *array, int length ) {
    int start = length > 10 ? length-10 : 0;
    for( int j=start;j<length;j++ ) {
        std::cout << array[j] << " ";
    }
    std::cout << "\n";
}

template<typename T>
void print_array( T *array, int length ) {
    if( length>40 ) length=40;
    for( int j=0;j<length;j++ ) {
        std::cout << "[" << j << "]:" << array[j] << " ";
    }
    std::cout << "\n";
}

timespec diff(timespec start, timespec end)
{
    timespec temp;
	if ((end.tv_nsec-start.tv_nsec)<0) {
            temp.tv_sec = end.tv_sec-start.tv_sec-1;
	    temp.tv_nsec = 1000000000+end.tv_nsec-start.tv_nsec;
	} else {
	    temp.tv_sec = end.tv_sec-start.tv_sec;
	    temp.tv_nsec = end.tv_nsec-start.tv_nsec;
	}
    return temp;
}

struct CpuTimer {

#if defined(CLOCK_PROCESS_CPUTIME_ID)

    timespec start;
    timespec stop;

    void Start()
    {
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &start);
    }

    void Stop()
    {
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &stop);
    }

    float ElapsedMillis()
    {
        timespec temp;
        if ((stop.tv_nsec-start.tv_nsec)<0) {
            temp.tv_sec = stop.tv_sec-start.tv_sec-1;
            temp.tv_nsec = 1000000000+stop.tv_nsec-start.tv_nsec;
        } else {
            temp.tv_sec = stop.tv_sec-start.tv_sec;
            temp.tv_nsec = stop.tv_nsec-start.tv_nsec;
        }
        return temp.tv_nsec/1000000.0;
    }

#else

    rusage start;
    rusage stop;

    void Start()
    {
        getrusage(RUSAGE_SELF, &start);
    }

    void Stop()
    {
        getrusage(RUSAGE_SELF, &stop);
    }

    float ElapsedMillis()
    {
        float sec = stop.ru_utime.tv_sec - start.ru_utime.tv_sec;
        float usec = stop.ru_utime.tv_usec - start.ru_utime.tv_usec;

        return (sec * 1000) + (usec /1000);
    }

#endif
};


/******************************************************************************
 * Helper routines for list construction and validation 
 ******************************************************************************/

/**
 * \addtogroup PublicInterface
 * @{
 */

/**
 * @brief Compares the equivalence of two arrays. If incorrect, print the location
 * of the first incorrect value appears, the incorrect value, and the reference
 * value.
 * \return Zero if two vectors are exactly the same, non-zero if there is any difference.
 *
 */
template <typename T>
int CompareResults(T* computed, T* reference, int len, bool verbose = true)
{
    int flag = 0;
    for (int i = 0; i < len; i++) {

        if (computed[i] != reference[i] && flag == 0) {
            printf("\nINCORRECT: [%lu]: ", (unsigned long) i);
            std::cout << computed[i];
            printf(" != ");
            std::cout << reference[i];

            if (verbose) {
                printf("\nresult[...");
                for (size_t j = (i >= 5) ? i - 5 : 0; (j < i + 5) && (j < len); j++) {
                    std::cout << computed[j];
                    printf(", ");
                }
                printf("...]");
                printf("\nreference[...");
                for (size_t j = (i >= 5) ? i - 5 : 0; (j < i + 5) && (j < len); j++) {
                    std::cout << reference[j];
                    printf(", ");
                }
                printf("...]");
            }
            flag += 1;
            //return flag;
        }
        if (computed[i] != reference[i] && flag > 0) flag+=1;
    }
    printf("\n");
    if (flag == 0)
        printf("CORRECT\n");
    return flag;
}

// Verify the result
void verify( const int m, const int *h_bfsResult, const int *h_bfsResultCPU ){
    if (h_bfsResultCPU != NULL) {
        printf("Label Validity: ");
        int error_num = CompareResults(h_bfsResult, h_bfsResultCPU, m, true);
        if (error_num > 0) {
            printf("%d errors occurred.\n", error_num);
        }
    }
}

struct GpuTimer
{
    cudaEvent_t start;
    cudaEvent_t stop;

    GpuTimer()
    {
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
    }

    ~GpuTimer()
    {
        cudaEventDestroy(start);
        cudaEventDestroy(stop);
    }

    void Start()
    {
        cudaEventRecord(start, 0);
    }

    void Stop()
    {
        cudaEventRecord(stop, 0);
    }

    float ElapsedMillis()
    {
        float elapsed;
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&elapsed, start, stop);
        return elapsed;
    }
};

// This function extracts the number of nodes and edges from input file
void readEdge( int &m, int &n, int &edge, FILE *inputFile ) {
    int c = getchar();
    int old_c = 0;
    while( c!=EOF ) {
        if( (old_c==10 || old_c==0) && c!=37 ) {
            ungetc(c, inputFile);
            break;
        }
        old_c = c;
        c=getchar();
    }
    scanf("%d %d %d", &m, &n, &edge);
}

// This function loads a graph from .mtx input file
template<typename typeVal>
void readMtx( int edge, int *h_csrColInd, int *h_cooRowInd, typeVal *h_csrVal ) {
    bool weighted = true;
    int c;
    int csr_max = 0;
    int csr_current = 0;
    int csr_row = 0;
    int csr_first = 0;

    // Currently checks if there are fewer rows than promised
    // Could add check for edges in diagonal of adjacency matrix
    for( int j=0; j<edge; j++ ) {
        if( scanf("%d", &h_csrColInd[j])==EOF ) {
            printf("Error: not enough rows in mtx file.\n");
            break;
        }
        scanf("%d", &h_cooRowInd[j]);

        if( j==0 ) {
            c=getchar();
        }

        if( c!=32 ) {
            h_csrVal[j]=1.0;
            if( j==0 ) weighted = false;
        } else {
            //std::cin >> h_csrVal[j];
            scanf("%f", &h_csrVal[j]);
        }

        h_cooRowInd[j]--;
        h_csrColInd[j]--;

        // Finds max csr row.
        if( j!=0 ) {
            if( h_cooRowInd[j]==0 ) csr_first++;
            if( h_cooRowInd[j]==h_cooRowInd[j-1] )
                csr_current++;
            else {
                csr_current++;
                //printf("New row: Last row %d elements long\n", csr_current);
                if( csr_current > csr_max ) {
                    csr_max = csr_current;
                    csr_current = 0;
                    csr_row = h_cooRowInd[j-1];
                } else
                    csr_current = 0;
            }
        }
    }
    printf("The biggest row was %d with %d elements.\n", csr_row, csr_max);
    printf("The first row has %d elements.\n", csr_first);
    if( weighted==true ) {
        printf("The graph is weighted. ");
    } else {
        printf("The graph is unweighted.\n");
    }
}

bool parseArgs( int argc, char**argv, int &source, int &device ) {
    bool error = false;
    source = 0;
    device = 0;

    if( argc%2!=0 )
        return true;   
 
    for( int i=2; i<argc; i+=2 ) {
       if( strstr(argv[i], "-source") != NULL )
           source = atoi(argv[i+1]);
       else if( strstr(argv[i], "-device") != NULL )
           device = atoi(argv[i+1]);
    }
    return error;
}

void coo2csr( const int *d_cooRowIndA, const int edge, const int m, int *d_csrRowPtrA ) {

    cusparseHandle_t handle;
    cusparseCreate(&handle);

    GpuTimer gpu_timer;
    float elapsed = 0.0f;
    gpu_timer.Start();
    cusparseStatus_t status = cusparseXcoo2csr(handle, d_cooRowIndA, edge, m, d_csrRowPtrA, CUSPARSE_INDEX_BASE_ZERO);
    gpu_timer.Stop();
    elapsed += gpu_timer.ElapsedMillis();
    printf("COO->CSR finished in %f msec. \n", elapsed);

    // Important: destroy handle
    cusparseDestroy(handle);
}

template<typename typeVal>
void csr2csc( const int m, const int edge, const typeVal *d_csrValA, const int *d_csrRowPtrA, const int *d_csrColIndA, typeVal *d_cscValA, int *d_cscRowIndA, int *d_cscColPtrA ) {

    cusparseHandle_t handle;
    cusparseCreate(&handle);

    // For CUDA 4.0
    //cusparseStatus_t status = cusparseScsr2csc(handle, m, m, d_csrValA, d_csrRowPtrA, d_csrColIndA, d_cscValA, d_cscRowIndA, d_cscColPtrA, 1, CUSPARSE_INDEX_BASE_ZERO);

    // For CUDA 5.0+
    cusparseStatus_t status = cusparseScsr2csc(handle, m, m, edge, d_csrValA, d_csrRowPtrA, d_csrColIndA, d_cscValA, d_cscRowIndA, d_cscColPtrA, CUSPARSE_ACTION_SYMBOLIC, CUSPARSE_INDEX_BASE_ZERO);

    // Important: destroy handle
    cusparseDestroy(handle);
}
