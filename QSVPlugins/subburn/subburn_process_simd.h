﻿//  -----------------------------------------------------------------------------------------
//    QSVEnc by rigaya
//  -----------------------------------------------------------------------------------------
//   ソースコードについて
//   ・無保証です。
//   ・本ソースコードを使用したことによるいかなる損害・トラブルについてrigayaは責任を負いません。
//   以上に了解して頂ける場合、本ソースコードの使用、複製、改変、再頒布を行って頂いて構いません。
//  -----------------------------------------------------------------------------------------

#pragma once
#include <cstdint>
#include <emmintrin.h> //SSE2
#if USE_SSSE3
#include <tmmintrin.h> //SSSE3
#endif
#if USE_SSE41
#include <smmintrin.h>
#endif
#if USE_AVX
#include <immintrin.h>
#endif
#include "qsv_simd.h"

#if USE_AVX2
#define MEM_ALIGN 32
#else
#define MEM_ALIGN 16
#endif

//SSSE3のpalignrもどき
#define palignr_sse2(a,b,i) _mm_or_si128( _mm_slli_si128(a, 16-i), _mm_srli_si128(b, i) )

#if USE_SSSE3
#define _mm_alignr_epi8_simd _mm_alignr_epi8
#else
#define _mm_alignr_epi8_simd palignr_sse2
#endif

#if USE_SSE41
#define _mm_blendv_epi8_simd _mm_blendv_epi8
#else
static inline __m128i select_by_mask(__m128i a, __m128i b, __m128i mask) {
    return _mm_or_si128( _mm_andnot_si128(mask,a), _mm_and_si128(b,mask) );
}
#define _mm_blendv_epi8_simd select_by_mask
#endif

alignas(MEM_ALIGN) static const uint16_t MASK_16BIT[] = {
    0xffff, 0x0000, 0xffff, 0x0000, 0xffff, 0x0000, 0xffff, 0x0000,
#if USE_AVX2
    0xffff, 0x0000, 0xffff, 0x0000, 0xffff, 0x0000, 0xffff, 0x0000
#endif
};

#if USE_AVX2
//本来の256bit alignr
#define MM_ABS(x) (((x) < 0) ? -(x) : (x))
#define _mm256_alignr256_epi8(a, b, i) ((i<=16) ? _mm256_alignr_epi8(_mm256_permute2x128_si256(a, b, (0x00<<4) + 0x03), b, i) : _mm256_alignr_epi8(a, _mm256_permute2x128_si256(a, b, (0x00<<4) + 0x03), MM_ABS(i-16)))

//_mm256_srli_si256, _mm256_slli_si256は
//単に128bitシフト×2をするだけの命令である
#define _mm256_bsrli_epi128 _mm256_srli_si256
#define _mm256_bslli_epi128 _mm256_slli_si256
//本当の256bitシフト
#define _mm256_srli256_si256(a, i) ((i<=16) ? _mm256_alignr_epi8(_mm256_permute2x128_si256(a, a, (0x08<<4) + 0x03), a, i) : _mm256_bsrli_epi128(_mm256_permute2x128_si256(a, a, (0x08<<4) + 0x03), MM_ABS(i-16)))
#define _mm256_slli256_si256(a, i) ((i<=16) ? _mm256_alignr_epi8(a, _mm256_permute2x128_si256(a, a, (0x00<<4) + 0x08), MM_ABS(16-i)) : _mm256_bslli_epi128(_mm256_permute2x128_si256(a, a, (0x00<<4) + 0x08), MM_ABS(i-16)))


alignas(MEM_ALIGN) static const unsigned int ARRAY_0x00008000[8] = {
    0x00008000, 0x00008000, 0x00008000, 0x00008000, 0x00008000, 0x00008000, 0x00008000, 0x00008000,
};
static QSV_FORCEINLINE __m256i cvtlo256_epi16_epi32(__m256i y0) {
    __m256i yWordsHi = _mm256_cmpgt_epi16(_mm256_setzero_si256(), y0);
    return _mm256_unpacklo_epi16(y0, yWordsHi);
}

static QSV_FORCEINLINE __m256i cvthi256_epi16_epi32(__m256i y0) {
    __m256i yWordsHi = _mm256_cmpgt_epi16(_mm256_setzero_si256(), y0);
    return _mm256_unpackhi_epi16(y0, yWordsHi);
}

static QSV_FORCEINLINE __m256i _mm256_neg_epi32(__m256i y) {
    return _mm256_sub_epi32(_mm256_setzero_si256(), y);
}
static QSV_FORCEINLINE __m256i _mm256_neg_epi16(__m256i y) {
    return _mm256_sub_epi16(_mm256_setzero_si256(), y);
}
static QSV_FORCEINLINE __m256 _mm256_rcp_ps_hp(__m256 y0) {
    __m256 y1, y2;
    y1 = _mm256_rcp_ps(y0);
    y0 = _mm256_mul_ps(y0, y1);
    y2 = _mm256_add_ps(y1, y1);
#if USE_FMA3
    y2 = _mm256_fnmadd_ps(y0, y1, y2);
#else
    y0 = _mm256_mul_ps(y0, y1);
    y2 = _mm256_sub_ps(y2, y0);
#endif
    return y2;
}

#elif USE_SSE2
alignas(MEM_ALIGN) static const unsigned int ARRAY_0x00008000[4] = {
    0x00008000, 0x00008000, 0x00008000, 0x00008000,
};
static QSV_FORCEINLINE __m128i _mm_neg_epi32(__m128i y) {
    return _mm_sub_epi32(_mm_setzero_si128(), y);
}
static QSV_FORCEINLINE __m128i _mm_neg_epi16(__m128i y) {
    return _mm_sub_epi16(_mm_setzero_si128(), y);
}
static QSV_FORCEINLINE __m128 _mm_rcp_ps_hp(__m128 x0) {
    __m128 x1, x2;
    x1 = _mm_rcp_ps(x0);
    x0 = _mm_mul_ps(x0, x1);
    x2 = _mm_add_ps(x1, x1);
    x0 = _mm_mul_ps(x0, x1);
    x2 = _mm_sub_ps(x2, x0);
    return x2;
}

static QSV_FORCEINLINE __m128i _mm_packus_epi32_simd(__m128i a, __m128i b) {
#if USE_SSE41
    return _mm_packus_epi32(a, b);
#else
    alignas(64) static const DWORD VAL[2][4] = {
        { 0x00008000, 0x00008000, 0x00008000, 0x00008000 },
        { 0x80008000, 0x80008000, 0x80008000, 0x80008000 }
    };
#define LOAD_32BIT_0x8000 _mm_load_si128((__m128i *)VAL[0])
#define LOAD_16BIT_0x8000 _mm_load_si128((__m128i *)VAL[1])
    a = _mm_sub_epi32(a, LOAD_32BIT_0x8000);
    b = _mm_sub_epi32(b, LOAD_32BIT_0x8000);
    a = _mm_packs_epi32(a, b);
    return _mm_add_epi16(a, LOAD_16BIT_0x8000);
#undef LOAD_32BIT_0x8000
#undef LOAD_16BIT_0x8000
#endif
}


static QSV_FORCEINLINE __m128i _mm_mullo_epi32_simd(__m128i x0, __m128i x1) {
#if USE_SSE41
    return _mm_mullo_epi32(x0, x1);
#else
    __m128i x2 = _mm_mul_epu32(x0, x1);
    __m128i x3 = _mm_mul_epu32(_mm_shuffle_epi32(x0, 0xB1), _mm_shuffle_epi32(x1, 0xB1));
    
    x2 = _mm_shuffle_epi32(x2, 0xD8);
    x3 = _mm_shuffle_epi32(x3, 0xD8);
    
    return _mm_unpacklo_epi32(x2, x3);
#endif
}

static QSV_FORCEINLINE __m128i cvtlo_epi16_epi32(__m128i x0) {
#if USE_SSE41
    return _mm_cvtepi16_epi32(x0);
#else
    __m128i xWordsHi = _mm_cmpgt_epi16(_mm_setzero_si128(), x0);
    return _mm_unpacklo_epi16(x0, xWordsHi);
#endif
}

static QSV_FORCEINLINE __m128i cvthi_epi16_epi32(__m128i x0) {
#if USE_SSE41
    return _mm_cvtepi16_epi32(_mm_srli_si128(x0, 8));
#else
    __m128i xWordsHi = _mm_cmpgt_epi16(_mm_setzero_si128(), x0);
    return _mm_unpackhi_epi16(x0, xWordsHi);
#endif
}

static QSV_FORCEINLINE __m128i blendv_epi8_simd(__m128i a, __m128i b, __m128i mask) {
#if USE_SSE41
    return _mm_blendv_epi8(a, b, mask);
#else
    return _mm_or_si128( _mm_andnot_si128(mask,a), _mm_and_si128(b,mask) );
#endif
}
#endif

#pragma warning(push)
#pragma warning(disable: 4100)
#if USE_AVX2
static QSV_FORCEINLINE void blend_block(uint8_t *ptr_dst, const __m256i& yBitmap, const __m256i& ySubColor, const __m256i& yTable0, const __m256i& yTable1) {
    const __m256i yC255b = _mm256_set1_epi8(-1);
    //uint8_t alpha = ((255 - ptr_transparency[0]) * subalpha) >> 9;
    //ptr_dst[0] = (ptr_dst[0] * (127 - alpha) + subcolory * alpha) >> 7;
    __m256i yFrame0, yFrame1;
    yFrame0 = _mm256_load_si256((__m256i *)ptr_dst);
    yFrame1 = _mm256_unpackhi_epi8(yFrame0, ySubColor); //frame[8], subcolor, frame[9], subcolor, ...
    yFrame0 = _mm256_unpacklo_epi8(yFrame0, ySubColor); //frame[0], subcolor, frame[1], subcolor, ...
    const __m256i yC0xfb = _mm256_set1_epi8(0xf);
    const __m256i yC127b = _mm256_set1_epi8(127);
    __m256i yBitmapHi = _mm256_and_si256(_mm256_srli_epi16(yBitmap, 4), yC0xfb);
    __m256i yBitmapLo = _mm256_and_si256(yBitmap, yC0xfb);
    __m256i yAlpha    = _mm256_add_epi8(_mm256_shuffle_epi8(yTable0, yBitmapHi), _mm256_shuffle_epi8(yTable1, yBitmapLo)); //alpha = ((255 - ptr_transparency[0]) * subalpha) >> 9
    __m256i yAlphaInv = _mm256_sub_epi8(yC127b, yAlpha); //127-alpha[0], 127-alpha[1], ...

    __m256i xInvAlphaAlpha0 = _mm256_unpacklo_epi8(yAlphaInv, yAlpha); //127-alpha[0], alpha[0], 127-alpha[1], alpha[1], ...
    __m256i xInvAlphaAlpha1 = _mm256_unpackhi_epi8(yAlphaInv, yAlpha); //127-alpha[8], alpha[8], 127-alpha[9], alpha[9], ...

    const __m256i yC256w = _mm256_set1_epi16(256);
    yFrame0 = _mm256_maddubs_epi16(yFrame0, xInvAlphaAlpha0); //(127-alpha[0])*frame[0] + alpha[0] * subcolor, ...
    yFrame1 = _mm256_maddubs_epi16(yFrame1, xInvAlphaAlpha1); //(127-alpha[8])*frame[8] + alpha[8] * subcolor, ...
    yFrame0 = _mm256_add_epi16(yFrame0, yC256w);
    yFrame1 = _mm256_add_epi16(yFrame1, yC256w);
    yFrame0 = _mm256_srai_epi16(yFrame0, 7);
    yFrame1 = _mm256_srai_epi16(yFrame1, 7);
    yFrame0 = _mm256_packus_epi16(yFrame0, yFrame1);
    _mm256_store_si256((__m256i *)ptr_dst, yFrame0);
}
#else
static QSV_FORCEINLINE void blend_block(uint8_t *ptr_dst, const __m128i& xBitmap, const __m128i& xSubColor, const __m128i& xTable0, const __m128i& xTable1) {
    const __m128i xC255b = _mm_set1_epi8(-1);
    //uint8_t alpha = ((255 - ptr_transparency[0]) * subalpha) >> 9;
    //ptr_dst[0] = (ptr_dst[0] * (127 - alpha) + subcolory * alpha) >> 7;
    __m128i xFrame0, xFrame1;
    xFrame0 = _mm_load_si128((__m128i *)ptr_dst);
    xFrame1 = _mm_unpackhi_epi8(xFrame0, xSubColor); //frame[8], subcolor, frame[9], subcolor, ...
    xFrame0 = _mm_unpacklo_epi8(xFrame0, xSubColor); //frame[0], subcolor, frame[1], subcolor, ...
#if PSHUFB_SLOW
    const __m128i xC127w = _mm_set1_epi16(127);
    __m128i xBitmapLo = _mm_unpacklo_epi8(xBitmap, _mm_setzero_si128());
    __m128i xBitmapHi = _mm_unpackhi_epi8(xBitmap, _mm_setzero_si128());
    __m128i xAlphaLo  = _mm_srli_epi16(_mm_maddubs_epi16(xBitmapLo, xTable0), 8);
    __m128i xAlphaHi  = _mm_srli_epi16(_mm_maddubs_epi16(xBitmapHi, xTable0), 8);
    __m128i xInvAlphaLo = _mm_sub_epi16(xC127w, xAlphaLo);
    __m128i xInvAlphaHi = _mm_sub_epi16(xC127w, xAlphaHi);
    __m128i xInvAlphaAlpha0 = _mm_or_si128(xInvAlphaLo, _mm_slli_epi16(xAlphaLo, 8)); //127-alpha[0], alpha[0], 127-alpha[1], alpha[1], ...
    __m128i xInvAlphaAlpha1 = _mm_or_si128(xInvAlphaHi, _mm_slli_epi16(xAlphaHi, 8)); //127-alpha[8], alpha[8], 127-alpha[9], alpha[9], ...
#else
    const __m128i xC0xfb = _mm_set1_epi8(0xf);
    const __m128i xC127b = _mm_set1_epi8(127);
    __m128i xBitmapHi = _mm_and_si128(_mm_srli_epi16(xBitmap, 4), xC0xfb);
    __m128i xBitmapLo = _mm_and_si128(xBitmap, xC0xfb);
    __m128i xAlpha    = _mm_add_epi8(_mm_shuffle_epi8(xTable0, xBitmapHi), _mm_shuffle_epi8(xTable1, xBitmapLo)); //alpha = ((255 - ptr_transparency[0]) * subalpha) >> 9
    __m128i xAlphaInv = _mm_sub_epi8(xC127b, xAlpha); //127-alpha[0], 127-alpha[1], ...

    __m128i xInvAlphaAlpha0 = _mm_unpacklo_epi8(xAlphaInv, xAlpha); //127-alpha[0], alpha[0], 127-alpha[1], alpha[1], ...
    __m128i xInvAlphaAlpha1 = _mm_unpackhi_epi8(xAlphaInv, xAlpha); //127-alpha[8], alpha[8], 127-alpha[9], alpha[9], ...
#endif
    const __m128i xC256w = _mm_set1_epi16(256);
    xFrame0 = _mm_maddubs_epi16(xFrame0, xInvAlphaAlpha0); //(127-alpha[0])*frame[0] + alpha[0] * subcolor, ...
    xFrame1 = _mm_maddubs_epi16(xFrame1, xInvAlphaAlpha1); //(127-alpha[8])*frame[8] + alpha[8] * subcolor, ...
    xFrame0 = _mm_add_epi16(xFrame0, xC256w);
    xFrame1 = _mm_add_epi16(xFrame1, xC256w);
    xFrame0 = _mm_srai_epi16(xFrame0, 7);
    xFrame1 = _mm_srai_epi16(xFrame1, 7);
    xFrame0 = _mm_packus_epi16(xFrame0, xFrame1);
    _mm_store_si128((__m128i *)ptr_dst, xFrame0);
}
#endif
#pragma warning(pop)

#if USE_AVX2
static QSV_FORCEINLINE __m256i convert_bitmap_for_uv(__m256i yBitmap) {
    __m256i yBitmapDoubleLo = _mm256_unpacklo_epi8(yBitmap, yBitmap);
    __m256i yBitmapDoubleHi = _mm256_unpackhi_epi8(yBitmap, yBitmap);
    yBitmapDoubleLo = _mm256_and_si256(yBitmapDoubleLo, _mm256_set1_epi32(0xff));
    yBitmapDoubleHi = _mm256_and_si256(yBitmapDoubleHi, _mm256_set1_epi32(0xff));
    return _mm256_packus_epi32(yBitmapDoubleLo, yBitmapDoubleHi);
}
#else
static QSV_FORCEINLINE __m128i convert_bitmap_for_uv(__m128i xBitmap) {
    //15, 14, 13, 12, ..., 3, 2, 1, 0
    //  ↓
    //14, 14, 12, 12, ..., 2, 2, 0, 0
    __m128i xBitmapDoubleLo = _mm_unpacklo_epi8(xBitmap, xBitmap);
    __m128i xBitmapDoubleHi = _mm_unpackhi_epi8(xBitmap, xBitmap);
    xBitmapDoubleLo = _mm_and_si128(xBitmapDoubleLo, _mm_set1_epi32(0xff));
    xBitmapDoubleHi = _mm_and_si128(xBitmapDoubleHi, _mm_set1_epi32(0xff));
    return _mm_packus_epi32_simd(xBitmapDoubleLo, xBitmapDoubleHi);
}
#endif

#if USE_AVX2
static QSV_FORCEINLINE __m256i shiftFirstBitmap(const uint8_t *ptr_alpha, const __m256i& yFirstLoadShift0, const __m256i& yFirstLoadShift1) {
    __m256i y0 = _mm256_loadu_si256((__m256i *)ptr_alpha);
    __m256i y1 = _mm256_loadu2_m128i((__m128i *)ptr_alpha, (__m128i *)ptr_alpha);
    y0 = _mm256_shuffle_epi8(y0, yFirstLoadShift0);
    y1 = _mm256_shuffle_epi8(y1, yFirstLoadShift1);
    y0 = _mm256_or_si256(y0, y1);
    return y0;
}
#else
static QSV_FORCEINLINE __m128i shiftFirstBitmap(const uint8_t *ptr_alpha, const __m128i& xFirstLoadShift) {
    __m128i x0 = _mm_loadu_si128((__m128i *)ptr_alpha);
    x0 = _mm_shuffle_epi8(x0, xFirstLoadShift);
    return x0;
}
#endif

template<int bForUV>
static QSV_FORCEINLINE void blend_sub(uint8_t *pFrame, int pitch, const uint8_t *pAlpha, int subX, int subY, int subW, int subStride, int bufH, uint8_t subcolor0, uint8_t subcolor1, uint8_t subTransparency) {
    const int bufX = subX & ~(MEM_ALIGN-1);
    const int bufW = ((subX + subW + (MEM_ALIGN-1)) & ~((MEM_ALIGN-1))) - bufX;
    const int bufXOffset = subX - bufX;
    const int subalpha = 255 - subTransparency;
    /*
    16byte align
    bufX                     16byte alignして処理するサイズ
     | <-------------------------------- bufW --------------------------------> |
     | <------ 16byte ------> |                        |                        |
           |                                                             |
      <--->| <-------------------------  subW -------------------------> |<---->
      ↑ subX                      実際の字幕の横幅                         ↑ 
      ｜                                                               bufYXExtension
     bufXOffset
    */
#if USE_AVX2
    const __m256i ySubColor = _mm256_set1_epi16((subcolor1 << 8) | subcolor0);
    const __m256i yC255b = _mm256_set1_epi8(-1);
#else
    const __m128i xSubColor = _mm_set1_epi16((subcolor1 << 8) | subcolor0);
    const __m128i xC255b = _mm_set1_epi8(-1);
#endif
    alignas(MEM_ALIGN) static const uint8_t iter[] = {
#if USE_AVX2
        240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240,
#endif
        240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240,
          0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,  15,
#if USE_AVX2
        240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240, 240,
          0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,  15,
          0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,  15,
#endif
    };
#if USE_AVX2
    __m256i yTable0 = _mm256_load_si256((__m256i *)(iter + 64));
    __m256i yTable1 = yTable0;
    {
        __m256i y2 = _mm256_unpacklo_epi8(yTable0, _mm256_setzero_si256());
        __m256i y3 = _mm256_unpackhi_epi8(yTable0, _mm256_setzero_si256());
        __m256i y0 = _mm256_mullo_epi16(y2, _mm256_set1_epi16((short)(subalpha+1)));
        __m256i y1 = _mm256_mullo_epi16(y3, _mm256_set1_epi16((short)(subalpha+1)));
        y0 = _mm256_srai_epi16(y0, 5);
        y1 = _mm256_srai_epi16(y1, 5);
        yTable0 = _mm256_packus_epi16(y0, y1);
        y2 = _mm256_mullo_epi16(y2, _mm256_set1_epi16((short)((subalpha+1)>>4)));
        y3 = _mm256_mullo_epi16(y3, _mm256_set1_epi16((short)((subalpha+1)>>4)));
        y2 = _mm256_srai_epi16(y2, 5);
        y3 = _mm256_srai_epi16(y3, 5);
        yTable1 = _mm256_packus_epi16(y2, y3);
    }
    //bufXOffset = 4
    //                 256                                                128                                                 0
    //alpha0            |  ptr_alpha[31] .................. ptr_alpha[16]  | ptr_alpha[15] ..................... ptr_alpha[0] |
    //yFirstLoadShift0  |  11,  10,   9, ...,   1,   0, 240, 240, 240, 240 |  11,  10,   9, ...,   1,   0, 240, 240, 240, 240 |
    //
    //alpha1            |  ptr_alpha[15] ................... ptr_alpha[0]  | ptr_alpha[15] ..................... ptr_alpha[0] |
    //yFirstLoadShift1  | 240, 240, 240, ..., 240, 240,  15,  14,  13,  12 | 240, ....................................... 240 |
    // shifted alpha = _mm256_or_si256( _mm256_shuffle_epi8(alpha0, yFirstLoadShift0),  _mm256_shuffle_epi8(alpha1, yFirstLoadShift1) )

    //
    //bufXOffset = 20
    //                 256                                                128                                                 0
    //alpha0            |  ptr_alpha[31] .................. ptr_alpha[16]  | ptr_alpha[15] ..................... ptr_alpha[0] |
    //yFirstLoadShift0  | 240, ....................................... 240 | 240, ....................................... 240 |
    //
    //alpha1            |  ptr_alpha[15] ................... ptr_alpha[0]  | ptr_alpha[15] ..................... ptr_alpha[0] |
    //yFirstLoadShift1  |  11,  10,   9, ...,   1,   0, 240, 240, 240, 240 | 240, ....................................... 240 |
    // shifted alpha = _mm256_or_si256( _mm256_shuffle_epi8(alpha0, yFirstLoadShift0),  _mm256_shuffle_epi8(alpha1, yFirstLoadShift1) )
    const __m256i yFirstLoadShift0 = _mm256_loadu2_m128i((__m128i *)(iter + 32 - bufXOffset), (__m128i *)(iter + 32 - bufXOffset));
    const __m256i yFirstLoadShift1 = _mm256_loadu2_m128i((__m128i *)(iter + 48 - bufXOffset), (__m128i *)(iter));
#else
#if PSHUFB_SLOW
    __m128i xTable0 = _mm_set1_epi16((short)(subalpha >> 1));
    __m128i xTable1 = xTable0;
#else
    __m128i xTable0 = _mm_load_si128((__m128i *)(iter + 16));
    __m128i xTable1 = _mm_load_si128((__m128i *)(iter + 16));
    {
        __m128i x2 = _mm_unpacklo_epi8(xTable0, _mm_setzero_si128());
        __m128i x3 = _mm_unpackhi_epi8(xTable0, _mm_setzero_si128());
        __m128i x0 = _mm_mullo_epi16(x2, _mm_set1_epi16((short)(subalpha+1)));
        __m128i x1 = _mm_mullo_epi16(x3, _mm_set1_epi16((short)(subalpha+1)));
        x0 = _mm_srai_epi16(x0, 5);
        x1 = _mm_srai_epi16(x1, 5);
        xTable0 = _mm_packus_epi16(x0, x1);
        x2 = _mm_mullo_epi16(x2, _mm_set1_epi16((short)((subalpha+1)>>4)));
        x3 = _mm_mullo_epi16(x3, _mm_set1_epi16((short)((subalpha+1)>>4)));
        x2 = _mm_srai_epi16(x2, 5);
        x3 = _mm_srai_epi16(x3, 5);
        xTable1 = _mm_packus_epi16(x2, x3);
    }
#endif
    const __m128i xFirstLoadShift = _mm_loadu_si128((__m128i *)(iter + 16 - bufXOffset));
    // bufXOffset ... xFirstLoadShift
    //  0 ...  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
    //  1 ... 16,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
    //  2 ... 16, 16,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13,
    // ...
#endif

    alignas(MEM_ALIGN) static const uint8_t mask[] = {
#if USE_AVX2
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
#endif
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
#if USE_AVX2
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
#endif
    };
    const int bufYXExtension = bufX + bufW - (subX + subW);
#if USE_AVX2
    const __m256i yLastLoadMask = _mm256_loadu_si256((__m256i *)(mask + bufYXExtension));
#else
    const __m128i xLastLoadMask = _mm_loadu_si128((__m128i *)(mask + bufYXExtension));
    // bufYXExtension ... xLastLoadMask
    //  0 ... 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    //  1 ... 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00
    //  2 ... 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00
    // ...
#endif

    pFrame += (subY >> bForUV) * pitch + bufX;
    if (bufW <= MEM_ALIGN) {
        for (int y = 0; y < bufH; y += (1 + bForUV), pFrame += pitch, pAlpha += (subStride << bForUV)) {
            uint8_t *ptr_dst = pFrame;
            const uint8_t *ptr_alpha = pAlpha;
#if USE_AVX2
            __m256i yBitmap = shiftFirstBitmap(ptr_alpha, yFirstLoadShift0, yFirstLoadShift1);
            yBitmap = _mm256_and_si256(yBitmap, yLastLoadMask);
            if (bForUV) yBitmap = convert_bitmap_for_uv(yBitmap);
            blend_block(ptr_dst, yBitmap, ySubColor, yTable0, yTable1);
#else
            __m128i xBitmap = shiftFirstBitmap(ptr_alpha, xFirstLoadShift);
            xBitmap = _mm_and_si128(xBitmap, xLastLoadMask);
            if (bForUV) xBitmap = convert_bitmap_for_uv(xBitmap);
            blend_block(ptr_dst, xBitmap, xSubColor, xTable0, xTable1);
#endif
        }
    } else {
        for (int y = 0; y < bufH; y += (1 + bForUV), pFrame += pitch, pAlpha += (subStride << bForUV)) {
            uint8_t *ptr_dst = pFrame;
            uint8_t *ptr_dst_fin = ptr_dst + bufW - MEM_ALIGN;
            const uint8_t *ptr_alpha = pAlpha;
#if USE_AVX2
            __m256i yBitmap = shiftFirstBitmap(ptr_alpha, yFirstLoadShift0, yFirstLoadShift1);
            if (bForUV) yBitmap = convert_bitmap_for_uv(yBitmap);
            blend_block(ptr_dst, yBitmap, ySubColor, yTable0, yTable1);
#else
            __m128i xBitmap = shiftFirstBitmap(ptr_alpha, xFirstLoadShift);
            if (bForUV) xBitmap = convert_bitmap_for_uv(xBitmap);
            blend_block(ptr_dst, xBitmap, xSubColor, xTable0, xTable1);
#endif
            ptr_dst += MEM_ALIGN;
            ptr_alpha += MEM_ALIGN - bufXOffset;
            for (; ptr_dst < ptr_dst_fin; ptr_dst += MEM_ALIGN, ptr_alpha += MEM_ALIGN) {
#if USE_AVX2
                yBitmap = _mm256_loadu_si256((__m256i *)ptr_alpha);
                if (bForUV) yBitmap = convert_bitmap_for_uv(yBitmap);
                blend_block(ptr_dst, yBitmap, ySubColor, yTable0, yTable1);
#else
                xBitmap = _mm_loadu_si128((__m128i *)ptr_alpha);
                if (bForUV) xBitmap = convert_bitmap_for_uv(xBitmap);
                blend_block(ptr_dst, xBitmap, xSubColor, xTable0, xTable1);
#endif
            }
#if USE_AVX2
            yBitmap = _mm256_loadu_si256((__m256i *)ptr_alpha);
            yBitmap = _mm256_and_si256(yBitmap, yLastLoadMask);
            if (bForUV) yBitmap = convert_bitmap_for_uv(yBitmap);
            blend_block(ptr_dst, yBitmap, ySubColor, yTable0, yTable1);
#else
            xBitmap = _mm_loadu_si128((__m128i *)ptr_alpha);
            xBitmap = _mm_and_si128(xBitmap, xLastLoadMask);
            if (bForUV) xBitmap = convert_bitmap_for_uv(xBitmap);
            blend_block(ptr_dst, xBitmap, xSubColor, xTable0, xTable1);
#endif
        }
    }
}
