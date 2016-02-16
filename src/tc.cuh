// Provides BFS function for GPU

#include <cuda_profiler_api.h>
#include <cusparse.h>
#include "mXv.cuh"
#include "scratch.hpp"

#define NTHREADS 512

// Uses MGPU SpMV
template<typename T>
void spmv( const T *d_inputVector, const int edge, const int m, const T *d_csrValA, const int *d_csrRowPtrA, const int *d_csrColIndA, T *d_spmvResult, mgpu::CudaContext& context) {
    mgpu::SpmvCsrBinary(d_csrValA, d_csrColIndA, edge, d_csrRowPtrA, m, d_inputVector, true, d_spmvResult, (T)0, mgpu::multiplies<T>(), mgpu::plus<T>(), context);
}

// Uses cuSPARSE SpMV
template<typename T>
void cuspmv( const T *d_inputVector, const int edge, const int m, const T *d_csrValA, const int *d_csrRowPtrA, const int *d_csrColIndA, T *d_spmvResult, cusparseHandle_t handle, cusparseMatDescr_t descr ) {

    const float alf = 1;
    const float bet = 0;
    const float *alpha = &alf;
    const float *beta = &bet;

    // For CUDA 5.0+
    cusparseStatus_t status = cusparseScsrmv(handle,                   
                              CUSPARSE_OPERATION_NON_TRANSPOSE, 
                              m, m, edge, 
                              alpha, descr, 
                              d_csrValA, d_csrRowPtrA, d_csrColIndA, 
                              d_inputVector, beta, d_spmvResult );

    switch( status ) {
        case CUSPARSE_STATUS_SUCCESS:
            //printf("spmv multiplication successful!\n");
            break;
        case CUSPARSE_STATUS_NOT_INITIALIZED:
            printf("Error: Library not initialized.\n");
            break;
        case CUSPARSE_STATUS_INVALID_VALUE:
            printf("Error: Invalid parameters m, n, or nnz.\n");
            break;
        case CUSPARSE_STATUS_EXECUTION_FAILED:
            printf("Error: Failed to launch GPU.\n");
            break;
        case CUSPARSE_STATUS_ALLOC_FAILED:
            printf("Error: Resources could not be allocated.\n");
            break;
        case CUSPARSE_STATUS_ARCH_MISMATCH:
            printf("Error: Device architecture does not support.\n");
            break;
        case CUSPARSE_STATUS_INTERNAL_ERROR:
            printf("Error: An internal operation failed.\n");
            break;
        case CUSPARSE_STATUS_MATRIX_TYPE_NOT_SUPPORTED:
            printf("Error: Matrix type not supported.\n");
    }

}

// Uses cuSPARSE SpGEMM
template<typename T>
int spgemm( const int edge, const int m, const T* d_cscValA, const int *d_cscColPtrA, const int *d_cscRowIndA, const T* d_cscValB, const int *d_cscColPtrB, const int *d_cscRowIndB, int *d_cscColPtrC, int *d_cscRowIndC, T *d_cscValC ) {
    
    cusparseHandle_t handle;
    cusparseCreate(&handle);

    cusparseMatDescr_t descr;
    cusparseCreateMatDescr(&descr);

    const float alf = 1;
    const float bet = 0;
    const float *alpha = &alf;
    const float *beta = &bet;

    int baseC, nnzC;
    int *nnzTotalDevHostPtr = &nnzC;
    cudaMalloc( &d_cscColPtrC, (m+1)*sizeof(int));
    cusparseSetPointerMode( handle, CUSPARSE_POINTER_MODE_HOST );

    cusparseStatus_t status = cusparseXcsrgemmNnz( handle,
                              CUSPARSE_OPERATION_NON_TRANSPOSE,
                              CUSPARSE_OPERATION_NON_TRANSPOSE,
                              m, m, m,
                              descr, edge,
                              d_cscColPtrA, d_cscRowIndA,
                              descr, edge,
                              d_cscColPtrB, d_cscRowIndB,
                              descr,
                              d_cscColPtrC, nnzTotalDevHostPtr );

    if( NULL != nnzTotalDevHostPtr )
        nnzC = *nnzTotalDevHostPtr;
    else {
        cudaMemcpy( &nnzC, d_cscColPtrC+m, sizeof(int), cudaMemcpyDeviceToHost );
        cudaMemcpy( &baseC, d_cscColPtrC, sizeof(int), cudaMemcpyDeviceToHost );
        nnzC -= baseC;
    }
    cudaMalloc( &d_cscRowIndC, nnzC*sizeof(int));
    cudaMalloc( &d_cscValC, nnzC*sizeof(float));

    status                  = cusparseScsrgemm( handle,                   
                              CUSPARSE_OPERATION_NON_TRANSPOSE, 
                              CUSPARSE_OPERATION_NON_TRANSPOSE, 
                              m, m, m,
                              descr, edge,
                              d_cscValA, d_cscColPtrA, d_cscRowIndA, 
                              descr, edge,
                              d_cscValB, d_cscColPtrB, d_cscRowIndB,
                              descr,
                              d_cscValC, d_cscColPtrC, d_cscRowIndC );

    switch( status ) {
        case CUSPARSE_STATUS_SUCCESS:
            printf("spgemm multiplication successful!\n");
            break;
        case CUSPARSE_STATUS_NOT_INITIALIZED:
            printf("Error: Library not initialized.\n");
            break;
        case CUSPARSE_STATUS_INVALID_VALUE:
            printf("Error: Invalid parameters m, n, or nnz.\n");
            break;
        case CUSPARSE_STATUS_EXECUTION_FAILED:
            printf("Error: Failed to launch GPU.\n");
            break;
        case CUSPARSE_STATUS_ALLOC_FAILED:
            printf("Error: Resources could not be allocated.\n");
            break;
        case CUSPARSE_STATUS_ARCH_MISMATCH:
            printf("Error: Device architecture does not support.\n");
            break;
        case CUSPARSE_STATUS_INTERNAL_ERROR:
            printf("Error: An internal operation failed.\n");
            break;
        case CUSPARSE_STATUS_MATRIX_TYPE_NOT_SUPPORTED:
            printf("Error: Matrix type not supported.\n");
    }

    // Important: destroy handle
    cusparseDestroy(handle);
    cusparseDestroyMatDescr(descr);
}

__global__ void addResult( int *d_bfsResult, float *d_spmvResult, const int iter, const int length ) {
    const int STRIDE = gridDim.x * blockDim.x;
    for (int idx = (blockIdx.x * blockDim.x) + threadIdx.x; idx < length; idx += STRIDE) {
        //d_bfsResult[idx] = (d_spmvResult[idx]>0.5 && d_bfsResult[idx]<0) ? iter:d_bfsResult[idx];
        if( d_spmvResult[idx]>0.5 && d_bfsResult[idx]<0 ) {
            d_bfsResult[idx] = iter;
        } else d_spmvResult[idx] = 0;
    }
    //int tid = threadIdx.x + blockIdx.x * blockDim.x;

    //while( tid<N ) {
        //d_bfsResult[tid] = (d_spmvResult[tid]>0.5 && d_bfsResult[tid]<0) ? iter : d_bfsResult[tid];
    //    tid += blockDim.x*gridDim.x;
    //}
}

//template< typename T >
void allocScratch( d_scratch **d, const int edge, const int m ) {

    *d = (d_scratch *)malloc(sizeof(d_scratch));
    cudaMalloc(&((*d)->d_cscVecInd), edge*sizeof(int));
    cudaMalloc(&((*d)->d_cscSwapInd), edge*sizeof(int));
    cudaMalloc(&((*d)->d_cscVecVal), edge*sizeof(float));
    cudaMalloc(&((*d)->d_cscSwapVal), edge*sizeof(float));
    cudaMalloc(&((*d)->d_cscTempVal), edge*sizeof(float));

    cudaMalloc(&((*d)->d_cscColGood), edge*sizeof(int));
    cudaMalloc(&((*d)->d_cscColBad), m*sizeof(int));
    cudaMalloc(&((*d)->d_cscColDiff), m*sizeof(int));
    cudaMalloc(&((*d)->d_ones), m*sizeof(int));
    cudaMalloc(&((*d)->d_index), m*sizeof(int));
    cudaMalloc(&((*d)->d_temp_storage), 93184);
    cudaMalloc(&((*d)->d_randVecInd), m*sizeof(int));

    //Host mallocs
    (*d)->h_cscVecInd = (int*) malloc (edge*sizeof(int));
    (*d)->h_cscVecVal = (float*) malloc (edge*sizeof(float));
    (*d)->h_cscColDiff = (int*) malloc (m*sizeof(int));
    (*d)->h_ones = (int*) malloc (m*sizeof(int));
    (*d)->h_index = (int*) malloc (m*sizeof(int));

    (*d)->h_bfsResult = (int*) malloc (m*sizeof(int));
    (*d)->h_spmvResult = (float*) malloc (m*sizeof(float));
    (*d)->h_bfsValA = (float*) malloc (edge*sizeof(float));
}

template< typename T >
void bfs( const int vertex, const int edge, const int m, const T* d_cscValA, const int *d_cscColPtrA, const int *d_cscRowIndA, int *d_bfsResult, const int depth, mgpu::CudaContext& context) {

    cusparseHandle_t handle;
    cusparseCreate(&handle);

    cusparseMatDescr_t descr;
    cusparseCreateMatDescr(&descr);

    // Allocate scratch memory
    d_scratch *d;
    allocScratch( &d, edge, m );

    // Allocate GPU memory for result
    float *d_spmvResult, *d_spmvSwap;
    cudaMalloc(&d_spmvResult, m*sizeof(float));
    cudaMalloc(&d_spmvSwap, m*sizeof(float));

    // Generate initial vector using vertex
    // Generate d_ones, d_index
    for( int i=0; i<m; i++ ) {
        d->h_bfsResult[i]=-1;
        d->h_spmvResult[i]=0.0;
        d->h_ones[i] = 1;
        d->h_index[i] = i;
        if( i==vertex ) {
            d->h_bfsResult[i]=0;
            d->h_spmvResult[i]=1.0;
        }
    }
    cudaMemcpy(d_bfsResult, d->h_bfsResult, m*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_spmvSwap, d->h_spmvResult, m*sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d->d_index, d->h_index, m*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d->d_ones, d->h_ones, m*sizeof(int), cudaMemcpyHostToDevice);

    // Generate d_cscColDiff
    int NBLOCKS = (m+NTHREADS-1)/NTHREADS;
    diff<<<NBLOCKS,NTHREADS>>>(d_cscColPtrA, d->d_cscColDiff, m);

    // Generate values for BFS (cscValA where everything is 1)
    float *d_bfsValA;
    cudaMalloc(&d_bfsValA, edge*sizeof(float));

    for( int i=0; i<edge; i++ ) {
        d->h_bfsValA[i] = 1.0;
    }
    cudaMemcpy(d_bfsValA, d->h_bfsValA, edge*sizeof(float), cudaMemcpyHostToDevice);

    GpuTimer gpu_timer;
    float elapsed = 0.0f;
    gpu_timer.Start();
    cudaProfilerStart();

    //spmv<float>(d_spmvSwap, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvResult, context);
    cuspmv<float>(d_spmvSwap, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvResult, handle, descr);
    //mXv<float>(d_spmvSwap, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvResult, d, context);

    addResult<<<NBLOCKS,NTHREADS>>>( d_bfsResult, d_spmvResult, 1, m);

    for( int i=2; i<depth; i++ ) {
    //for( int i=2; i<5; i++ ) {
        if( i%2==0 ) {
            //spmv<float>( d_spmvResult, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvSwap, context);
            cuspmv<float>( d_spmvResult, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvSwap, handle, descr);
            //mXv<float>( d_spmvResult, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvSwap, d, context);
            addResult<<<NBLOCKS,NTHREADS>>>( d_bfsResult, d_spmvSwap, i, m);
            //cudaMemcpy(h_bfsResult,d_bfsResult, m*sizeof(int), cudaMemcpyDeviceToHost);
            //print_array(h_bfsResult,m);
            //cudaMemcpy(h_spmvResult,d_spmvSwap, m*sizeof(float), cudaMemcpyDeviceToHost);
            //print_array(h_spmvResult,m);
        } else {
            //spmv<float>( d_spmvSwap, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvResult, context);
            cuspmv<float>( d_spmvSwap, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvResult, handle, descr);
            //mXv<float>( d_spmvSwap, edge, m, d_bfsValA, d_cscColPtrA, d_cscRowIndA, d_spmvResult, d, context);
            addResult<<<NBLOCKS,NTHREADS>>>( d_bfsResult, d_spmvResult, i, m);
            //cudaMemcpy(h_bfsResult,d_bfsResult, m*sizeof(int), cudaMemcpyDeviceToHost);
            //print_array(h_bfsResult,m);
            //cudaMemcpy(h_spmvResult,d_spmvResult, m*sizeof(float), cudaMemcpyDeviceToHost);
            //print_array(h_spmvResult,m);
        }
    }

    cudaProfilerStop();
    gpu_timer.Stop();
    elapsed += gpu_timer.ElapsedMillis();
    printf("\nGPU BFS finished in %f msec. \n", elapsed);
    //printf("The maximum frontier size was: %d.\n", frontier_max);
    //printf("The average frontier size was: %d.\n", frontier_sum/depth);

    // Important: destroy handle
    cusparseDestroy(handle);
    cusparseDestroyMatDescr(descr);

    cudaFree(d_spmvResult);
    cudaFree(d_spmvSwap);
}

template< typename T >
int mXm( const int edge, const int m, const T* d_cscValA, const int *d_cscColPtrA, const int *d_cscRowIndA, const T* d_cscValB, const int *h_cscColPtrB, const int *d_cscColPtrB, const int *d_cscRowIndB, int *d_cscColPtrC, int *d_cscRowIndC, T *d_cscValC, mgpu::CudaContext& context) {

    // Allocate scratch memory
    d_scratch *d;
    allocScratch( &d, edge, m );

    // Generate d_ones, d_index
    for( int i=0; i<m; i++ ) {
        d->h_ones[i] = 1;
        d->h_index[i] = i;
    }
    cudaMemcpy(d->d_index, d->h_index, m*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d->d_ones, d->h_ones, m*sizeof(int), cudaMemcpyHostToDevice);

    // Generate d_cscColDiff
    int NBLOCKS = (m+NTHREADS-1)/NTHREADS;
    diff<<<NBLOCKS,NTHREADS>>>(d_cscColPtrA, d->d_cscColDiff, m);

    // Initialize nnz cumulative
    int *h_cscColPtrC = (int*)malloc((m+1)*sizeof(int));
    int total_nnz = 0;
    h_cscColPtrC[0] = total_nnz;
    int nnz = 0;

    GpuTimer gpu_timer;
    float elapsed = 0.0f;
    gpu_timer.Start();
    cudaProfilerStart();

    //for( int i=0; i<m; i++ ) {
    for( int i=0; i<2; i++ ) {
        nnz = h_cscColPtrB[i+1]-h_cscColPtrB[i];
        printf("Reading %d elements in matrix B: %d to %d\n", nnz, h_cscColPtrB[i], h_cscColPtrB[i+1]);
        if( nnz ) {
        mXv<float>(&d_cscRowIndB[h_cscColPtrB[i]], &d_cscValB[h_cscColPtrB[i]], edge, m, nnz, d_cscValA, d_cscColPtrA, d_cscRowIndA, &d_cscRowIndC[total_nnz], &d_cscValC[total_nnz], d, context);
        total_nnz += nnz;
        h_cscColPtrC[i+1] = total_nnz;
        printf("mXv iteration %d: ColPtrC at %d\n", i, total_nnz);
        cudaMemcpy(d->h_bfsResult, d_cscRowIndC, total_nnz*sizeof(int), cudaMemcpyDeviceToHost);
        print_array(d->h_bfsResult,total_nnz);
        cudaMemcpy(d->h_spmvResult, d_cscValC, total_nnz*sizeof(float), cudaMemcpyDeviceToHost);
        print_array(d->h_spmvResult,total_nnz);
        }
    }

    cudaProfilerStop();
    gpu_timer.Stop();
    elapsed += gpu_timer.ElapsedMillis();
    printf("\nGPU mXm finished in %f msec. \n", elapsed);

}
