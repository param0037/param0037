/**
*    ---------------------------------------------------------------------
*    Author : Wayne
*    Date   : 2021.04.16
*    ---------------------------------------------------------------------
*    This is a part of the open source program named "DECX", copyright c Wayne,
*    2021.04.16
*/

#ifndef _FFT2D_KERNEL_CUH_
#define _FFT2D_KERNEL_CUH_


#include "../../../../core/basic.h"



// because it is in the middle, do not need to worry about CC or RC, it is always CC mode
__global__
void cu_FFT2D_b2_CC_halved(float4*         src,
                           float4*         dst,
                           const int       thr_num,
                           const int       warp_proc_len,
                           const int       warp_len,
                           const int       Height_limit,
                           const int       Wsrc)
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    int map_dex;
    de::complex_f twd_fac(1, 0);

    int _warp,                  // 线程蔟 id
        warp_loc_id;            // 线程蔟本地 id

    if (tidy < thr_num && tidx < Height_limit) {
        _warp = tidy / warp_len;
        warp_loc_id = tidy % warp_len;
        // the location where the first element of each thread' s butterfly operation
        map_dex = _warp * warp_proc_len + warp_loc_id + tidx * Wsrc;

        float4 mid_term[2], tmp;
        
        // 构造旋转因子（单位根, and then rewrite w so that the register memory can be saved
        constructW_f(Two_Pi * __fdividef((float)warp_loc_id, (float)warp_proc_len), &twd_fac);

        tmp = src[map_dex + warp_len];
        C_mul_C2_fp32(tmp, twd_fac, mid_term[1]);

        mid_term[0] = src[map_dex];
        C2_ADD_C2(mid_term[0], mid_term[1], tmp);
        dst[map_dex] = tmp;

        C2_SUB_C2(mid_term[0], mid_term[1], tmp);
        dst[map_dex + warp_len] = tmp;
    }
//#endif
}




__global__
/**
* @brief : A transpose operation is included
*/
void cu_FFT2D_b2_single_clamp_last(float2*         src,
                                   float2*         dst,
                                   const int       warp_proc_len,
                                   const int       warp_len,
                                   const int       thr_num,
                                   const int       height_limit,
                                   const int       Wsrc)
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;
    const size_t dex_base = tidx * Wsrc;
    
    int map_dex;
    de::complex_f twd_fac(1, 0);

    int _warp,                  // 线程蔟 id
        warp_loc_id;            // 线程蔟本地 id

    float2 mid_term[2], tmp;

    if (tidy < thr_num && tidx < height_limit) {
        _warp = tidy / warp_len;
        warp_loc_id = tidy % warp_len;
        // the location where the first element of each thread' s butterfly operation
        map_dex = _warp * warp_proc_len + warp_loc_id;

        // 构造旋转因子（单位根, and then rewrite w so that the register memory can be saved
        constructW_f(Two_Pi * __fdividef((float)warp_loc_id, (float)warp_proc_len), &twd_fac);

        tmp = src[tidy * 2 + 1 + dex_base];
        C_mul_C_fp32(tmp, twd_fac, mid_term[1]);

        mid_term[0] = src[tidy * 2 + dex_base];
        C_ADD_C(mid_term[0], mid_term[1], tmp);
        dst[map_dex * height_limit + tidx] = tmp;

        C_SUB_C(mid_term[0], mid_term[1], tmp);
        dst[(map_dex + warp_len) * height_limit + tidx] = tmp;
    }
//#endif
}



// -------------------------------------------------------Raidx--3---------------------------------------------------------


__global__
/**
if the function is CC, it means that the function is applied at the first or the middle
* THIS FUNCTION IS USED ONLY IN THE MIDDLE
* step of FFT loop, do not need to consider the imaginary part, just put the
* real part into the right place, because the rotation factor is W(k, 0) = 1
*/
void cu_FFT2D_b3_CC_halved(float4*         src,
                           float4*         dst,
                           const int       thr_num,
                           const int       warp_proc_len,            // 一个warp所处理的数组长度 = padded
                           const int       warp_len,
                           const int       height_limit,
                           const int       Wsrc)                     // 线程蔟长度
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    bool is_in = tidy < thr_num && tidx < height_limit;

    if (is_in)
    {
        int warp_ID = tidy / warp_len,
            warp_loc_ID = tidy % warp_len;

        int init_dex = warp_ID * warp_proc_len + warp_loc_ID + tidx * Wsrc;   // 线程DFT操作的起始引脚

        de::CPf twd_fac;
        float4 mid_term[3], tmp;

        mid_term[0] = src[init_dex];

        tmp = src[init_dex + warp_len];
        constructW_f(__fmul_rn(Two_Pi, __fdividef((float)warp_loc_ID, (float)warp_proc_len)), &twd_fac);
        C_mul_C2_fp32(tmp, twd_fac, mid_term[1]);

        tmp = src[init_dex + (warp_len << 1)];
        constructW_f(__fmul_rn(Two_Pi, __fdividef((float)(warp_loc_ID << 1), (float)warp_proc_len)), &twd_fac);
        C_mul_C2_fp32(tmp, twd_fac, mid_term[2]);

        C_SUM3(mid_term, x, tmp);
        C_SUM3(mid_term, y, tmp);
        C_SUM3(mid_term, z, tmp);
        C_SUM3(mid_term, w, tmp);
        dst[init_dex] = tmp;

        tmp = mid_term[0];
        C_FMA_C2_fp32_constant(mid_term[1], -0.5f, 0.8660254f, tmp);
        C_FMA_C2_fp32_constant(mid_term[2], -0.5f, -0.8660254f, tmp);
        dst[init_dex + warp_len] = tmp;

        tmp = mid_term[0];
        C_FMA_C2_fp32_constant(mid_term[1], -0.5f, -0.8660254f, tmp);
        C_FMA_C2_fp32_constant(mid_term[2], -0.5f, 0.8660254f, tmp);
        dst[init_dex + (warp_len << 1)] = tmp;
    }
//#endif
}




__global__
/**
if the function is CC, it means that the function is applied at the first or the middle
* THIS FUNCTION IS USED ONLY IN THE MIDDLE
* step of FFT loop, do not need to consider the imaginary part, just put the
* real part into the right place, because the rotation factor is W(k, 0) = 1
*/
void cu_FFT2D_b3_CC(float2*         src,
                    float2*         dst,
                    const int       thr_num,
                    const int       warp_proc_len,            // 一个warp所处理的数组长度 = padded
                    const int       warp_len,
                    const int       height_limit,
                    const int       Wsrc)                 // 线程蔟长度
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    bool is_in = tidy < thr_num && tidx < height_limit;

    if (is_in)
    {
        int warp_ID = tidy / warp_len,
            warp_loc_ID = tidy % warp_len;

        int init_dex = warp_ID * warp_proc_len + warp_loc_ID + tidx * Wsrc;   // 线程DFT操作的起始引脚

        de::CPf twd_fac;
        float2 mid_term[3], tmp;

        mid_term[0] = src[init_dex];

        tmp = src[init_dex + warp_len];
        constructW_f(__fmul_rn(Two_Pi, __fdividef((float)warp_loc_ID, (float)warp_proc_len)), &twd_fac);
        C_mul_C_fp32(tmp, twd_fac, mid_term[1]);

        tmp = src[init_dex + (warp_len << 1)];
        constructW_f(__fmul_rn(Two_Pi, __fdividef((float)(warp_loc_ID << 1), (float)warp_proc_len)), &twd_fac);
        C_mul_C_fp32(tmp, twd_fac, mid_term[2]);

        C_SUM3(mid_term, x, tmp);
        C_SUM3(mid_term, y, tmp);
        dst[init_dex] = tmp;

        tmp = mid_term[0];
        C_FMA_C_fp32_constant(mid_term[1], -0.5f, 0.8660254f, tmp);
        C_FMA_C_fp32_constant(mid_term[2], -0.5f, -0.8660254f, tmp);
        dst[init_dex + warp_len] = tmp;

        tmp = mid_term[0];
        C_FMA_C_fp32_constant(mid_term[1], -0.5f, -0.8660254f, tmp);
        C_FMA_C_fp32_constant(mid_term[2], -0.5f, 0.8660254f, tmp);
        dst[init_dex + (warp_len << 1)] = tmp;
    }
//#endif
}




__global__
/**
if the function is CC, it means that the function is applied at the first or the middle
* THIS FUNCTION IS USED ONLY IN THE MIDDLE
* step of FFT loop, do not need to consider the imaginary part, just put the
* real part into the right place, because the rotation factor is W(k, 0) = 1
*/
void cu_FFT2D_b3_CC_trans(float2*         src,
                          float2*         dst,
                          const int       thr_num,
                          const int       warp_proc_len,            // 一个warp所处理的数组长度 = padded
                          const int       warp_len,
                          const int       height_limit,
                          const int       Wsrc)                 // 线程蔟长度
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    bool is_in = tidy < thr_num && tidx < height_limit;

    if (is_in)
    {
        int warp_ID = tidy / warp_len,
            warp_loc_ID = tidy % warp_len;

        int init_dex = warp_ID * warp_proc_len + warp_loc_ID;   // 线程DFT操作的起始引脚

        de::CPf twd_fac;
        float2 mid_term[3], tmp;

        mid_term[0] = src[init_dex + tidx * Wsrc];

        tmp = src[init_dex + warp_len + tidx * Wsrc];
        constructW_f(__fmul_rn(Two_Pi, __fdividef((float)warp_loc_ID, (float)warp_proc_len)), &twd_fac);
        C_mul_C_fp32(tmp, twd_fac, mid_term[1]);

        tmp = src[init_dex + (warp_len << 1) + tidx * Wsrc];
        constructW_f(__fmul_rn(Two_Pi, __fdividef((float)(warp_loc_ID << 1), (float)warp_proc_len)), &twd_fac);
        C_mul_C_fp32(tmp, twd_fac, mid_term[2]);

        C_SUM3(mid_term, x, tmp);
        C_SUM3(mid_term, y, tmp);
        dst[init_dex * height_limit + tidx] = tmp;

        tmp = mid_term[0];
        C_FMA_C_fp32_constant(mid_term[1], -0.5f, 0.8660254f, tmp);
        C_FMA_C_fp32_constant(mid_term[2], -0.5f, -0.8660254f, tmp);
        dst[(init_dex + warp_len) * height_limit + tidx] = tmp;

        tmp = mid_term[0];
        C_FMA_C_fp32_constant(mid_term[1], -0.5f, -0.8660254f, tmp);
        C_FMA_C_fp32_constant(mid_term[2], -0.5f, 0.8660254f, tmp);
        dst[(init_dex + (warp_len << 1)) * height_limit + tidx] = tmp;
    }
//#endif
}



// ----------------------------------------------Radix--4------------------------------------------------------------------




__global__
/**
* pay attention to that this kernel requires for dynamic share memory
* spread some threads on row dimension to process some datas
*/
void cu_FFT2D_b4_CC_halved(float4*          src,
                           float4*          dst,
                           const int        thr_num,
                           const int        warp_proc_len,
                           const int        warp_len,
                           const int        height_limit,
                           const int        Wsrc)
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    bool is_in = tidy < thr_num && tidx < height_limit;

    int warp_ID = tidy / warp_len,
        warp_loc_ID = tidy % warp_len;

    int init_dex = warp_ID * warp_proc_len + warp_loc_ID + tidx * Wsrc;

    float4 CmulC_buffer[4];                    // 复数乘法的中间缓存，同时也是 Wn,k 的缓存
    float4 tmp;
    de::CPf res;

    if (is_in)
    {
        tmp = src[init_dex];
        CmulC_buffer[0] = tmp;                  // X1(K)

        constructW_f(Two_Pi * __fdividef((float)warp_loc_ID, (float)warp_proc_len), &res);
        tmp = src[init_dex + warp_len];
        C_mul_C2_fp32(tmp, res, CmulC_buffer[1]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID << 1), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len << 1)];
        C_mul_C2_fp32(tmp, res, CmulC_buffer[2]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID * 3), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len * 3)];
        C_mul_C2_fp32(tmp, res, CmulC_buffer[3]);   // X2(k) * Wn,k

        C_SUM4(x);
        C_SUM4(y);
        C_SUM4(z);
        C_SUM4(w);

        dst[init_dex] = tmp;

        // the second one
        {
            tmp = CmulC_buffer[0];
            tmp.x = __fsub_rn(tmp.x, CmulC_buffer[1].y);
            tmp.y = __fadd_rn(tmp.y, CmulC_buffer[1].x);
            tmp.z = __fsub_rn(tmp.z, CmulC_buffer[1].w);
            tmp.w = __fadd_rn(tmp.w, CmulC_buffer[1].z);

            tmp.x = __fsub_rn(tmp.x, CmulC_buffer[2].x);
            tmp.y = __fsub_rn(tmp.y, CmulC_buffer[2].y);
            tmp.z = __fsub_rn(tmp.z, CmulC_buffer[2].z);
            tmp.w = __fsub_rn(tmp.w, CmulC_buffer[2].w);

            tmp.x = __fadd_rn(tmp.x, CmulC_buffer[3].y);
            tmp.y = __fsub_rn(tmp.y, CmulC_buffer[3].x);
            tmp.z = __fadd_rn(tmp.z, CmulC_buffer[3].w);
            tmp.w = __fsub_rn(tmp.w, CmulC_buffer[3].z);

            dst[init_dex + warp_len] = tmp;
        }
        // the thrid one
        {
            tmp = CmulC_buffer[0];        // reset
            tmp.x = __fsub_rn(tmp.x, CmulC_buffer[1].x);
            tmp.y = __fsub_rn(tmp.y, CmulC_buffer[1].y);
            tmp.z = __fsub_rn(tmp.z, CmulC_buffer[1].z);
            tmp.w = __fsub_rn(tmp.w, CmulC_buffer[1].w);

            tmp.x = __fadd_rn(tmp.x, CmulC_buffer[2].x);
            tmp.y = __fadd_rn(tmp.y, CmulC_buffer[2].y);
            tmp.z = __fadd_rn(tmp.z, CmulC_buffer[2].z);
            tmp.w = __fadd_rn(tmp.w, CmulC_buffer[2].w);

            tmp.x = __fsub_rn(tmp.x, CmulC_buffer[3].x);
            tmp.y = __fsub_rn(tmp.y, CmulC_buffer[3].y);
            tmp.z = __fsub_rn(tmp.z, CmulC_buffer[3].z);
            tmp.w = __fsub_rn(tmp.w, CmulC_buffer[3].w);
            
            dst[init_dex + (warp_len << 1)] = tmp;
        }
        // the fourth one
        {
            tmp = CmulC_buffer[0];        // reset
            tmp.x = __fadd_rn(tmp.x, CmulC_buffer[1].y);
            tmp.y = __fsub_rn(tmp.y, CmulC_buffer[1].x);
            tmp.z = __fadd_rn(tmp.z, CmulC_buffer[1].w);
            tmp.w = __fsub_rn(tmp.w, CmulC_buffer[1].z);

            tmp.x = __fsub_rn(tmp.x, CmulC_buffer[2].x);
            tmp.y = __fsub_rn(tmp.y, CmulC_buffer[2].y);
            tmp.z = __fsub_rn(tmp.z, CmulC_buffer[2].z);
            tmp.w = __fsub_rn(tmp.w, CmulC_buffer[2].w);

            tmp.x = __fsub_rn(tmp.x, CmulC_buffer[3].y);
            tmp.y = __fadd_rn(CmulC_buffer[3].x, tmp.y);
            tmp.z = __fsub_rn(tmp.z, CmulC_buffer[3].w);
            tmp.w = __fadd_rn(CmulC_buffer[3].z, tmp.w);

            dst[init_dex + (warp_len * 3)] = tmp;
        }
    }
//#endif
}




__global__
/**
* 这个核有问题, 这个内核，一个grid有多少个block， 应为总长度除以每个block处理的长度！！！
* @brief : Because it is in the middle, do not need to worry about CC or RC, it is always CC mode
* The UPPER_LIMIT of number of threads per block is 256, and the maximum elements a block
* can process is 1024 (4x4x4x4 x4)
*/
void cu_FFT2D_b4_CC_consec128_halved(float4*         src,
                                     float4*         dst,
                                     const int       thread_num_limit,      // for block
                                     const int       __iter,
                                     const int       height_limit,
                                     const int       Wsrc)
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * thread_num_limit;
    const size_t base_dex = tidx * Wsrc;

    __shared__ float4 local_fragment[256 * 4];

    float4 CmulC_buffer[4];                    // 复数乘法的中间缓存，同时也是 Wn,k 的缓存
    float4 tmp;
    de::CPf res;

    int warp_len = 1, warp_proc_len = 1;

    int init_dex,
        warp_id,                  // 线程蔟 id
        warp_loc_id;              // 线程蔟本地 id

    if (threadIdx.y < thread_num_limit && tidx < height_limit) {
        local_fragment[threadIdx.y * 4 + threadIdx.x * thread_num_limit * 4] = src[tidy * 4 + base_dex];
        local_fragment[threadIdx.y * 4 + 1 + threadIdx.x * thread_num_limit * 4] = src[tidy * 4 + 1 + base_dex];
        local_fragment[threadIdx.y * 4 + 2 + threadIdx.x * thread_num_limit * 4] = src[tidy * 4 + 2 + base_dex];
        local_fragment[threadIdx.y * 4 + 3 + threadIdx.x * thread_num_limit * 4] = src[tidy * 4 + 3 + base_dex];
    }

    __syncthreads();

    if (threadIdx.y < thread_num_limit && tidx < height_limit)
    {
        for (int i = 0; i < __iter; ++i) 
        {
            warp_proc_len *= 4;

            warp_id = threadIdx.y / warp_len;
            warp_loc_id = threadIdx.y % warp_len;
            // the location where the first element of each thread' s butterfly operation
            init_dex = warp_id * warp_proc_len + warp_loc_id + threadIdx.x * thread_num_limit * 4;

            tmp = local_fragment[init_dex];
            CmulC_buffer[0] = tmp;                  // X1(K)

            constructW_f(Two_Pi * __fdividef((float)warp_loc_id, (float)warp_proc_len), &res);
            tmp = local_fragment[init_dex + warp_len];
            C_mul_C2_fp32(tmp, res, CmulC_buffer[1]);   // X2(k) * Wn,k

            constructW_f(Two_Pi * __fdividef((float)(warp_loc_id << 1), (float)warp_proc_len), &res);
            tmp = local_fragment[init_dex + (warp_len << 1)];
            C_mul_C2_fp32(tmp, res, CmulC_buffer[2]);   // X2(k) * Wn,k

            constructW_f(Two_Pi * __fdividef((float)(warp_loc_id * 3), (float)warp_proc_len), &res);
            tmp = local_fragment[init_dex + (warp_len * 3)];
            C_mul_C2_fp32(tmp, res, CmulC_buffer[3]);   // X2(k) * Wn,k

            C_SUM4(x);
            C_SUM4(y);
            C_SUM4(z);
            C_SUM4(w);

            local_fragment[init_dex] = tmp;

            // the second one
            {
                tmp = CmulC_buffer[0];
                tmp.x = __fsub_rn(tmp.x, CmulC_buffer[1].y);
                tmp.y = __fadd_rn(tmp.y, CmulC_buffer[1].x);
                tmp.z = __fsub_rn(tmp.z, CmulC_buffer[1].w);
                tmp.w = __fadd_rn(tmp.w, CmulC_buffer[1].z);

                tmp.x = __fsub_rn(tmp.x, CmulC_buffer[2].x);
                tmp.y = __fsub_rn(tmp.y, CmulC_buffer[2].y);
                tmp.z = __fsub_rn(tmp.z, CmulC_buffer[2].z);
                tmp.w = __fsub_rn(tmp.w, CmulC_buffer[2].w);

                tmp.x = __fadd_rn(tmp.x, CmulC_buffer[3].y);
                tmp.y = __fsub_rn(tmp.y, CmulC_buffer[3].x);
                tmp.z = __fadd_rn(tmp.z, CmulC_buffer[3].w);
                tmp.w = __fsub_rn(tmp.w, CmulC_buffer[3].z);

                local_fragment[init_dex + warp_len] = tmp;
            }
            // the thrid one
            {
                tmp = CmulC_buffer[0];        // reset
                tmp.x = __fsub_rn(tmp.x, CmulC_buffer[1].x);
                tmp.y = __fsub_rn(tmp.y, CmulC_buffer[1].y);
                tmp.z = __fsub_rn(tmp.z, CmulC_buffer[1].z);
                tmp.w = __fsub_rn(tmp.w, CmulC_buffer[1].w);

                tmp.x = __fadd_rn(tmp.x, CmulC_buffer[2].x);
                tmp.y = __fadd_rn(tmp.y, CmulC_buffer[2].y);
                tmp.z = __fadd_rn(tmp.z, CmulC_buffer[2].z);
                tmp.w = __fadd_rn(tmp.w, CmulC_buffer[2].w);

                tmp.x = __fsub_rn(tmp.x, CmulC_buffer[3].x);
                tmp.y = __fsub_rn(tmp.y, CmulC_buffer[3].y);
                tmp.z = __fsub_rn(tmp.z, CmulC_buffer[3].z);
                tmp.w = __fsub_rn(tmp.w, CmulC_buffer[3].w);
                
                local_fragment[init_dex + (warp_len << 1)] = tmp;
            }
            // the fourth one
            {
                tmp = CmulC_buffer[0];        // reset
                tmp.x = __fadd_rn(tmp.x, CmulC_buffer[1].y);
                tmp.y = __fsub_rn(tmp.y, CmulC_buffer[1].x);
                tmp.z = __fadd_rn(tmp.z, CmulC_buffer[1].w);
                tmp.w = __fsub_rn(tmp.w, CmulC_buffer[1].z);

                tmp.x = __fsub_rn(tmp.x, CmulC_buffer[2].x);
                tmp.y = __fsub_rn(tmp.y, CmulC_buffer[2].y);
                tmp.z = __fsub_rn(tmp.z, CmulC_buffer[2].z);
                tmp.w = __fsub_rn(tmp.w, CmulC_buffer[2].w);

                tmp.x = __fsub_rn(tmp.x, CmulC_buffer[3].y);
                tmp.y = __fadd_rn(CmulC_buffer[3].x, tmp.y);
                tmp.z = __fsub_rn(tmp.z, CmulC_buffer[3].w);
                tmp.w = __fadd_rn(CmulC_buffer[3].z, tmp.w);

                local_fragment[init_dex + (warp_len * 3)] = tmp;
            }

            warp_len *= 4;

            __syncthreads();
        }

        dst[tidy * 4 + base_dex] = local_fragment[threadIdx.y * 4 + threadIdx.x * thread_num_limit * 4];
        dst[tidy * 4 + 1 + base_dex] = local_fragment[threadIdx.y * 4 + 1 + threadIdx.x * thread_num_limit * 4];
        dst[tidy * 4 + 2 + base_dex] = local_fragment[threadIdx.y * 4 + 2 + threadIdx.x * thread_num_limit * 4];
        dst[tidy * 4 + 3 + base_dex] = local_fragment[threadIdx.y * 4 + 3 + threadIdx.x * thread_num_limit * 4];
    }
//#endif
}




// ----------------------------------------------Radix--5-----------------------------------------------


__global__
/**
* pay attention to that this kernel requires for dynamic share memory
* spread some threads on row dimension to process some datas
*/
void cu_FFT2D_b5_CC_halved(float4*         src,
                           float4*         dst,
                           const int       thr_num,
                           const int       warp_proc_len,
                           const int       warp_len,
                           const int       height_limit,
                           const int       Wsrc)
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    bool is_in = tidy < thr_num;

    int warp_ID = tidy / warp_len,
        warp_loc_ID = tidy % warp_len;

    int init_dex = warp_ID * warp_proc_len + warp_loc_ID + Wsrc * tidx;

    float4 CmulC_buffer[5];                    // 复数乘法的中间缓存，同时也是 Wn,k 的缓存
    float4 tmp;
    de::CPf res;

    if (is_in)
    {
        tmp = src[init_dex];
        CmulC_buffer[0] = tmp;                  // X1(K)

        constructW_f(Two_Pi * __fdividef((float)warp_loc_ID, (float)warp_proc_len), &res);
        tmp = src[init_dex + warp_len];
        C_mul_C2_fp32(tmp, res, CmulC_buffer[1]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID << 1), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len << 1)];
        C_mul_C2_fp32(tmp, res, CmulC_buffer[2]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID * 3), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len * 3)];
        C_mul_C2_fp32(tmp, res, CmulC_buffer[3]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID << 2), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len << 2)];
        C_mul_C2_fp32(tmp, res, CmulC_buffer[4]);   // X2(k) * Wn,k

        C_SUM5(x);
        C_SUM5(y);
        C_SUM5(z);
        C_SUM5(w);

        dst[init_dex] = tmp;

        /*
        * W5,1 = 0.309017 + j 0.9510565
        * W5,2 = -0.809017 + j 0.5877853
        * W5,3 = -0.809017 - j 0.5877852
        * W5,4 = 0.309017 - j 0.9510565
        */
        tmp = CmulC_buffer[0];

        // the second one
        {
            C_FMA_C2_fp32_constant(CmulC_buffer[1], 0.309017, 0.9510565, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[2], -0.809017, 0.5877853, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[3], -0.809017, -0.5877853, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[4], 0.309017, -0.9510565, tmp);

            dst[init_dex + warp_len] = tmp;
        }
        // the thrid one
        {
            tmp = CmulC_buffer[0];        // reset
            C_FMA_C2_fp32_constant(CmulC_buffer[1], -0.809017, 0.5877853, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[2], 0.309017, -0.9510565, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[3], 0.309017, 0.9510565, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[4], -0.809017, -0.5877853, tmp);

            dst[init_dex + (warp_len << 1)] = tmp;
        }
        // the fourth one
        {
            tmp = CmulC_buffer[0];        // reset
            C_FMA_C2_fp32_constant(CmulC_buffer[1], -0.809017, -0.5877853, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[2], 0.309017, 0.9510565, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[3], 0.309017, -0.9510565, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[4], -0.809017, 0.5877853, tmp);

            dst[init_dex + (warp_len * 3)] = tmp;
        }
        // the fifth one
        {
            tmp = CmulC_buffer[0];        // reset

            C_FMA_C2_fp32_constant(CmulC_buffer[1], 0.309017, -0.9510565, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[2], -0.809017, -0.5877853, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[3], -0.809017, 0.5877853, tmp);
            C_FMA_C2_fp32_constant(CmulC_buffer[4], 0.309017, 0.9510565, tmp);

            dst[init_dex + (warp_len << 2)] = tmp;
        }
    }
//#endif
}




__global__
/**
* pay attention to that this kernel requires for dynamic share memory
* spread some threads on row dimension to process some datas
*/
void cu_FFT2D_b5_CC(float2*         src,
                    float2*         dst,
                    const int       thr_num,
                    const int       warp_proc_len,
                    const int       warp_len,
                    const int       height_limit,
                    const int       Wsrc)
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    bool is_in = tidy < thr_num && tidx < height_limit;

    int warp_ID = tidy / warp_len,
        warp_loc_ID = tidy % warp_len;

    int init_dex = warp_ID * warp_proc_len + warp_loc_ID + tidx * Wsrc;

    float2 CmulC_buffer[5];                    // 复数乘法的中间缓存，同时也是 Wn,k 的缓存
    float2 tmp;
    de::CPf res;

    if (is_in)
    {
        tmp = src[init_dex];
        CmulC_buffer[0] = tmp;                  // X1(K)

        constructW_f(Two_Pi * __fdividef((float)warp_loc_ID, (float)warp_proc_len), &res);
        tmp = src[init_dex + warp_len];
        C_mul_C_fp32(tmp, res, CmulC_buffer[1]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID << 1), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len << 1)];
        C_mul_C_fp32(tmp, res, CmulC_buffer[2]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID * 3), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len * 3)];
        C_mul_C_fp32(tmp, res, CmulC_buffer[3]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID << 2), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len << 2)];
        C_mul_C_fp32(tmp, res, CmulC_buffer[4]);   // X2(k) * Wn,k

        C_SUM5(x);
        C_SUM5(y);

        dst[init_dex] = tmp;

        /*
        * W5,1 = 0.309017 + j 0.9510565
        * W5,2 = -0.809017 + j 0.5877853
        * W5,3 = -0.809017 - j 0.5877852
        * W5,4 = 0.309017 - j 0.9510565
        */
        tmp = CmulC_buffer[0];

        // the second one
        {
            C_FMA_C_fp32_constant(CmulC_buffer[1], 0.309017, 0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], -0.809017, 0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], -0.809017, -0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], 0.309017, -0.9510565, tmp);

            dst[init_dex + warp_len] = tmp;
        }
        // the thrid one
        {
            tmp = CmulC_buffer[0];        // reset
            C_FMA_C_fp32_constant(CmulC_buffer[1], -0.809017, 0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], 0.309017, -0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], 0.309017, 0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], -0.809017, -0.5877853, tmp);

            dst[init_dex + (warp_len << 1)] = tmp;
        }
        // the fourth one
        {
            tmp = CmulC_buffer[0];        // reset
            C_FMA_C_fp32_constant(CmulC_buffer[1], -0.809017, -0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], 0.309017, 0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], 0.309017, -0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], -0.809017, 0.5877853, tmp);

            dst[init_dex + (warp_len * 3)] = tmp;
        }
        // the fifth one
        {
            tmp = CmulC_buffer[0];        // reset

            C_FMA_C_fp32_constant(CmulC_buffer[1], 0.309017, -0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], -0.809017, -0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], -0.809017, 0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], 0.309017, 0.9510565, tmp);

            dst[init_dex + (warp_len << 2)] = tmp;
        }
    }
//#endif
}




__global__
/**
* pay attention to that this kernel requires for dynamic share memory
* spread some threads on row dimension to process some datas
*/
void cu_FFT2D_b5_CC_trans(float2*         src,
                          float2*         dst,
                          const int       thr_num,
                          const int       warp_proc_len,
                          const int       warp_len,
                          const int       height_limit,
                          const int       Wsrc)
{
//#ifdef __CUDACC__
    const int tidx = threadIdx.x + blockIdx.x * blockDim.x;
    const int tidy = threadIdx.y + blockIdx.y * blockDim.y;

    bool is_in = tidy < thr_num && tidx < height_limit;

    int warp_ID = tidy / warp_len,
        warp_loc_ID = tidy % warp_len;

    int init_dex = warp_ID * warp_proc_len + warp_loc_ID;

    float2 CmulC_buffer[5];                    // 复数乘法的中间缓存，同时也是 Wn,k 的缓存
    float2 tmp;
    de::CPf res;

    if (is_in)
    {
        tmp = src[init_dex + tidx * Wsrc];
        CmulC_buffer[0] = tmp;                  // X1(K)

        constructW_f(Two_Pi * __fdividef((float)warp_loc_ID, (float)warp_proc_len), &res);
        tmp = src[init_dex + warp_len + tidx * Wsrc];
        C_mul_C_fp32(tmp, res, CmulC_buffer[1]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID << 1), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len << 1) + tidx * Wsrc];
        C_mul_C_fp32(tmp, res, CmulC_buffer[2]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID * 3), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len * 3) + tidx * Wsrc];
        C_mul_C_fp32(tmp, res, CmulC_buffer[3]);   // X2(k) * Wn,k

        constructW_f(Two_Pi * __fdividef((float)(warp_loc_ID << 2), (float)warp_proc_len), &res);
        tmp = src[init_dex + (warp_len << 2) + tidx * Wsrc];
        C_mul_C_fp32(tmp, res, CmulC_buffer[4]);   // X2(k) * Wn,k

        C_SUM5(x);
        C_SUM5(y);

        dst[init_dex * height_limit + tidx] = tmp;

        /*
        * W5,1 = 0.309017 + j 0.9510565
        * W5,2 = -0.809017 + j 0.5877853
        * W5,3 = -0.809017 - j 0.5877852
        * W5,4 = 0.309017 - j 0.9510565
        */
        tmp = CmulC_buffer[0];

        // the second one
        {
            C_FMA_C_fp32_constant(CmulC_buffer[1], 0.309017, 0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], -0.809017, 0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], -0.809017, -0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], 0.309017, -0.9510565, tmp);

            dst[(init_dex + warp_len) * height_limit + tidx] = tmp;
        }
        // the thrid one
        {
            tmp = CmulC_buffer[0];        // reset
            C_FMA_C_fp32_constant(CmulC_buffer[1], -0.809017, 0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], 0.309017, -0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], 0.309017, 0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], -0.809017, -0.5877853, tmp);

            dst[(init_dex + (warp_len << 1)) * height_limit + tidx] = tmp;
        }
        // the fourth one
        {
            tmp = CmulC_buffer[0];        // reset
            C_FMA_C_fp32_constant(CmulC_buffer[1], -0.809017, -0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], 0.309017, 0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], 0.309017, -0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], -0.809017, 0.5877853, tmp);

            dst[(init_dex + (warp_len * 3)) * height_limit + tidx] = tmp;
        }
        // the fifth one
        {
            tmp = CmulC_buffer[0];        // reset

            C_FMA_C_fp32_constant(CmulC_buffer[1], 0.309017, -0.9510565, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[2], -0.809017, -0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[3], -0.809017, 0.5877853, tmp);
            C_FMA_C_fp32_constant(CmulC_buffer[4], 0.309017, 0.9510565, tmp);

            dst[(init_dex + (warp_len << 2)) * height_limit + tidx] = tmp;
        }
    }
//#endif
}


#endif          // #ifndef _FFT2D_KERNEL_CUH_