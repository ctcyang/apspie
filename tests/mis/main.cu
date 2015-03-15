// Puts everything together
// For now, just run V times.
// Optimizations: 
// -come up with good stopping criteria [done]
// -start from i=1 [done]
// -test whether float really are faster than ints
// -distributed idea
// -change nthread [done - doesn't work]
 
#include <cstdlib>
#include <stdio.h>
#include <cuda_runtime_api.h>
#include <cuda.h>
#include <deque>
#include <cusparse.h>
#include <moderngpu.cuh>

#include <util.cuh>
#include <mis.cuh>
//#include <spmspv.cuh>

#include <string.h>


// A simple CPU-based reference MIS ranking implementation
template<typename VertexId>
int SimpleReferenceMis(
    const VertexId m, const VertexId *h_rowPtrA, const VertexId *h_colIndA,
    VertexId                                *source_path,
    VertexId                                src)
{
    //initialize distances
    for (VertexId i = 0; i < m; ++i) {
        source_path[i] = -1;
    }
    source_path[src] = 1;
    int edges_begin = h_rowPtrA[src];
    int edges_end = h_rowPtrA[src + 1];

    for( int edge=edges_begin; edge<edges_end; edge++ ) {
        VertexId neighbor = h_colIndA[edge];

        if (source_path[neighbor] == -1)
            source_path[neighbor] = 0;
    }
    
    VertexId search_depth = 1;

    //
    //Perform MIS
    //

    CpuTimer cpu_timer;
    cpu_timer.Start();
   
    for( VertexId i=0; i<m; i++ ) {
        if( source_path[i]==-1 ) {
            source_path[i] = 1;
       
            // Locate adjacency list 
            edges_begin = h_rowPtrA[i];
            edges_end = h_rowPtrA[i + 1];

            for( int edge=edges_begin; edge<edges_end; edge++ ) {
                VertexId neighbor = h_colIndA[edge];

                if ( source_path[neighbor]==-1 )
                    source_path[neighbor] = 0;
            }
        }
    }
 
    cpu_timer.Stop();
    float elapsed = cpu_timer.ElapsedMillis();
    search_depth++;

    printf("CPU MIS finished in %lf msec. Search depth is: %d\n", elapsed, search_depth);

    return search_depth;
}

int misCPU( const int src, const int m, const int *h_rowPtr, const int *h_colInd, int *h_misResultCPU ) {

    typedef int VertexId; // Use as the node identifier type

    int depth = SimpleReferenceMis<VertexId>(
        m, h_rowPtr, h_colInd,
        h_misResultCPU,
        src);

    //print_array(h_misResultCPU, m);
    return depth;
}

void runMis(int argc, char**argv) { 
    int m, n, edge;
    mgpu::ContextPtr context = mgpu::CreateCudaDevice(0);

    // Define what filetype edge value should be stored
    typedef float typeVal;

    // File i/o
    // 1. Open file from command-line 
    // -source 1
    freopen(argv[1],"r",stdin);
    int source;
    int device;
    if( parseArgs( argc, argv, source, device )==true ) {
        printf( "Usage: test apple.mtx -source 5\n");
        return;
    }
    //cudaSetDevice(device);
    printf("Testing %s from source %d\n", argv[1], source);
    
    // 2. Reads in number of edges, number of nodes
    readEdge( m, n, edge, stdin );
    printf("Graph has %d nodes, %d edges\n", m, edge);

    // 3. Allocate memory depending on how many edges are present
    typeVal *h_csrValA;
    int *h_csrRowPtrA, *h_csrColIndA, *h_cooRowIndA;
    int *h_misResult, *h_misResultCPU;

    h_csrValA    = (typeVal*)malloc(edge*sizeof(typeVal));
    h_csrRowPtrA = (int*)malloc((m+1)*sizeof(int));
    h_csrColIndA = (int*)malloc(edge*sizeof(int));
    h_cooRowIndA = (int*)malloc(edge*sizeof(int));
    h_misResult = (int*)malloc((m)*sizeof(int));
    h_misResultCPU = (int*)malloc((m)*sizeof(int));

    // 4. Read in graph from .mtx file
    readMtx<typeVal>( edge, h_csrColIndA, h_cooRowIndA, h_csrValA );
    print_array( h_cooRowIndA, m );

    // 5. Allocate GPU memory
    typeVal *d_csrValA;
    int *d_csrRowPtrA, *d_csrColIndA, *d_cooRowIndA;
    typeVal *d_cscValA;
    int *d_cscRowIndA, *d_cscColPtrA;
    int *d_misResult;
    cudaMalloc(&d_misResult, m*sizeof(int));

    cudaMalloc(&d_csrValA, edge*sizeof(typeVal));
    cudaMalloc(&d_csrRowPtrA, (m+1)*sizeof(int));
    cudaMalloc(&d_csrColIndA, edge*sizeof(int));
    cudaMalloc(&d_cooRowIndA, edge*sizeof(int));

    cudaMalloc(&d_cscValA, edge*sizeof(typeVal));
    cudaMalloc(&d_cscRowIndA, edge*sizeof(int));
    cudaMalloc(&d_cscColPtrA, (m+1)*sizeof(int));

    // 6. Copy data from host to device
    cudaMemcpy(d_csrValA, h_csrValA, (edge)*sizeof(typeVal),cudaMemcpyHostToDevice);
    cudaMemcpy(d_csrColIndA, h_csrColIndA, (edge)*sizeof(int),cudaMemcpyHostToDevice);
    cudaMemcpy(d_cooRowIndA, h_cooRowIndA, (edge)*sizeof(int),cudaMemcpyHostToDevice);

    // 7. Run COO -> CSR kernel
    coo2csr( d_cooRowIndA, edge, m, d_csrRowPtrA );

    // 8. Run MIS on CPU. Need data in CSR form first.
    cudaMemcpy(h_csrRowPtrA,d_csrRowPtrA,(m+1)*sizeof(int),cudaMemcpyDeviceToHost);
    int depth = 1000;
    depth = misCPU( source, m, h_csrRowPtrA, h_csrColIndA, h_misResultCPU );
    print_end_interesting(h_misResultCPU, m);

    // Make two GPU timers
    GpuTimer gpu_timer;
    GpuTimer gpu_timer2;
    float elapsed = 0.0f;
    float elapsed2 = 0.0f;
    gpu_timer.Start();

    // 9. Run CSR -> CSC kernel
    csr2csc<typeVal>( m, edge, d_csrValA, d_csrRowPtrA, d_csrColIndA, d_cscValA, d_cscRowIndA, d_cscColPtrA );
    gpu_timer.Stop();
    gpu_timer2.Start();

    // 10. Run MIS kernel on GPU
    //mis( i, edge, m, d_csrValA, d_csrRowPtrA, d_csrColIndA, d_misResult, 5 );
    //mis( 0, edge, m, d_cscValA, d_cscColPtrA, d_cscRowIndA, d_misResult, 5 );

    // 10. Run MIS kernel on GPU
    /*lubyMis( source, edge, m, h_csrRowPtrA, d_csrRowPtrA, d_csrColIndA, d_misResult, depth, *context); 
    //mis( 0, edge, m, d_cscColPtrA, d_cscRowIndA, d_misResult, depth, *context);
    gpu_timer2.Stop();
    elapsed += gpu_timer.ElapsedMillis();
    elapsed2 += gpu_timer2.ElapsedMillis();

    printf("CSR->CSC finished in %f msec. performed %d iterations\n", elapsed, depth-1);
    //printf("GPU MIS finished in %f msec. not including transpose\n", elapsed2);

    cudaMemcpy(h_csrColIndA, d_csrColIndA, edge*sizeof(int), cudaMemcpyDeviceToHost);
    print_array(h_csrColIndA, m);

    // Compare with CPU MIS for errors
    cudaMemcpy(h_misResult,d_misResult,m*sizeof(int),cudaMemcpyDeviceToHost);
    verify( m, h_misResult, h_misResultCPU );
    print_array(h_misResult, m);

    // Compare with SpMV for errors
    cuspMis( 0, edge, m, d_cscColPtrA, d_cscRowIndA, d_misResult, depth, *context);
    cudaMemcpy(h_misResult,d_misResult,m*sizeof(int),cudaMemcpyDeviceToHost);
    verify( m, h_misResult, h_misResultCPU );
    print_array(h_misResult, m);*/
    
    cudaFree(d_csrValA);
    cudaFree(d_csrRowPtrA);
    cudaFree(d_csrColIndA);
    cudaFree(d_cooRowIndA);

    cudaFree(d_cscValA);
    cudaFree(d_cscRowIndA);
    cudaFree(d_cscColPtrA);
    cudaFree(d_misResult);

    free(h_csrValA);
    free(h_csrRowPtrA);
    free(h_csrColIndA);
    free(h_cooRowIndA);
    free(h_misResult);
    free(h_misResultCPU);

    //free(h_cscValA);
    //free(h_cscRowIndA);
    //free(h_cscColPtrA);
}

int main(int argc, char**argv) {
    runMis(argc, argv);
}    
