﻿// -----------------------------------------------------------------------------------------
// RGY by rigaya
// -----------------------------------------------------------------------------------------
//
// The MIT License
//
// Copyright (c) 2014-2016 rigaya
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// ------------------------------------------------------------------------------------------

#include "rgy_filter_libplacebo.h"
#include "rgy_libdovi.h"
#include "rgy_filesystem.h"
#include "rgy_osdep.h"
#include <iostream>
#include <fstream>

tstring RGYFilterParamLibplaceboResample::print() const {
    return resample.print();
}

tstring RGYFilterParamLibplaceboDeband::print() const {
    return deband.print();
}

tstring RGYFilterParamLibplaceboToneMapping::print() const {
    return toneMapping.print();
}

#if ENABLE_LIBPLACEBO

#pragma comment(lib, "libplacebo-349.lib")

static const TCHAR *RGY_LIBPLACEBO_DLL_NAME = _T("libplacebo-349.dll");

class LibplaceboLoader {
private:
    HMODULE m_hModule;

    pl_color_space *m_pl_color_space_bt2020_hlg;
    pl_color_space *m_pl_color_space_bt709;
    pl_color_space *m_pl_color_space_srgb;
    pl_color_space *m_pl_color_space_hdr10;
    pl_hdr_metadata *m_pl_hdr_metadata_empty;
    pl_peak_detect_params *m_pl_peak_detect_default_params;

public:
    LibplaceboLoader();
    ~LibplaceboLoader();

    bool load();
    void close();

    pl_color_space pl_color_space_bt2020_hlg() const { return *m_pl_color_space_bt2020_hlg; }
    pl_color_space pl_color_space_bt709() const { return *m_pl_color_space_bt709; }
    pl_color_space pl_color_space_srgb() const { return *m_pl_color_space_srgb; }
    pl_color_space pl_color_space_hdr10() const { return *m_pl_color_space_hdr10; }
    pl_hdr_metadata pl_hdr_metadata_empty() const { return *m_pl_hdr_metadata_empty; }
    pl_peak_detect_params  pl_peak_detect_default_params() const { return *m_pl_peak_detect_default_params; }
};

LibplaceboLoader::LibplaceboLoader() : m_hModule(nullptr),
m_pl_color_space_bt2020_hlg(nullptr),
m_pl_color_space_bt709(nullptr),
m_pl_color_space_srgb(nullptr),
m_pl_color_space_hdr10(nullptr),
m_pl_hdr_metadata_empty(nullptr),
m_pl_peak_detect_default_params(nullptr) {
}

LibplaceboLoader::~LibplaceboLoader() {
    close();
}

bool LibplaceboLoader::load() {
    if (m_hModule) {
        return true;
    }

    if ((m_hModule = RGY_LOAD_LIBRARY(RGY_LIBPLACEBO_DLL_NAME)) == nullptr) {
        return false;
    }

    auto loadFunc = [this](const char *funcName, void **func) {
        if ((*func = RGY_GET_PROC_ADDRESS(m_hModule, funcName)) == nullptr) {
            return false;
        }
        return true;
    };

    if (!loadFunc("pl_color_space_bt2020_hlg", (void**)&m_pl_color_space_bt2020_hlg)) return false;
    if (!loadFunc("pl_color_space_bt709", (void**)&m_pl_color_space_bt709)) return false;
    if (!loadFunc("pl_color_space_srgb", (void**)&m_pl_color_space_srgb)) return false;
    if (!loadFunc("pl_color_space_hdr10", (void**)&m_pl_color_space_hdr10)) return false;
    if (!loadFunc("pl_hdr_metadata_empty", (void**)&m_pl_hdr_metadata_empty)) return false;
    if (!loadFunc("pl_peak_detect_default_params", (void**)&m_pl_peak_detect_default_params)) return false;

    return true;
}

void LibplaceboLoader::close() {
    if (m_hModule) {
        RGY_FREE_LIBRARY(m_hModule);
        m_hModule = nullptr;
    }

    m_pl_color_space_bt2020_hlg = nullptr;
    m_pl_color_space_bt709 = nullptr;
    m_pl_color_space_srgb = nullptr;
    m_pl_color_space_hdr10 = nullptr;
}

static const RGYLogType RGY_LOGT_LIBPLACEBO = RGY_LOGT_VPP;

static const auto RGY_LOG_LEVEL_TO_LIBPLACEBO = make_array<std::pair<RGYLogLevel, pl_log_level>>(
    std::make_pair(RGYLogLevel::RGY_LOG_QUIET, PL_LOG_NONE),
    std::make_pair(RGYLogLevel::RGY_LOG_ERROR, PL_LOG_ERR),
    std::make_pair(RGYLogLevel::RGY_LOG_WARN,  PL_LOG_WARN),
    std::make_pair(RGYLogLevel::RGY_LOG_INFO,  PL_LOG_INFO),
    std::make_pair(RGYLogLevel::RGY_LOG_DEBUG, PL_LOG_DEBUG),
    std::make_pair(RGYLogLevel::RGY_LOG_TRACE, PL_LOG_TRACE)
);

MAP_PAIR_0_1(loglevel, rgy, RGYLogLevel, libplacebo, pl_log_level, RGY_LOG_LEVEL_TO_LIBPLACEBO, RGYLogLevel::RGY_LOG_INFO, PL_LOG_INFO);

static const auto RGY_RESIZE_ALGO_TO_LIBPLACEBO = make_array<std::pair<RGY_VPP_RESIZE_ALGO, const char*>>(
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_SPLINE16, "spline16"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_SPLINE36, "spline36"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_SPLINE64, "spline64"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_NEAREST, "nearest"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_BILINEAR, "bilinear"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_GAUSSIAN, "gaussian"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_SINC, "sinc"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_LANCZOS, "lanczos"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_GINSENG, "ginseng"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_JINC, "ewa_jinc"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_LANCZOS, "ewa_lanczos"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_LANCZOSSHARP, "ewa_lanczossharp"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_LANCZOS4SHARPEST, "ewa_lanczos4sharpest"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_GINSENG, "ewa_ginseng"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_HANN, "ewa_hann"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_HANNING, "ewa_hanning"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_BICUBIC, "bicubic"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_TRIANGLE, "triangle"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_HERMITE, "hermite"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_CATMULL_ROM, "catmull_rom"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_MITCHELL, "mitchell"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_MITCHELL_CLAMP, "mitchell_clamp"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_ROBIDOUX, "robidoux"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_ROBIDOUXSHARP, "robidouxsharp"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_ROBIDOUX, "ewa_robidoux"),
    std::make_pair(RGY_VPP_RESIZE_LIBPLACEBO_EWA_ROBIDOUXSHARP, "ewa_robidouxsharp")
);

MAP_PAIR_0_1(resize_algo, rgy, RGY_VPP_RESIZE_ALGO, libplacebo, const char*, RGY_RESIZE_ALGO_TO_LIBPLACEBO, RGY_VPP_RESIZE_UNKNOWN, nullptr);

 static const auto RGY_TONEMAP_METADATA_TO_LIBPLACEBO = make_array<std::pair<VppLibplaceboToneMappingMetadata, pl_hdr_metadata_type>>(
    std::make_pair(VppLibplaceboToneMappingMetadata::ANY, PL_HDR_METADATA_ANY),
    std::make_pair(VppLibplaceboToneMappingMetadata::NONE, PL_HDR_METADATA_NONE),
    std::make_pair(VppLibplaceboToneMappingMetadata::HDR10, PL_HDR_METADATA_HDR10),
    std::make_pair(VppLibplaceboToneMappingMetadata::HDR10PLUS, PL_HDR_METADATA_HDR10PLUS),
    std::make_pair(VppLibplaceboToneMappingMetadata::CIE_Y, PL_HDR_METADATA_CIE_Y)
);

MAP_PAIR_0_1(tone_map_metadata, rgy, VppLibplaceboToneMappingMetadata, libplacebo, pl_hdr_metadata_type, RGY_TONEMAP_METADATA_TO_LIBPLACEBO, VppLibplaceboToneMappingMetadata::ANY, PL_HDR_METADATA_ANY);

static const auto RGY_TRANSFER_TO_LIBPLACEBO = make_array<std::pair<CspTransfer, pl_color_transfer>>(
    std::make_pair(RGY_TRANSFER_UNKNOWN,      PL_COLOR_TRC_UNKNOWN),
    std::make_pair(RGY_TRANSFER_BT709,        PL_COLOR_TRC_BT_1886),
    std::make_pair(RGY_TRANSFER_BT601,        PL_COLOR_TRC_BT_1886),
    std::make_pair(RGY_TRANSFER_BT2020_10,    PL_COLOR_TRC_BT_1886),
    std::make_pair(RGY_TRANSFER_BT2020_12,    PL_COLOR_TRC_BT_1886),
    std::make_pair(RGY_TRANSFER_IEC61966_2_1, PL_COLOR_TRC_SRGB),
    std::make_pair(RGY_TRANSFER_LINEAR,       PL_COLOR_TRC_LINEAR),
    std::make_pair(RGY_TRANSFER_ST2084,       PL_COLOR_TRC_PQ),
    std::make_pair(RGY_TRANSFER_ARIB_B67,     PL_COLOR_TRC_HLG)
);

MAP_PAIR_0_1(transfer, rgy, CspTransfer, libplacebo, pl_color_transfer, RGY_TRANSFER_TO_LIBPLACEBO, RGY_TRANSFER_UNKNOWN, PL_COLOR_TRC_UNKNOWN);

static const auto RGY_COLORPRIM_TO_LIBPLACEBO = make_array<std::pair<CspColorprim, pl_color_primaries>>(
    std::make_pair(RGY_PRIM_UNKNOWN,     PL_COLOR_PRIM_UNKNOWN),
    std::make_pair(RGY_PRIM_BT709,       PL_COLOR_PRIM_BT_709),
    std::make_pair(RGY_PRIM_UNSPECIFIED, PL_COLOR_PRIM_UNKNOWN),
    std::make_pair(RGY_PRIM_BT470_M,     PL_COLOR_PRIM_BT_470M),
    std::make_pair(RGY_PRIM_BT470_BG,    PL_COLOR_PRIM_BT_601_625),
    std::make_pair(RGY_PRIM_ST170_M,     PL_COLOR_PRIM_BT_601_525),
    std::make_pair(RGY_PRIM_ST240_M,     PL_COLOR_PRIM_BT_601_525), // 近似値
    std::make_pair(RGY_PRIM_FILM,        PL_COLOR_PRIM_FILM_C),
    std::make_pair(RGY_PRIM_BT2020,      PL_COLOR_PRIM_BT_2020),
    std::make_pair(RGY_PRIM_ST428,       PL_COLOR_PRIM_CIE_1931),
    std::make_pair(RGY_PRIM_ST431_2,     PL_COLOR_PRIM_DCI_P3),
    std::make_pair(RGY_PRIM_ST432_1,     PL_COLOR_PRIM_DISPLAY_P3),
    std::make_pair(RGY_PRIM_EBU3213_E,   PL_COLOR_PRIM_EBU_3213)
);

MAP_PAIR_0_1(colorprim, rgy, CspColorprim, libplacebo, pl_color_primaries, RGY_COLORPRIM_TO_LIBPLACEBO, RGY_PRIM_UNKNOWN, PL_COLOR_PRIM_UNKNOWN);

std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter> rgy_pl_tex_recreate(pl_gpu gpu, const pl_tex_params& tex_params) {
    pl_tex tex_tmp = { 0 };
    if (!pl_tex_recreate(gpu, &tex_tmp, &tex_params)) {
        return std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter>();
    }
    return std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter>(
        tex_tmp, RGYLibplaceboTexDeleter(gpu));
}

static void libplacebo_log_func(void *private_data, pl_log_level level, const char* msg) {
    auto log = static_cast<RGYLog*>(private_data);
    auto log_level = loglevel_libplacebo_to_rgy(level);
    if (log == nullptr || log_level < log->getLogLevel(RGY_LOGT_LIBPLACEBO)) {
        return;
    }
    log->write_log(log_level, RGY_LOGT_LIBPLACEBO, (tstring(_T("libplacebo: ")) + char_to_tstring(msg) + _T("\n")).c_str());
}

RGYFrameD3D11::RGYFrameD3D11() : frame(), clframe() {}

RGYFrameD3D11::~RGYFrameD3D11() { deallocate(); };

RGY_ERR RGYFrameD3D11::allocate(ID3D11Device *device, const int width, const int height, const RGY_CSP csp, const int bitdepth) {
    if (!device) {
        return RGY_ERR_NULL_PTR;
    }
    if (frame.ptr[0]) {
        deallocate();
    }
    const auto dxgi_format = (RGY_CSP_DATA_TYPE[csp] != RGY_DATA_TYPE_U8) ? DXGI_FORMAT_R16_UNORM : DXGI_FORMAT_R8_UNORM;
    frame = RGYFrameInfo(width, height, csp, bitdepth);
    for (int iplane = 0; iplane < RGY_CSP_PLANES[csp]; iplane++) {
        auto plane = getPlane(&frame, (RGY_PLANE)iplane);
        D3D11_TEXTURE2D_DESC desc = {};
        desc.Width = plane.width;
        desc.Height = plane.height;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = dxgi_format;
        desc.SampleDesc.Count = 1;
        desc.SampleDesc.Quality = 0;
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS | D3D11_BIND_RENDER_TARGET;
        desc.CPUAccessFlags = 0;
        desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

        ID3D11Texture2D *pTexture = nullptr;
        HRESULT hr = device->CreateTexture2D(&desc, nullptr, &pTexture);
        if (FAILED(hr)) {
            return RGY_ERR_MEMORY_ALLOC;
        }
        frame.ptr[iplane] = (uint8_t*)pTexture;
    }
    return RGY_ERR_NONE;
}

void RGYFrameD3D11::deallocate() {
    if (clframe) {
        clframe.reset();
    }
    for (int iplane = 0; iplane < RGY_CSP_PLANES[frame.csp]; iplane++) {
        if (frame.ptr[iplane]) {
            auto pTexture = (ID3D11Texture2D*)frame.ptr[iplane];
            pTexture->Release();
            frame.ptr[iplane] = nullptr;
        }
    }
}

RGYCLFrameInterop *RGYFrameD3D11::getCLFrame(RGYOpenCLContext *clctx, RGYOpenCLQueue& queue) {
    if (!clframe) {
        clframe = clctx->createFrameFromD3D11SurfacePlanar(frame, queue, CL_MEM_READ_WRITE);
    }
    return clframe.get();
}

RGYFilterLibplacebo::RGYFilterLibplacebo(shared_ptr<RGYOpenCLContext> context) :
    RGYFilter(context),
    m_procByFrame(false),
    m_textCspIn(RGY_CSP_NA),
    m_textCspOut(RGY_CSP_NA),
    m_dxgiformatIn(DXGI_FORMAT_UNKNOWN),
    m_dxgiformatOut(DXGI_FORMAT_UNKNOWN),
    m_log(),
    m_d3d11(),
    m_dispatch(),
    m_renderer(),
    m_dither_state(std::unique_ptr<pl_shader_obj, decltype(&pl_shader_obj_destroy)>(nullptr, pl_shader_obj_destroy)),
    m_textIn(),
    m_textOut() {
    m_name = _T("libplacebo");
}
RGYFilterLibplacebo::~RGYFilterLibplacebo() {
    close();
}

RGY_ERR RGYFilterLibplacebo::initLibplacebo(const RGYFilterParam *param) {
    auto prm = dynamic_cast<const RGYFilterParamLibplacebo*>(param);
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }

    if (!m_cl->platform()->d3d11dev()) {
        AddMessage(RGY_LOG_ERROR, _T("DX11 device not set\n"));
        return RGY_ERR_NULL_PTR;
    }
    m_libplaceboLoader = std::make_unique<LibplaceboLoader>();
    if (!m_libplaceboLoader->load()) {
        AddMessage(RGY_LOG_ERROR, _T("%s is required but not found.\n"), RGY_LIBPLACEBO_DLL_NAME);
        return RGY_ERR_UNKNOWN;
    }
    const pl_log_params log_params = {libplacebo_log_func, m_pLog.get(), loglevel_rgy_to_libplacebo(m_pLog->getLogLevel(RGY_LOGT_LIBPLACEBO))};
    m_log = std::unique_ptr<std::remove_pointer<pl_log>::type, RGYLibplaceboDeleter<pl_log>>(pl_log_create(0, &log_params), RGYLibplaceboDeleter<pl_log>(pl_log_destroy));
    if (!m_log) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to create libplacebo log.\n"));
        return RGY_ERR_UNKNOWN;
    }
    AddMessage(RGY_LOG_DEBUG, _T("Created libplacebo log.\n"));

    pl_d3d11_params gpu_params = { 0 };
    gpu_params.device = (ID3D11Device*)m_cl->platform()->d3d11dev();

    m_d3d11 = std::unique_ptr<std::remove_pointer<pl_d3d11>::type, RGYLibplaceboDeleter<pl_d3d11>>(
        pl_d3d11_create(m_log.get(), &gpu_params), RGYLibplaceboDeleter<pl_d3d11>(pl_d3d11_destroy));
    if (!m_d3d11) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to create libplacebo D3D11 device.\n"));
        return RGY_ERR_UNKNOWN;
    }
    AddMessage(RGY_LOG_DEBUG, _T("Created libplacebo D3D11 device.\n"));

    m_dispatch = std::unique_ptr<std::remove_pointer<pl_dispatch>::type, RGYLibplaceboDeleter<pl_dispatch>>(
        pl_dispatch_create(m_log.get(), m_d3d11->gpu), RGYLibplaceboDeleter<pl_dispatch>(pl_dispatch_destroy));
    if (!m_dispatch) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to create libplacebo dispatch.\n"));
        return RGY_ERR_UNKNOWN;
    }
    AddMessage(RGY_LOG_DEBUG, _T("Created libplacebo dispatch.\n"));

    m_renderer = std::unique_ptr<std::remove_pointer<pl_renderer>::type, RGYLibplaceboDeleter<pl_renderer>>(
        pl_renderer_create(m_log.get(), m_d3d11->gpu), RGYLibplaceboDeleter<pl_renderer>(pl_renderer_destroy));
    if (!m_renderer) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to create libplacebo renderer.\n"));
        return RGY_ERR_UNKNOWN;
    }
    AddMessage(RGY_LOG_DEBUG, _T("Created libplacebo renderer.\n"));
    return RGY_ERR_NONE;
}

RGY_CSP RGYFilterLibplacebo::getTextureCsp(const RGY_CSP csp) {
    const auto inChromaFmt = RGY_CSP_CHROMA_FORMAT[csp];
    if (inChromaFmt == RGY_CHROMAFMT_RGB) {
        return (RGY_CSP_DATA_TYPE[csp] != RGY_DATA_TYPE_U8) ? RGY_CSP_RGB_16 : RGY_CSP_RGB;
    } else if (inChromaFmt == RGY_CHROMAFMT_YUV420) {
        return (RGY_CSP_DATA_TYPE[csp] != RGY_DATA_TYPE_U8) ? RGY_CSP_YV12_16 : RGY_CSP_YV12;
    } else if (inChromaFmt == RGY_CHROMAFMT_YUV444) {
        return (RGY_CSP_DATA_TYPE[csp] != RGY_DATA_TYPE_U8) ? RGY_CSP_YUV444_16 : RGY_CSP_YUV444;
    }
    return RGY_CSP_NA;
}

DXGI_FORMAT RGYFilterLibplacebo::getTextureDXGIFormat(const RGY_CSP csp) {
    return (RGY_CSP_DATA_TYPE[csp] != RGY_DATA_TYPE_U8) ? DXGI_FORMAT_R16_UNORM : DXGI_FORMAT_R8_UNORM;
}

RGY_ERR RGYFilterLibplacebo::init(shared_ptr<RGYFilterParam> pParam, shared_ptr<RGYLog> pPrintMes) {
    m_pLog = pPrintMes;

    RGY_ERR sts = RGY_ERR_NONE;
    sts = checkParam(pParam.get());
    if (sts != RGY_ERR_NONE) {
        return sts;
    }

    if (rgy_csp_has_alpha(pParam->frameIn.csp)) {
        AddMessage(RGY_LOG_ERROR, _T("nfx filters does not support alpha channel.\n"));
        return RGY_ERR_UNSUPPORTED;
    }

    sts = initLibplacebo(pParam.get());
    if (sts != RGY_ERR_NONE) {
        return sts;
    }

    sts = setLibplaceboParam(pParam.get());
    if (sts != RGY_ERR_NONE) {
        return sts;
    }

    m_textCspIn = getTextureCsp(pParam->frameIn.csp);
    m_textCspOut = getTextureCsp(pParam->frameOut.csp);
    m_dxgiformatIn = getTextureDXGIFormat(pParam->frameIn.csp);
    m_dxgiformatOut = getTextureDXGIFormat(pParam->frameOut.csp);

    sts = initCommon(pParam);
    if (sts != RGY_ERR_NONE) {
        return sts;
    }
    return sts;
}

tstring RGYFilterLibplacebo::printParams(const RGYFilterParamLibplacebo *prm) const {
    return prm->print();
}

RGY_ERR RGYFilterLibplacebo::initCommon(shared_ptr<RGYFilterParam> pParam) {
    RGY_ERR sts = RGY_ERR_NONE;
    auto prm = dynamic_cast<RGYFilterParamLibplacebo*>(pParam.get());
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }

    const auto inChromaFmt = RGY_CSP_CHROMA_FORMAT[pParam->frameIn.csp];
    VideoVUIInfo vui = prm->vui;
    if (inChromaFmt == RGY_CHROMAFMT_RGB || inChromaFmt == RGY_CHROMAFMT_RGB_PACKED) {
        vui.setIfUnset(VideoVUIInfo().to(RGY_MATRIX_RGB).to(RGY_PRIM_BT709).to(RGY_TRANSFER_IEC61966_2_1));
    } else {
        vui.setIfUnset(VideoVUIInfo().to((CspMatrix)COLOR_VALUE_AUTO_RESOLUTION).to((CspColorprim)COLOR_VALUE_AUTO_RESOLUTION).to((CspTransfer)COLOR_VALUE_AUTO_RESOLUTION));
    }
    vui.apply_auto(VideoVUIInfo(), pParam->frameIn.height);

    auto textInFrameInfo = pParam->frameIn;
    if (!m_srcCrop
        || m_srcCrop->GetFilterParam()->frameIn.width != pParam->frameIn.width
        || m_srcCrop->GetFilterParam()->frameIn.height != pParam->frameIn.height) {
        AddMessage(RGY_LOG_DEBUG, _T("Create input csp conversion filter.\n"));
        unique_ptr<RGYFilterCspCrop> filter(new RGYFilterCspCrop(m_cl));
        shared_ptr<RGYFilterParamCrop> paramCrop(new RGYFilterParamCrop());
        paramCrop->frameIn = pParam->frameIn;
        paramCrop->frameOut = paramCrop->frameIn;
        paramCrop->frameOut.csp = m_textCspIn;
        paramCrop->baseFps = pParam->baseFps;
        paramCrop->frameIn.mem_type = RGY_MEM_TYPE_GPU;
        paramCrop->frameOut.mem_type = RGY_MEM_TYPE_GPU;
        paramCrop->bOutOverwrite = false;
        sts = filter->init(paramCrop, m_pLog);
        if (sts != RGY_ERR_NONE) {
            return sts;
        }
        m_srcCrop = std::move(filter);
        AddMessage(RGY_LOG_DEBUG, _T("created %s.\n"), m_srcCrop->GetInputMessage().c_str());
        textInFrameInfo = m_srcCrop->GetFilterParam()->frameOut;
    }
    const int numPlanes = RGY_CSP_PLANES[textInFrameInfo.csp];
    pParam->frameOut.csp = m_textCspOut;
    if (numPlanes != RGY_CSP_PLANES[pParam->frameOut.csp]) {
        AddMessage(RGY_LOG_ERROR, _T("unsupported csp, int out plane count does not match.\n"));
        return RGY_ERR_UNSUPPORTED;
    }
    if (!m_textIn
    || m_textIn->width() != pParam->frameIn.width
    || m_textIn->height() != pParam->frameIn.height
    || m_textIn->csp() != pParam->frameIn.csp) {
        m_textIn = std::make_unique<RGYFrameD3D11>();
        sts = m_textIn->allocate((ID3D11Device*)m_cl->platform()->d3d11dev(), pParam->frameIn.width, pParam->frameIn.height, m_textCspIn, RGY_CSP_BIT_DEPTH[m_textCspIn]);
        if (sts != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_DEBUG, _T("failed to create input texture: %s.\n"), get_err_mes(sts));
            return sts;
        }
    }
    if (!m_textOut
    || m_textOut->width() != pParam->frameIn.width
    || m_textOut->height() != pParam->frameIn.height
    || m_textOut->csp() != pParam->frameIn.csp) {
        m_textOut = std::make_unique<RGYFrameD3D11>();
        sts = m_textOut->allocate((ID3D11Device*)m_cl->platform()->d3d11dev(), pParam->frameOut.width, pParam->frameOut.height, m_textCspOut, RGY_CSP_BIT_DEPTH[m_textCspOut]);
        if (sts != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_DEBUG, _T("failed to create output texture: %s.\n"), get_err_mes(sts));
            return sts;
        }
    }

    if (!m_dstCrop
        || m_dstCrop->GetFilterParam()->frameOut.width != pParam->frameOut.width
        || m_dstCrop->GetFilterParam()->frameOut.height != pParam->frameOut.height) {
        AddMessage(RGY_LOG_DEBUG, _T("Create output csp conversion filter.\n"));
        unique_ptr<RGYFilterCspCrop> filter(new RGYFilterCspCrop(m_cl));
        shared_ptr<RGYFilterParamCrop> paramCrop(new RGYFilterParamCrop());
        paramCrop->frameIn = pParam->frameOut;
        paramCrop->frameIn.csp = m_textCspOut;
        paramCrop->frameOut = pParam->frameOut;
        paramCrop->baseFps = pParam->baseFps;
        paramCrop->frameIn.mem_type = RGY_MEM_TYPE_GPU;
        paramCrop->frameOut.mem_type = RGY_MEM_TYPE_GPU;
        paramCrop->bOutOverwrite = false;
        sts = filter->init(paramCrop, m_pLog);
        if (sts != RGY_ERR_NONE) {
            return sts;
        }
        m_dstCrop = std::move(filter);
        AddMessage(RGY_LOG_DEBUG, _T("created %s.\n"), m_dstCrop->GetInputMessage().c_str());

        m_textFrameBufOut = m_cl->createFrameBuffer(m_dstCrop->GetFilterParam()->frameIn.width, m_dstCrop->GetFilterParam()->frameIn.height, m_textCspOut, RGY_CSP_BIT_DEPTH[m_textCspOut]);
        if (sts != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_DEBUG, _T("failed to allocate memory for libplacebo output: %s.\n"), get_err_mes(sts));
            return sts;
        }
    }

    if (m_frameBuf.size() == 0
        || !cmpFrameInfoCspResolution(&m_frameBuf[0]->frame, &pParam->frameOut)) {
        sts = AllocFrameBuf(pParam->frameOut, 2);
        if (sts != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_ERROR, _T("failed to allocate memory: %s.\n"), get_err_mes(sts));
            return RGY_ERR_MEMORY_ALLOC;
        }
    }
    for (int i = 0; i < RGY_CSP_PLANES[pParam->frameOut.csp]; i++) {
        pParam->frameOut.pitch[i] = m_frameBuf[0]->frame.pitch[i];
    }
    const tstring nameBlank(m_name.length() + _tcslen(_T(": ")), _T(' '));
    tstring info = m_name + _T(": ");
    tstring INFO_INDENT = _T("    ");
    tstring indent = tstring(INFO_INDENT) + nameBlank;
    if (m_srcCrop) {
        info += indent + m_srcCrop->GetInputMessage() + _T("\n");
    }
    auto prm_print = printParams(prm);
    const size_t MAX_LINE_LENGTH = 90;
    std::vector<tstring> prm_print_lines;
    tstring current_line = indent;
    for (const auto& token : split(prm_print, _T(","))) {
        current_line += trim(token) + _T(", ");
        if (current_line.length() > MAX_LINE_LENGTH) {
            info += current_line + _T("\n");
            current_line = indent;
            indent = tstring(INFO_INDENT) + nameBlank;
        }
    }
    current_line = lstrip(current_line, _T(", "));
    if (current_line.size() > 0) {
        info += current_line + _T("\n");
    }
    if (m_dstCrop) {
        info += indent + m_dstCrop->GetInputMessage() + _T("\n");
    }
    setFilterInfo(info);
    m_param = pParam;
    return sts;
}

RGY_ERR RGYFilterLibplacebo::run_filter(const RGYFrameInfo *pInputFrame, RGYFrameInfo **ppOutputFrames, int *pOutputFrameNum, RGYOpenCLQueue &queue, const std::vector<RGYOpenCLEvent> &wait_events, RGYOpenCLEvent *event) {
    RGY_ERR sts = RGY_ERR_NONE;
    if (pInputFrame->ptr[0] == nullptr) {
        return sts;
    }
    auto prm = dynamic_cast<RGYFilterParamLibplacebo*>(m_param.get());
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }

    sts = setFrameParam(pInputFrame);
    if (sts != RGY_ERR_NONE) {
        return sts;
    }

    //const auto memcpyKind = getCudaMemcpyKind(pInputFrame->mem_type, ppOutputFrames[0]->mem_type);
    //if (memcpyKind != cudaMemcpyDeviceToDevice) {
    //    AddMessage(RGY_LOG_ERROR, _T("only supported on device memory.\n"));
    //    return RGY_ERR_INVALID_PARAM;
    //}
    // pInputFrame -> txtFrameBufIn
    const RGYFrameInfo *txtFrameBufIn = nullptr;
    if (!m_srcCrop) {
        AddMessage(RGY_LOG_ERROR, _T("srcCrop is not set.\n"));
        return RGY_ERR_NULL_PTR;
    }
#define COPY_DEBUG 0
    {
        auto textInCL = m_textIn->getCLFrame(m_cl.get(), queue);
        auto err = textInCL->acquire(queue);
        if (err != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to acquire CL frame: %s.\n"), get_err_mes(err));
            return err;
        }
        auto textInCLInfo = textInCL->frameInfo();
        int filterOutputNum = 0;
        RGYFrameInfo *outInfo[1] = { &textInCLInfo };
        RGYFrameInfo cropInput = *pInputFrame;
        auto sts_filter = m_srcCrop->filter(&cropInput, (RGYFrameInfo **)&outInfo, &filterOutputNum, queue, wait_events, event);
        txtFrameBufIn = outInfo[0];
        if (txtFrameBufIn == nullptr || filterOutputNum != 1) {
            AddMessage(RGY_LOG_ERROR, _T("Unknown behavior \"%s\".\n"), m_srcCrop->name().c_str());
            return sts_filter;
        }
        if (sts_filter != RGY_ERR_NONE || filterOutputNum != 1) {
            AddMessage(RGY_LOG_ERROR, _T("Error while running filter \"%s\".\n"), m_srcCrop->name().c_str());
            return sts_filter;
        }
        copyFramePropWithoutRes(outInfo[0], pInputFrame);
#if COPY_DEBUG
        auto textOutCL = m_textOut->getCLFrame(m_cl.get(), queue);
        err = textOutCL->acquire(queue);
        if (err != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to acquire CL frame: %s.\n"), get_err_mes(err));
            return err;
        }
        auto textOutCLInfo = textOutCL->frameInfo();
        for (int iplane = 0; iplane < RGY_CSP_PLANES[m_textIn->csp()]; iplane++) {
            auto planeIn = getPlane(&textInCLInfo, (RGY_PLANE)iplane);
            auto planeOut = getPlane(&textOutCLInfo, (RGY_PLANE)iplane);
            size_t origin[3] = { 0, 0, 0 };
            size_t region[3] = { std::min<size_t>(planeIn.width, planeOut.width), std::min<size_t>(planeIn.height, planeOut.height), 1};
            err = err_cl_to_rgy(clEnqueueCopyImage(queue.get(), (cl_mem)planeIn.ptr[0], (cl_mem)planeOut.ptr[0],
                origin, origin, region, 0, nullptr, nullptr));
            if (err != RGY_ERR_NONE) {
                AddMessage(RGY_LOG_ERROR, _T("Failed to copy CL iamge: %s.\n"), get_err_mes(err));
                return err;
            }
        }
        textInCL->release();
    }
#else
        textInCL->release();
        queue.finish();
    }

    // フィルタを適用
    std::vector<std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter>> pl_tex_planes_in, pl_tex_planes_out;
    for (int iplane = 0; iplane < RGY_CSP_PLANES[m_textIn->csp()]; iplane++) {
        auto textInFrameInfo = m_textIn->frameInfo();
        auto planeIn = getPlane(&textInFrameInfo, (RGY_PLANE)iplane);
        pl_d3d11_wrap_params d3d11_wrap_in = { 0 };
        d3d11_wrap_in.tex = (ID3D11Texture2D*)planeIn.ptr[0];
        d3d11_wrap_in.array_slice = 0;
        d3d11_wrap_in.fmt = m_dxgiformatIn;
        d3d11_wrap_in.w = planeIn.width;
        d3d11_wrap_in.h = planeIn.height;
        auto pl_tex_in = std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter>(
            pl_d3d11_wrap(m_d3d11->gpu, &d3d11_wrap_in), RGYLibplaceboTexDeleter(m_d3d11->gpu));
        if (!pl_tex_in) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to wrap input d3d11 plane(%d) to pl_tex.\n"), iplane);
            return RGY_ERR_NULL_PTR;
        }

        auto textOutFrameInfo = m_textOut->frameInfo();
        auto planeOut = getPlane(&textOutFrameInfo, (RGY_PLANE)iplane);
        pl_d3d11_wrap_params d3d11_wrap_out = { 0 };
        d3d11_wrap_out.tex = (ID3D11Texture2D*)planeOut.ptr[0];
        d3d11_wrap_out.array_slice = 0;
        d3d11_wrap_out.fmt = m_dxgiformatOut;
        d3d11_wrap_out.w = planeOut.width;
        d3d11_wrap_out.h = planeOut.height;
        auto pl_tex_out = std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter>(
            pl_d3d11_wrap(m_d3d11->gpu, &d3d11_wrap_out), RGYLibplaceboTexDeleter(m_d3d11->gpu));
        if (!pl_tex_out) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to wrap output d3d11 plane(%d) to pl_tex.\n"), iplane);
            return RGY_ERR_NULL_PTR;
        }
        
        if (m_procByFrame) {
            pl_tex_planes_in.push_back(std::move(pl_tex_in));
            pl_tex_planes_out.push_back(std::move(pl_tex_out));
        } else {
            sts = procPlane(pl_tex_out.get(), &planeOut, pl_tex_in.get(), &planeIn, (RGY_PLANE)iplane);
            if (sts != RGY_ERR_NONE) {
                AddMessage(RGY_LOG_ERROR, _T("Failed to process plane(%d): %s.\n"), iplane, get_err_mes(sts));
                return sts;
            }
        }
    }

    if (m_procByFrame) {
        pl_tex texOut[RGY_MAX_PLANES], texIn[RGY_MAX_PLANES];
        for (int iplane = 0; iplane < RGY_CSP_PLANES[m_textIn->csp()]; iplane++) {
            texOut[iplane] = pl_tex_planes_out[iplane].get();
            texIn[iplane] = pl_tex_planes_in[iplane].get();
        }
        sts = procFrame(texOut, ppOutputFrames[0], texIn, txtFrameBufIn);
         if (sts != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to process frame.\n"));
             return sts;
         }
         pl_tex_planes_in.clear();
         pl_tex_planes_out.clear();
    }
    // CL_CONTEXT_INTEROP_USER_SYNC=trueの場合、ここでlibplaceboの処理の終了を待つ必要がある
    pl_gpu_finish(m_d3d11->gpu);
#endif
    if (!ppOutputFrames[0]) {
        ppOutputFrames[0] = &m_frameBuf[0]->frame;
        *pOutputFrameNum = 1;
    }
    // m_ngxFrameBufOut -> ppOutputFrames
    auto textOutCL = m_textOut->getCLFrame(m_cl.get(), queue);
#if !COPY_DEBUG
    auto err = textOutCL->acquire(queue);
    if (err != RGY_ERR_NONE) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to acquire CL frame: %s.\n"), get_err_mes(err));
        return err;
    }
#endif
    auto textOutCLInfo = textOutCL->frameInfo();
    if (m_dstCrop) {
        auto sts_filter = m_dstCrop->filter(&textOutCLInfo, ppOutputFrames, pOutputFrameNum, queue);
        if (ppOutputFrames[0] == nullptr || *pOutputFrameNum != 1) {
            AddMessage(RGY_LOG_ERROR, _T("Unknown behavior \"%s\".\n"), m_dstCrop->name().c_str());
            return sts_filter;
        }
        if (sts_filter != RGY_ERR_NONE || *pOutputFrameNum != 1) {
            AddMessage(RGY_LOG_ERROR, _T("Error while running filter \"%s\".\n"), m_dstCrop->name().c_str());
            return sts_filter;
        }
        textOutCL->release();
    }
    setFrameProp(ppOutputFrames[0], pInputFrame);
    return RGY_ERR_NONE;
}

int RGYFilterLibplacebo::getTextureBytePerPix(const DXGI_FORMAT format) const {
    switch (format) {
    case DXGI_FORMAT_R8_UINT:
    case DXGI_FORMAT_R8_UNORM:
        return 1;
    case DXGI_FORMAT_R16_UINT:
    case DXGI_FORMAT_R16_UNORM:
        return 2;
    default:
        return 0;
    }
}

void RGYFilterLibplacebo::close() {
    m_textIn.reset();
    m_textOut.reset();
    m_textFrameBufOut.reset();
    m_srcCrop.reset();
    m_dstCrop.reset();
    
    m_renderer.reset();
    m_dispatch.reset();
    m_d3d11.reset();
    m_libplaceboLoader.reset();
    m_log.reset();

    m_frameBuf.clear();
}

RGYFilterLibplaceboResample::RGYFilterLibplaceboResample(shared_ptr<RGYOpenCLContext> context) :
    RGYFilterLibplacebo(context),
    m_filter_params() {
    m_name = _T("libplacebo-resample");
}

RGYFilterLibplaceboResample::~RGYFilterLibplaceboResample() {
}

RGY_ERR RGYFilterLibplaceboResample::checkParam(const RGYFilterParam *param) {
    auto prm = dynamic_cast<const RGYFilterParamLibplaceboResample*>(param);
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }

    // prm->resampleの各値の範囲をチェック
    if (prm->resample.radius > 16.0f) {
        AddMessage(RGY_LOG_ERROR, _T("radius must be between 0.0f and 16.0f.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->resample.blur < 0.0f || prm->resample.blur > 100.0f) {
        AddMessage(RGY_LOG_ERROR, _T("blur must be between 0.0f and 100.0f.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->resample.taper < 0.0f || prm->resample.taper > 1.0f) {
        AddMessage(RGY_LOG_ERROR, _T("taper must be between 0.0f and 1.0f.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->resample.clamp_ < 0.0f || prm->resample.clamp_ > 1.0f) {
        AddMessage(RGY_LOG_ERROR, _T("clamp must be between 0.0f and 1.0f.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->resample.antiring < 0.0f || prm->resample.antiring > 1.0f) {
        AddMessage(RGY_LOG_ERROR, _T("antiring must be between 0.0f and 1.0f.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->resample.cplace < 0 || prm->resample.cplace > 2) {
        AddMessage(RGY_LOG_ERROR, _T("cplace must be between 0 and 2.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    return RGY_ERR_NONE;
}

RGY_ERR RGYFilterLibplaceboResample::setLibplaceboParam(const RGYFilterParam *param) {
    auto prm = dynamic_cast<const RGYFilterParamLibplaceboResample*>(param);

    m_filter_params = std::make_unique<pl_sample_filter_params>();
    m_filter_params->no_widening = false;
    m_filter_params->no_compute = false;
    m_filter_params->antiring = prm->resample.antiring;

    auto resample_filter_name = resize_algo_rgy_to_libplacebo(prm->resize_algo);
    if (resample_filter_name == nullptr) {
        AddMessage(RGY_LOG_ERROR, _T("unsupported resize algorithm.\n"));
        return RGY_ERR_UNSUPPORTED;
    }

    auto filter_config = pl_find_filter_config(resample_filter_name, PL_FILTER_UPSCALING);
    if (!filter_config) {
        AddMessage(RGY_LOG_ERROR, _T("unsupported filter type.\n"));
        return RGY_ERR_UNSUPPORTED;
    }
    m_filter_params->filter = *filter_config;
    m_filter_params->filter.clamp = prm->resample.clamp_;
    m_filter_params->filter.blur = prm->resample.blur;
    m_filter_params->filter.taper = prm->resample.taper;
    if (prm->resample.radius >= 0.0) {
        if (!m_filter_params->filter.kernel->resizable) {
            AddMessage(RGY_LOG_WARN, _T("radius %.1f ignored for non-resizable filter: %s.\n"), char_to_tstring(resample_filter_name).c_str());
        } else {
            m_filter_params->filter.radius = prm->resample.radius;
        }
    }
    return RGY_ERR_NONE;
}

RGY_ERR RGYFilterLibplaceboResample::procPlane(pl_tex texOut, const RGYFrameInfo *pDstPlane, pl_tex texIn, const RGYFrameInfo *pSrcPlane, [[maybe_unused]] const RGY_PLANE planeIdx) {
    auto prm = dynamic_cast<RGYFilterParamLibplaceboResample*>(m_param.get());
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }

    pl_shader_obj lut = { 0 };
    auto filter_params = m_filter_params.get();
    filter_params->lut = &lut;

    std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter> tex_tmp1;

    pl_sample_src src = { 0 };
    src.tex = texIn;
    {
        pl_shader shader1 = pl_dispatch_begin(m_dispatch.get());

        pl_tex_params tex_params = { 0 };
        tex_params.w = src.tex->params.w;
        tex_params.h = src.tex->params.h;
        tex_params.renderable = true;
        tex_params.sampleable = true;
        tex_params.format = src.tex->params.format;

        tex_tmp1 = rgy_pl_tex_recreate(m_d3d11->gpu, tex_params);
        if (!tex_tmp1) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to recreate texture.\n"));
            return RGY_ERR_UNKNOWN;
        }

        pl_shader_sample_direct(shader1, &src);

        //if (d->linear) {
        //    pl_color_space colorspace;
        //    colorspace.transfer = d->trc;
        //    pl_shader_linearize(shader1, &colorspace);
        //}
//
        //if (d->sigmoid_params.get()) {
        //    pl_shader_sigmoidize(shader1, d->sigmoid_params.get());
        //}

        pl_dispatch_params dispatch_params = { 0 };
        dispatch_params.target = tex_tmp1.get();
        dispatch_params.shader = &shader1;

        if (!pl_dispatch_finish(m_dispatch.get(), &dispatch_params)) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to dispatch (1).\n"));
            return RGY_ERR_UNKNOWN;
        }
    }

    src.tex = tex_tmp1.get();
    src.rect = pl_rect2df{ 0.0f, 0.0f, (float)pSrcPlane->width, (float)pSrcPlane->height };
    src.new_h = pDstPlane->height;
    src.new_w = pDstPlane->width;

    pl_shader shader2 = pl_dispatch_begin(m_dispatch.get());
    std::unique_ptr<std::remove_pointer<pl_tex>::type, RGYLibplaceboTexDeleter> tex_tmp2;
    if (filter_params->filter.polar) {
        if (!pl_shader_sample_polar(shader2, &src, filter_params)) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to sample polar.\n"));
            return RGY_ERR_UNKNOWN;
        }
    } else {
        pl_sample_src src1 = src;
        src.new_w = src.tex->params.w;
        src.rect.x0 = 0.0f;
        src.rect.x1 = (float)src.new_w;
        src1.rect.y0 = 0.0f;
        src1.rect.y1 = (float)src.new_h;
        {
            pl_shader shader3 = pl_dispatch_begin(m_dispatch.get());
            if (!pl_shader_sample_ortho2(shader3, &src, filter_params)) {
                pl_dispatch_abort(m_dispatch.get(), &shader3);
                AddMessage(RGY_LOG_ERROR, _T("Failed to sample ortho2(1).\n"));
                return RGY_ERR_UNKNOWN;
            }

            pl_tex_params tex_params = { 0 };
            tex_params.w = src.new_w;
            tex_params.h = src.new_h;
            tex_params.renderable = true;
            tex_params.sampleable = true;
            tex_params.format = src.tex->params.format;
            tex_tmp2 = rgy_pl_tex_recreate(m_d3d11->gpu, tex_params);
            if (!tex_tmp2) {
                AddMessage(RGY_LOG_ERROR, _T("Failed to recreate temp texture.\n"));
                return RGY_ERR_UNKNOWN;
            }

            pl_dispatch_params dispatch_params = { 0 };
            dispatch_params.target = tex_tmp2.get();
            dispatch_params.shader = &shader3;

            if (!pl_dispatch_finish(m_dispatch.get(), &dispatch_params)) {
                AddMessage(RGY_LOG_ERROR, _T("Failed to sample polar.\n"));
                return RGY_ERR_UNKNOWN;
            }
        }

        src1.tex = tex_tmp2.get();
        src1.scale = 1.0f;

        if (!pl_shader_sample_ortho2(shader2, &src1, filter_params)) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to sample ortho2(2).\n"));
            return RGY_ERR_UNKNOWN;
        }
    }

    //if (d->sigmoid_params.get()) {
    //    pl_shader_unsigmoidize(shader2, d->sigmoid_params.get());
    //}

    //if (d->linear) {
    //    pl_color_space colorspace;
    //    colorspace.transfer = d->trc;
    //    pl_shader_delinearize(shader2, &colorspace);
    //}

    pl_dispatch_params dispatch_params = { 0 };
    dispatch_params.target = texOut;
    dispatch_params.shader = &shader2;

    if (!pl_dispatch_finish(m_dispatch.get(), &dispatch_params)) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to dispatch (2).\n"));
        return RGY_ERR_UNKNOWN;
    }
    pl_shader_obj_destroy(filter_params->lut);
    filter_params->lut = nullptr;
    return RGY_ERR_NONE;
}
    
RGYFilterLibplaceboDeband::RGYFilterLibplaceboDeband(shared_ptr<RGYOpenCLContext> context) :
    RGYFilterLibplacebo(context),
    m_filter_params(), m_filter_params_c(), m_dither_params(), m_frame_index(0) {
    m_name = _T("libplacebo-deband");
}

RGYFilterLibplaceboDeband::~RGYFilterLibplaceboDeband() {
}

RGY_ERR RGYFilterLibplaceboDeband::checkParam(const RGYFilterParam *param) {
    auto prm = dynamic_cast<const RGYFilterParamLibplaceboDeband*>(param);
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    // prm->debandの各値の範囲をチェック
    if (prm->deband.iterations < 0) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid iterations value. iterations must be 0 or more.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->deband.threshold < 0.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid threshold value. threshold must be 0 or more.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->deband.radius < 0.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid radius value. radius must be 0 or more.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->deband.grainY < 0.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid grain_y value. grain_y must be 0 or more.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    //if (prm->deband.grainC < 0.0f) {
    //    AddMessage(RGY_LOG_ERROR, _T("Invalid grain_c value. grain_c must be 0 or more.\n"));
    //    return RGY_ERR_INVALID_PARAM;
    //}
    if (prm->deband.lut_size < 0 || prm->deband.lut_size > 8) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid lut_size value. lut_size must be between 0 to 8.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    return RGY_ERR_NONE;
}

RGY_ERR RGYFilterLibplaceboDeband::setLibplaceboParam(const RGYFilterParam *param) {
    auto prm = dynamic_cast<const RGYFilterParamLibplaceboDeband*>(param);
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }

    m_dither_params.reset();
    m_filter_params.reset();
    m_filter_params_c.reset();
    auto prmPrev = dynamic_cast<RGYFilterParamLibplaceboDeband*>(m_param.get());
    if (prmPrev && prmPrev->deband.dither != prm->deband.dither) {
        m_dither_params.reset();
        m_dither_state.reset();
    }
    if (prm->deband.dither != VppLibplaceboDebandDitherMode::None) {
        if (!m_dither_params) {
            m_dither_params = std::make_unique<pl_dither_params>();
            m_dither_params->method = (pl_dither_method)((int)prm->deband.dither - 1);
            m_dither_params->lut_size = prm->deband.lut_size;
        }
        if (!m_dither_state) {
            m_dither_state = std::unique_ptr<pl_shader_obj, decltype(&pl_shader_obj_destroy)>(new pl_shader_obj, pl_shader_obj_destroy);
            memset(m_dither_state.get(), 0, sizeof(pl_shader_obj));
        }
    }

    m_filter_params = std::make_unique<pl_deband_params>();
    m_filter_params->iterations = prm->deband.iterations;
    m_filter_params->threshold = prm->deband.threshold;
    m_filter_params->radius = prm->deband.radius;
    m_filter_params->grain = prm->deband.grainY;
    if (prm->deband.grainC >= 0.0f && prm->deband.grainY != prm->deband.grainC) {
        m_filter_params_c = std::make_unique<pl_deband_params>(*m_filter_params.get());
        m_filter_params->grain = prm->deband.grainC;
    }
    return RGY_ERR_NONE;
}

RGY_ERR RGYFilterLibplaceboDeband::procPlane(pl_tex texOut, [[maybe_unused]] const RGYFrameInfo *pDstPlane, pl_tex texIn, const RGYFrameInfo *pSrcPlane, const RGY_PLANE planeIdx) {
    auto prm = dynamic_cast<const RGYFilterParamLibplaceboDeband*>(m_param.get());
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    pl_shader shader = pl_dispatch_begin(m_dispatch.get());
    if (!shader) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to begin shader.\n"));
        return RGY_ERR_UNKNOWN;
    }

    pl_shader_params shader_params = { 0 };
    shader_params.gpu = m_d3d11->gpu;
    shader_params.index = (decltype(shader_params.index))m_frame_index++;

    pl_shader_reset(shader, &shader_params);

    pl_sample_src src = { 0 };
    src.tex = texIn;

    pl_deband_params *filter_params = (m_filter_params_c && RGY_CSP_CHROMA_FORMAT[pSrcPlane->csp] != RGY_CHROMAFMT_RGB && (planeIdx == RGY_PLANE_U || planeIdx == RGY_PLANE_V))
        ? m_filter_params_c.get() : m_filter_params.get();
    pl_shader_deband(shader, &src, filter_params);

    if (m_dither_params) {
        pl_shader_dither(shader, texOut->params.format->component_depth[0], m_dither_state.get(), m_dither_params.get());
    }

    pl_dispatch_params dispatch_params = { 0 };
    dispatch_params.target = texOut;
    dispatch_params.shader = &shader;

    if (!pl_dispatch_finish(m_dispatch.get(), &dispatch_params)) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to dispatch.\n"));
        return RGY_ERR_UNKNOWN;
    }
    return RGY_ERR_NONE;
}

RGYFilterLibplaceboToneMapping::RGYFilterLibplaceboToneMapping(shared_ptr<RGYOpenCLContext> context) : RGYFilterLibplacebo(context), m_tonemap() {
    m_name = _T("libplacebo-tonemapping");
    m_procByFrame = true;
}
RGYFilterLibplaceboToneMapping::~RGYFilterLibplaceboToneMapping() {};

RGY_CSP RGYFilterLibplaceboToneMapping::getTextureCsp(const RGY_CSP csp) {
    const auto inChromaFmt = RGY_CSP_CHROMA_FORMAT[csp];
    return (inChromaFmt == RGY_CHROMAFMT_RGB) ? RGY_CSP_RGB_16 : RGY_CSP_YUV444_16;
}

DXGI_FORMAT RGYFilterLibplaceboToneMapping::getTextureDXGIFormat([[maybe_unused]] const RGY_CSP csp) {
    return DXGI_FORMAT_R16_UNORM;
}

RGY_ERR RGYFilterLibplaceboToneMapping::checkParam(const RGYFilterParam *param) {
    auto prm = dynamic_cast<const RGYFilterParamLibplaceboToneMapping*>(param);
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.src_max >= 0.0f && prm->toneMapping.src_min >= 0.0f && prm->toneMapping.src_min >= prm->toneMapping.src_max) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid source luminance range.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.dst_max >= 0.0f && prm->toneMapping.dst_min >= 0.0f && prm->toneMapping.dst_min >= prm->toneMapping.dst_max) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid destination luminance range.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.smooth_period <= 0.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid smoothing period.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.scene_threshold_low < 0.0f || prm->toneMapping.scene_threshold_high < prm->toneMapping.scene_threshold_low) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid scene change threshold.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.percentile < 0.0f || prm->toneMapping.percentile > 100.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid percentile for peak detection.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.black_cutoff < 0.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid black cutoff value.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (   prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::st2094_10
        || prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::st2094_40
        || prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::spline) {
        if (prm->toneMapping.tone_constants.st2094.knee_adaptation < 0.0f || prm->toneMapping.tone_constants.st2094.knee_adaptation > 1.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid knee adaptation value. Must be between 0.0 and 1.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
        if (prm->toneMapping.tone_constants.st2094.knee_min < 0.0f || prm->toneMapping.tone_constants.st2094.knee_min > 0.5f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid knee minimum value. Must be between 0.0 and 0.5.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
        if (prm->toneMapping.tone_constants.st2094.knee_max < 0.5f || prm->toneMapping.tone_constants.st2094.knee_max > 1.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid knee maximum value. Must be between 0.5 and 1.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
        if (prm->toneMapping.tone_constants.st2094.knee_default < prm->toneMapping.tone_constants.st2094.knee_min || prm->toneMapping.tone_constants.st2094.knee_default > prm->toneMapping.tone_constants.st2094.knee_max) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid knee default value. Must be between knee minimum and knee maximum.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
    }
    if (prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::bt2390) {
        if (prm->toneMapping.tone_constants.bt2390.knee_offset < 0.5f || prm->toneMapping.tone_constants.bt2390.knee_offset > 2.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid knee offset value. Must be between 0.5 and 2.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
    }
    if (prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::spline) {
        if (prm->toneMapping.tone_constants.spline.slope_tuning < 0.0f || prm->toneMapping.tone_constants.spline.slope_tuning > 10.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid slope tuning value. Must be between 0.0 and 10.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
        if (prm->toneMapping.tone_constants.spline.slope_offset < 0.0f || prm->toneMapping.tone_constants.spline.slope_offset > 1.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid slope offset value. Must be between 0.0 and 1.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
        if (prm->toneMapping.tone_constants.spline.spline_contrast < 0.0f || prm->toneMapping.tone_constants.spline.spline_contrast > 1.5f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid spline contrast value. Must be between 0.0 and 1.5.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
    }
    if (prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::reinhard) {
        if (prm->toneMapping.tone_constants.reinhard.contrast < 0.0f || prm->toneMapping.tone_constants.reinhard.contrast > 1.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid reinhard contrast value. Must be between 0.0 and 1.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
    }
    if (   prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::mobius
        || prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::gamma) {
        if (prm->toneMapping.tone_constants.mobius.linear_knee < 0.0f || prm->toneMapping.tone_constants.mobius.linear_knee > 1.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid linear knee value. Must be between 0.0 and 1.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
    }
    if (   prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::linear
        || prm->toneMapping.tonemapping_function == VppLibplaceboToneMappingFunction::linearlight) {
        if (prm->toneMapping.tone_constants.linear.exposure < 0.0f || prm->toneMapping.tone_constants.linear.exposure > 10.0f) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid exposure value. Must be between 0.0 and 10.0.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
    }
    if (prm->toneMapping.contrast_recovery < 0.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid contrast recovery strength.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.contrast_smoothness < 0.0f) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid contrast recovery smoothness.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    return RGY_ERR_NONE;
}

RGY_ERR RGYFilterLibplaceboToneMapping::setLibplaceboParam(const RGYFilterParam *param) {
    auto prm = dynamic_cast<const RGYFilterParamLibplaceboToneMapping*>(param);
    if (!prm) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parameter type.\n"));
        return RGY_ERR_INVALID_PARAM;
    }
    m_tonemap.cspSrc = prm->toneMapping.src_csp;
    m_tonemap.cspDst = prm->toneMapping.dst_csp;

    m_tonemap.reprSrc = std::make_unique<pl_color_repr>();
    m_tonemap.reprSrc->bits.sample_depth = 16;
    m_tonemap.reprSrc->bits.color_depth = 16;
    m_tonemap.reprSrc->bits.bit_shift = 0;

    m_tonemap.reprDst = std::make_unique<pl_color_repr>();
    m_tonemap.reprDst->bits.sample_depth = 16;
    m_tonemap.reprDst->bits.color_depth = 16;
    m_tonemap.reprDst->bits.bit_shift = 0;

    const auto inChromaFmt = RGY_CSP_CHROMA_FORMAT[param->frameIn.csp];
    VideoVUIInfo vuiSrc = prm->vui;
    if (inChromaFmt == RGY_CHROMAFMT_RGB || inChromaFmt == RGY_CHROMAFMT_RGB_PACKED) {
        vuiSrc.setIfUnset(VideoVUIInfo().to(RGY_MATRIX_RGB).to(RGY_PRIM_BT709).to(RGY_TRANSFER_IEC61966_2_1));
    } else {
        vuiSrc.setIfUnset(VideoVUIInfo().to((CspMatrix)COLOR_VALUE_AUTO_RESOLUTION).to((CspColorprim)COLOR_VALUE_AUTO_RESOLUTION).to((CspTransfer)COLOR_VALUE_AUTO_RESOLUTION));
    }
    vuiSrc.apply_auto(VideoVUIInfo(), param->frameIn.height);

    if (m_tonemap.cspSrc == VppLibplaceboToneMappingCSP::Auto) {
        if (vuiSrc.transfer == RGY_TRANSFER_ARIB_B67) {
            m_tonemap.cspSrc = VppLibplaceboToneMappingCSP::HLG;
        } else if (vuiSrc.transfer == RGY_TRANSFER_ST2084) {
            m_tonemap.cspSrc = VppLibplaceboToneMappingCSP::HDR10;
        } else if (vuiSrc.transfer == RGY_TRANSFER_IEC61966_2_1) {
            m_tonemap.cspSrc = VppLibplaceboToneMappingCSP::RGB;
        } else {
            m_tonemap.cspSrc = VppLibplaceboToneMappingCSP::SDR;
        }
    }

    switch (m_tonemap.cspSrc) {
        case VppLibplaceboToneMappingCSP::SDR:
            m_tonemap.plCspSrc = m_libplaceboLoader->pl_color_space_bt709();
            m_tonemap.reprSrc->sys = (vuiSrc.matrix == RGY_MATRIX_BT470_BG) ? PL_COLOR_SYSTEM_BT_601 : PL_COLOR_SYSTEM_BT_709;
            m_tonemap.reprSrc->levels = (vuiSrc.colorrange == RGY_COLORRANGE_FULL) ? PL_COLOR_LEVELS_FULL : PL_COLOR_LEVELS_LIMITED;
            break;
        case VppLibplaceboToneMappingCSP::HDR10:
        case VppLibplaceboToneMappingCSP::DOVI:
            m_tonemap.plCspSrc = m_libplaceboLoader->pl_color_space_hdr10();
            m_tonemap.reprSrc->sys = PL_COLOR_SYSTEM_BT_2020_NC;
            m_tonemap.reprSrc->levels = (vuiSrc.colorrange == RGY_COLORRANGE_FULL) ? PL_COLOR_LEVELS_FULL : PL_COLOR_LEVELS_LIMITED;
            break;
        case VppLibplaceboToneMappingCSP::HLG:
            m_tonemap.plCspSrc = m_libplaceboLoader->pl_color_space_bt2020_hlg();
            m_tonemap.reprSrc->sys = PL_COLOR_SYSTEM_BT_2020_NC;
            m_tonemap.reprSrc->levels = (vuiSrc.colorrange == RGY_COLORRANGE_FULL) ? PL_COLOR_LEVELS_FULL : PL_COLOR_LEVELS_LIMITED;
            break;
        case VppLibplaceboToneMappingCSP::RGB:
            m_tonemap.plCspSrc = m_libplaceboLoader->pl_color_space_srgb();
            m_tonemap.reprSrc->sys = PL_COLOR_SYSTEM_RGB;
            m_tonemap.reprSrc->levels = PL_COLOR_LEVELS_FULL;
            break;
        default:
            AddMessage(RGY_LOG_ERROR, _T("Invalid source color space.\n"));
            return RGY_ERR_INVALID_PARAM;
    }
    if (prm->toneMapping.dst_pl_colorprim != VppLibplaceboToneMappingColorprim::Unknown && prm->toneMapping.dst_pl_transfer != VppLibplaceboToneMappingTransfer::Unknown) {
        m_tonemap.plCspDst.primaries = (pl_color_primaries)prm->toneMapping.dst_pl_colorprim;
        m_tonemap.plCspDst.transfer = (pl_color_transfer)prm->toneMapping.dst_pl_transfer;
        m_tonemap.plCspDst.hdr = m_libplaceboLoader->pl_hdr_metadata_empty();

        switch (m_tonemap.plCspDst.transfer) {
        case PL_COLOR_TRC_SRGB:
            m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_RGB;
            m_tonemap.reprDst->levels = PL_COLOR_LEVELS_FULL;
            m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_RGB).to(RGY_TRANSFER_IEC61966_2_1).to(RGY_PRIM_BT709);
            m_tonemap.outVui.colorrange = RGY_COLORRANGE_FULL;
            m_tonemap.outVui.descriptpresent = 1;
            break;
        case PL_COLOR_TRC_BT_1886:
        case PL_COLOR_TRC_LINEAR:
        case PL_COLOR_TRC_GAMMA18:
        case PL_COLOR_TRC_GAMMA20:
        case PL_COLOR_TRC_GAMMA22:
        case PL_COLOR_TRC_GAMMA24:
        case PL_COLOR_TRC_GAMMA26:
        case PL_COLOR_TRC_GAMMA28:
        case PL_COLOR_TRC_PRO_PHOTO:
        case PL_COLOR_TRC_ST428:
            m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_BT_709;
            m_tonemap.reprDst->levels = PL_COLOR_LEVELS_LIMITED;
            m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_BT709).to(RGY_TRANSFER_BT709).to(RGY_PRIM_BT709);
            m_tonemap.outVui.colorrange = RGY_COLORRANGE_LIMITED;
            m_tonemap.outVui.descriptpresent = 1;
            break;
        case PL_COLOR_TRC_HLG:
            m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_BT_2020_NC;
            m_tonemap.reprDst->levels = PL_COLOR_LEVELS_LIMITED;
            m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_BT2020_NCL).to(RGY_TRANSFER_ARIB_B67).to(RGY_PRIM_BT2020);
            m_tonemap.outVui.colorrange = RGY_COLORRANGE_LIMITED;
            m_tonemap.outVui.descriptpresent = 1;
            break;
        case PL_COLOR_TRC_PQ:
        case PL_COLOR_TRC_V_LOG:
        case PL_COLOR_TRC_S_LOG1:
        case PL_COLOR_TRC_S_LOG2:
            m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_BT_2020_NC;
            m_tonemap.reprDst->levels = PL_COLOR_LEVELS_LIMITED;
            m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_BT2020_NCL).to(RGY_TRANSFER_ST2084).to(RGY_PRIM_BT2020);
            m_tonemap.outVui.colorrange = RGY_COLORRANGE_LIMITED;
            m_tonemap.outVui.descriptpresent = 1;
            break;
        default:
            AddMessage(RGY_LOG_ERROR, _T("Invalid destination color space.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
        m_tonemap.reprDst->levels = PL_COLOR_LEVELS_LIMITED;
    } else {
        switch (prm->toneMapping.dst_csp) {
            case VppLibplaceboToneMappingCSP::SDR:
                m_tonemap.plCspDst = m_libplaceboLoader->pl_color_space_bt709();
                m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_BT_709;
                m_tonemap.reprDst->levels = PL_COLOR_LEVELS_LIMITED;
                m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_BT709).to(RGY_TRANSFER_BT709).to(RGY_PRIM_BT709);
                m_tonemap.outVui.colorrange = RGY_COLORRANGE_LIMITED;
                m_tonemap.outVui.descriptpresent = 1;
                break;
            case VppLibplaceboToneMappingCSP::HDR10:
            case VppLibplaceboToneMappingCSP::DOVI:
                m_tonemap.plCspDst = m_libplaceboLoader->pl_color_space_hdr10();
                m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_BT_2020_NC;
                m_tonemap.reprDst->levels = PL_COLOR_LEVELS_LIMITED;
                m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_BT2020_NCL).to(RGY_TRANSFER_ST2084).to(RGY_PRIM_BT2020);
                m_tonemap.outVui.colorrange = RGY_COLORRANGE_LIMITED;
                m_tonemap.outVui.descriptpresent = 1;
                break;
            case VppLibplaceboToneMappingCSP::HLG:
                m_tonemap.plCspDst = m_libplaceboLoader->pl_color_space_bt2020_hlg();
                m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_BT_2020_NC;
                m_tonemap.reprDst->levels = PL_COLOR_LEVELS_LIMITED;
                m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_BT2020_NCL).to(RGY_TRANSFER_ARIB_B67).to(RGY_PRIM_BT2020);
                m_tonemap.outVui.colorrange = RGY_COLORRANGE_LIMITED;
                m_tonemap.outVui.descriptpresent = 1;
                break;
            case VppLibplaceboToneMappingCSP::RGB:
                m_tonemap.plCspDst = m_libplaceboLoader->pl_color_space_srgb();
                m_tonemap.reprDst->sys = PL_COLOR_SYSTEM_RGB;
                m_tonemap.reprDst->levels = PL_COLOR_LEVELS_FULL;
                m_tonemap.outVui = m_tonemap.outVui.to(RGY_MATRIX_RGB).to(RGY_TRANSFER_IEC61966_2_1).to(RGY_PRIM_BT709);
                m_tonemap.outVui.colorrange = RGY_COLORRANGE_FULL;
                m_tonemap.outVui.descriptpresent = 1;
                break;
            default:
                AddMessage(RGY_LOG_ERROR, _T("Invalid destination color space.\n"));
                return RGY_ERR_INVALID_PARAM;
        }
    }
    if (!prm->toneMapping.lut_path.empty()) {
        if (!rgy_file_exists(prm->toneMapping.lut_path.c_str())) {
            AddMessage(RGY_LOG_ERROR, _T("LUT file not found.\n"));
            return RGY_ERR_FILE_OPEN;
        }
        // prm->toneMapping.lut_path をバイナリモードでオープンし、中のデータをstd::vector<uint8_t>に読み込む
        std::ifstream lut_file(prm->toneMapping.lut_path, std::ios::binary | std::ios_base::in);
        if (!lut_file.is_open()) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to open LUT file.\n"));
            return RGY_ERR_FILE_OPEN;
        }
        lut_file.seekg(0, std::ios::end);
        std::vector<char> lut_data(lut_file.tellg());
        lut_file.seekg(0, std::ios::beg);
        lut_file.read(reinterpret_cast<char*>(lut_data.data()), lut_data.size());
        if (lut_data.size() == 0) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to read LUT file.\n"));
            return RGY_ERR_NULL_PTR;
        }

        m_tonemap.renderParams = std::make_unique<pl_render_params>();
        m_tonemap.renderParams->lut = pl_lut_parse_cube(m_log.get(), lut_data.data(), lut_data.size());
        if (!m_tonemap.renderParams->lut) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to parse LUT file.\n"));
            return RGY_ERR_INVALID_DATA_TYPE;
        }
        m_tonemap.renderParams->lut_type = (pl_lut_type)prm->toneMapping.lut_type;
    } else {
        if (prm->toneMapping.src_csp == VppLibplaceboToneMappingCSP::DOVI) {
            m_tonemap.plDoviMeta = std::make_unique<pl_dovi_metadata>();
        }
        if (prm->toneMapping.src_max < 0.0f) {
            m_tonemap.src_max_org = prm->toneMapping.src_max;
            m_tonemap.plCspSrc.hdr.max_luma = (m_tonemap.cspSrc == VppLibplaceboToneMappingCSP::SDR) ? FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MAX_SDR : FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MAX_HDR;
        } else if (prm->toneMapping.src_max > 0.0f) {
            m_tonemap.src_max_org = prm->toneMapping.src_max;
            m_tonemap.plCspSrc.hdr.max_luma = m_tonemap.src_max_org;
        }
        if (prm->toneMapping.src_min < 0.0f) {
            m_tonemap.src_min_org = prm->toneMapping.src_min;
            m_tonemap.plCspSrc.hdr.min_luma = (m_tonemap.cspSrc == VppLibplaceboToneMappingCSP::SDR) ? FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MIN_SDR : FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MIN_HDR;
        } else if (prm->toneMapping.src_min > 0.0f) {
            m_tonemap.src_min_org = prm->toneMapping.src_min;
            m_tonemap.plCspSrc.hdr.min_luma = m_tonemap.src_min_org;
        }
        if (prm->toneMapping.dst_max < 0.0f) {
            m_tonemap.dst_max_org = prm->toneMapping.dst_max;
            m_tonemap.plCspDst.hdr.max_luma = (m_tonemap.cspDst == VppLibplaceboToneMappingCSP::SDR) ? FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MAX_SDR : FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MAX_HDR;
        } else if (prm->toneMapping.dst_max > 0.0f) {
            m_tonemap.dst_max_org = prm->toneMapping.dst_max;
            m_tonemap.plCspDst.hdr.max_luma = prm->toneMapping.dst_max;
        }
        if (prm->toneMapping.dst_min < 0.0f) {
            m_tonemap.dst_min_org = prm->toneMapping.dst_min;
            m_tonemap.plCspDst.hdr.min_luma = (m_tonemap.cspDst == VppLibplaceboToneMappingCSP::SDR) ? FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MIN_SDR : FILTER_DEFAULT_LIBPLACEBO_TONEMAPPING_NIT_MIN_HDR;
        } else if (prm->toneMapping.dst_min > 0.0f) {
            m_tonemap.dst_min_org = prm->toneMapping.dst_min;
            m_tonemap.plCspDst.hdr.min_luma = prm->toneMapping.dst_min;
        }
        m_tonemap.colorMapParams = std::make_unique<pl_color_map_params>(pl_color_map_default_params);
        m_tonemap.colorMapParams->tone_constants.knee_adaptation = prm->toneMapping.tone_constants.st2094.knee_adaptation;
        m_tonemap.colorMapParams->tone_constants.knee_minimum = prm->toneMapping.tone_constants.st2094.knee_min;
        m_tonemap.colorMapParams->tone_constants.knee_maximum = prm->toneMapping.tone_constants.st2094.knee_max;
        m_tonemap.colorMapParams->tone_constants.knee_default = prm->toneMapping.tone_constants.st2094.knee_default;
        m_tonemap.colorMapParams->tone_constants.knee_offset = prm->toneMapping.tone_constants.bt2390.knee_offset;
        m_tonemap.colorMapParams->tone_constants.slope_tuning = prm->toneMapping.tone_constants.spline.slope_tuning;
        m_tonemap.colorMapParams->tone_constants.slope_offset = prm->toneMapping.tone_constants.spline.slope_offset;
        m_tonemap.colorMapParams->tone_constants.spline_contrast = prm->toneMapping.tone_constants.spline.spline_contrast;
        m_tonemap.colorMapParams->tone_constants.reinhard_contrast = prm->toneMapping.tone_constants.reinhard.contrast;
        m_tonemap.colorMapParams->tone_constants.linear_knee = prm->toneMapping.tone_constants.mobius.linear_knee;
        m_tonemap.colorMapParams->tone_constants.exposure = prm->toneMapping.tone_constants.linear.exposure;

        m_tonemap.colorMapParams->gamut_mapping = pl_find_gamut_map_function(tchar_to_string(get_cx_desc(list_vpp_libplacebo_tone_mapping_gamut_mapping, (int)prm->toneMapping.gamut_mapping)).c_str());
        if (!m_tonemap.colorMapParams->gamut_mapping) {
            AddMessage(RGY_LOG_ERROR, _T("Invalid gamut mapping.\n"));
            return RGY_ERR_INVALID_PARAM;
        }
        m_tonemap.colorMapParams->metadata = tone_map_metadata_rgy_to_libplacebo(prm->toneMapping.metadata);
        m_tonemap.colorMapParams->visualize_lut = prm->toneMapping.visualize_lut;
        m_tonemap.colorMapParams->show_clipping = prm->toneMapping.show_clipping;
        m_tonemap.colorMapParams->contrast_recovery = prm->toneMapping.contrast_recovery;
        m_tonemap.colorMapParams->contrast_smoothness = prm->toneMapping.contrast_smoothness;

        m_tonemap.peakDetectParams = std::make_unique<pl_peak_detect_params>(m_libplaceboLoader->pl_peak_detect_default_params());
        m_tonemap.peakDetectParams->smoothing_period = prm->toneMapping.smooth_period;
        m_tonemap.peakDetectParams->scene_threshold_low = prm->toneMapping.scene_threshold_low;
        m_tonemap.peakDetectParams->scene_threshold_high = prm->toneMapping.scene_threshold_high;
        m_tonemap.peakDetectParams->percentile = prm->toneMapping.percentile;
        m_tonemap.peakDetectParams->black_cutoff = prm->toneMapping.black_cutoff;

        if (!ENABLE_LIBDOVI) {
            if (prm->toneMapping.use_dovi > 0) {
                AddMessage(RGY_LOG_ERROR, _T("use_dovi is not supported without libdovi.\n"));
                return RGY_ERR_INVALID_PARAM;
            }
            m_tonemap.use_dovi = 0;
        } else {
            m_tonemap.use_dovi = prm->toneMapping.use_dovi >= 0 ? prm->toneMapping.use_dovi : m_tonemap.cspSrc == VppLibplaceboToneMappingCSP::DOVI;
        }
    }

    auto setHdrMetadata = [](pl_color_space& plCsp, const VppLibplaceboToneMappingCSP prm_csp, const float max_org, const float min_org, const RGYHDRMetadata *hdrMetadata) {
        const auto hdrMetadataPrm = hdrMetadata->getprm();
        if (hdrMetadataPrm.contentlight_set) {
            plCsp.hdr.max_cll = (float)hdrMetadataPrm.maxcll;
            plCsp.hdr.max_fall = (float)hdrMetadataPrm.maxfall;
        }
        if (hdrMetadataPrm.masterdisplay_set) {
            if (max_org < 1.0f) {
                plCsp.hdr.max_luma = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::L_Max].qfloat();
            }
            if (min_org < 0.0f) {
                plCsp.hdr.min_luma = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::L_Min].qfloat();
            }
            plCsp.hdr.prim.red.x = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::R_X].qfloat();
            plCsp.hdr.prim.red.y = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::R_Y].qfloat();
            plCsp.hdr.prim.green.x = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::G_X].qfloat();
            plCsp.hdr.prim.green.y = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::G_Y].qfloat();
            plCsp.hdr.prim.blue.x = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::B_X].qfloat();
            plCsp.hdr.prim.blue.y = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::B_Y].qfloat();
            plCsp.hdr.prim.white.x = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::WP_X].qfloat();
            plCsp.hdr.prim.white.y = hdrMetadataPrm.masterdisplay[RGYHDRMetadataPrmIndex::WP_Y].qfloat();
        } else {
            pl_raw_primaries_merge(&plCsp.hdr.prim, pl_raw_primaries_get((prm_csp == VppLibplaceboToneMappingCSP::SDR) ? plCsp.primaries : PL_COLOR_PRIM_DISPLAY_P3));
        }
    };

    if (prm->hdrMetadataIn) {
        setHdrMetadata(m_tonemap.plCspSrc, m_tonemap.cspSrc, m_tonemap.src_max_org, m_tonemap.src_min_org, prm->hdrMetadataIn);
    }
    if (prm->hdrMetadataOut) {
        setHdrMetadata(m_tonemap.plCspDst, m_tonemap.cspDst, m_tonemap.dst_max_org, m_tonemap.dst_min_org, prm->hdrMetadataOut);
    }
    m_pathThrough &= (~FILTER_PATHTHROUGH_DATA);
    return RGY_ERR_NONE;
}

tstring RGYFilterLibplaceboToneMapping::printParams(const RGYFilterParamLibplacebo *prm) const {
    tstring str;
    for (const auto& token : split(prm->print(), _T(","))) {
        auto tok2 = split(trim(token), _T("="));
        if (tok2.size() == 2) {
            try {
                if (tok2[0] == _T("src_csp") && tok2[1] == get_cx_desc(list_vpp_libplacebo_tone_mapping_csp, (int)VppLibplaceboToneMappingCSP::Auto)) {
                    str += strsprintf(_T("src_csp=auto (%s),"), get_cx_desc(list_vpp_libplacebo_tone_mapping_csp, (int)m_tonemap.cspSrc));
                    continue;
                } else if (tok2[0] == _T("dst_csp") && tok2[1] == get_cx_desc(list_vpp_libplacebo_tone_mapping_csp, (int)VppLibplaceboToneMappingCSP::Auto)) {
                    str += strsprintf(_T("dst_csp=auto (%s),"), get_cx_desc(list_vpp_libplacebo_tone_mapping_csp, (int)m_tonemap.cspDst));
                    continue;
                } else if (tok2[0] == _T("src_max") && std::stof(tok2[1]) < 0) {
                    str += strsprintf(_T("src_max=auto (%.2f),"), m_tonemap.plCspSrc.hdr.max_luma);
                    continue;
                } else if (tok2[0] == _T("src_min") && std::stof(tok2[1]) < 0) {
                    str += strsprintf(_T("src_min=auto (%.2f),"), m_tonemap.plCspSrc.hdr.min_luma);
                    continue;
                } else if (tok2[0] == _T("dst_max") && std::stof(tok2[1]) < 0) {
                    str += strsprintf(_T("dst_max=auto (%.2f),"), m_tonemap.plCspDst.hdr.max_luma);
                    continue;
                } else if (tok2[0] == _T("dst_min") && std::stof(tok2[1]) < 0) {
                    str += strsprintf(_T("dst_min=auto (%.2f),"), m_tonemap.plCspDst.hdr.min_luma);
                    continue;
                } else if (tok2[0] == _T("use_dovi") && (tok2[1] == _T("auto") || std::stoi(tok2[1]) < 0)) {
                    str += strsprintf(_T("use_dovi=auto (%s),"), m_tonemap.use_dovi ? _T("on") : _T("off"));
                    continue;
                }
            } catch (...) {
                ; //なにもしない
            }
        }
        str += token + _T(",");
    }
    return str;
}

#if ENABLE_LIBDOVI
static std::unique_ptr<pl_dovi_metadata> createDOVIMeta(const DoviRpuOpaque *rpu, const DoviRpuDataHeader *hdr) {
    auto dovi_meta = std::make_unique<pl_dovi_metadata>();
    if (hdr->use_prev_vdr_rpu_flag) {
        return dovi_meta;
    }
    if (std::unique_ptr<const DoviRpuDataMapping, decltype(&dovi_rpu_free_data_mapping)> mapping(dovi_rpu_get_data_mapping(rpu), dovi_rpu_free_data_mapping);
        mapping) {
        const auto scale = 1.0f / (float)(1 << hdr->coefficient_log2_denom);

        for (size_t ic = 0; ic < _countof(mapping->curves); ic++) {
            const DoviReshapingCurve& curve = mapping->curves[ic];
            auto& cmp = dovi_meta->comp[ic];
            cmp.num_pivots = (decltype(cmp.num_pivots))curve.pivots.len;
            for (size_t i = 0; i < _countof(cmp.method); i++) {
                cmp.method[i] = curve.mapping_idc;
            }
            {
                uint32_t pivot = 0;
                for (int ip = 0; ip < (int)cmp.num_pivots; ip++) {
                    pivot += curve.pivots.data[ip];
                    cmp.pivots[ip] = pivot / (float)((1 << (hdr->bl_bit_depth_minus8 + 8)) - 1);
                }
            }

            memset(cmp.poly_coeffs, 0, sizeof(cmp.poly_coeffs));

            for (int ip = 0; ip < (int)cmp.num_pivots - 1; ip++) {
                if (curve.polynomial) {
                    for (int64_t i = 0; i <= (int64_t)curve.polynomial->poly_order_minus1.data[ip] + 1; i++) {
                        cmp.poly_coeffs[ip][i] = curve.polynomial->poly_coef_int.list[ip]->data[i] + curve.polynomial->poly_coef.list[ip]->data[i] * scale;
                    }
                } else if (curve.mmr) {
                    cmp.mmr_order[ip] = curve.mmr->mmr_order_minus1.data[ip] + 1;
                    cmp.mmr_constant[ip] = curve.mmr->mmr_constant_int.data[ip] + curve.mmr->mmr_constant.data[ip] * scale;
                    for (size_t j = 0; j < cmp.mmr_order[ip]; j++) {
                        for (size_t k = 0; k < _countof(cmp.mmr_coeffs[ip][j]); k++) {
                            cmp.mmr_coeffs[ip][j][k] = curve.mmr->mmr_coef_int.list[ip]->list[j]->data[k] + curve.mmr->mmr_coef.list[ip]->list[j]->data[k] * scale;
                        }
                    }
                }
            }
        }
    }

    if (hdr->vdr_dm_metadata_present_flag) {
        std::unique_ptr<const DoviVdrDmData, decltype(&dovi_rpu_free_vdr_dm_data)> vdr_dm_data(dovi_rpu_get_vdr_dm_data(rpu), dovi_rpu_free_vdr_dm_data);
        if (vdr_dm_data) {
            dovi_meta->nonlinear_offset[0] = (float)(vdr_dm_data->ycc_to_rgb_offset0 * (1.0 / (double)(1 << 28)));
            dovi_meta->nonlinear_offset[1] = (float)(vdr_dm_data->ycc_to_rgb_offset1 * (1.0 / (double)(1 << 28)));
            dovi_meta->nonlinear_offset[2] = (float)(vdr_dm_data->ycc_to_rgb_offset2 * (1.0 / (double)(1 << 28)));

            dovi_meta->nonlinear.m[0][0] = (float)(vdr_dm_data->ycc_to_rgb_coef0 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[0][1] = (float)(vdr_dm_data->ycc_to_rgb_coef1 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[0][2] = (float)(vdr_dm_data->ycc_to_rgb_coef2 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[1][0] = (float)(vdr_dm_data->ycc_to_rgb_coef3 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[1][1] = (float)(vdr_dm_data->ycc_to_rgb_coef4 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[1][2] = (float)(vdr_dm_data->ycc_to_rgb_coef5 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[2][0] = (float)(vdr_dm_data->ycc_to_rgb_coef6 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[2][1] = (float)(vdr_dm_data->ycc_to_rgb_coef7 * (1.0 / (double)(1 << 13)));
            dovi_meta->nonlinear.m[2][2] = (float)(vdr_dm_data->ycc_to_rgb_coef8 * (1.0 / (double)(1 << 13)));

            dovi_meta->linear.m[0][0] = (float)(vdr_dm_data->rgb_to_lms_coef0 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[0][1] = (float)(vdr_dm_data->rgb_to_lms_coef1 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[0][2] = (float)(vdr_dm_data->rgb_to_lms_coef2 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[1][0] = (float)(vdr_dm_data->rgb_to_lms_coef3 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[1][1] = (float)(vdr_dm_data->rgb_to_lms_coef4 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[1][2] = (float)(vdr_dm_data->rgb_to_lms_coef5 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[2][0] = (float)(vdr_dm_data->rgb_to_lms_coef6 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[2][1] = (float)(vdr_dm_data->rgb_to_lms_coef7 * (1.0 / (double)(1 << 14)));
            dovi_meta->linear.m[2][2] = (float)(vdr_dm_data->rgb_to_lms_coef8 * (1.0 / (double)(1 << 14)));
        }
    }
    return dovi_meta;
}
#endif // ENABLE_LIBDOVI

RGY_ERR RGYFilterLibplaceboToneMapping::setFrameParam(const RGYFrameInfo *pInputFrame) {
    for (const auto& frameData : pInputFrame->dataList) {
        if (frameData->dataType() == RGY_FRAME_DATA_HDR10PLUS) {

        } else if (frameData->dataType() == RGY_FRAME_DATA_DOVIRPU && m_tonemap.use_dovi) {
#if ENABLE_LIBDOVI
            auto dovi_rpu = dynamic_cast<const RGYFrameDataDOVIRpu*>(frameData.get());
            if (!dovi_rpu) {
                AddMessage(RGY_LOG_ERROR, _T("Invalid frame data type.\n"));
                return RGY_ERR_INVALID_DATA_TYPE;
            }
            const auto& rpu_data = dovi_rpu->getData();
            if (rpu_data.size() > 0) {
                std::unique_ptr<DoviRpuOpaque, decltype(&dovi_rpu_free)> rpu(dovi_parse_rpu(rpu_data.data(), rpu_data.size()), dovi_rpu_free);
                if (!rpu) {
                    AddMessage(RGY_LOG_ERROR, _T("failed parsing RPU\n"));
                    return RGY_ERR_INVALID_PARAM;
                }
                std::unique_ptr<const DoviRpuDataHeader, decltype(&dovi_rpu_free_header)> header(dovi_rpu_get_header(rpu.get()), dovi_rpu_free_header);
                if (!header) {
                    auto errstr = char_to_tstring(dovi_rpu_get_error(rpu.get()));
                    AddMessage(RGY_LOG_ERROR, _T("failed parsing RPU: %s\n"), errstr.c_str());
                    return RGY_ERR_INVALID_PARAM;
                }
                const auto dovi_profile = header->guessed_profile;
                m_tonemap.plDoviMeta = createDOVIMeta(rpu.get(), header.get());

                m_tonemap.reprSrc->sys = PL_COLOR_SYSTEM_DOLBYVISION;
                m_tonemap.reprSrc->dovi = m_tonemap.plDoviMeta.get();

                if (dovi_profile == 5) {
                    m_tonemap.reprDst->levels = PL_COLOR_LEVELS_FULL;
                }

                // Update mastering display from RPU
                if (header->vdr_dm_metadata_present_flag) {
                    std::unique_ptr<const DoviVdrDmData, decltype(&dovi_rpu_free_vdr_dm_data)> vdr_dm_data(dovi_rpu_get_vdr_dm_data(rpu.get()), dovi_rpu_free_vdr_dm_data);
                    if (!vdr_dm_data) {
                        AddMessage(RGY_LOG_ERROR, _T("failed parsing VDR DM data\n"));
                        return RGY_ERR_INVALID_PARAM;
                    }

                    m_tonemap.plCspDst.hdr.min_luma = (m_tonemap.cspDst == VppLibplaceboToneMappingCSP::HDR10) ? m_tonemap.plCspSrc.hdr.min_luma : pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, vdr_dm_data->source_min_pq / 4095.0f);
                    m_tonemap.plCspSrc.hdr.max_luma = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, vdr_dm_data->source_max_pq / 4095.0f);

                    if (vdr_dm_data->dm_data.level1) {
                        const DoviExtMetadataBlockLevel1* extL1 = vdr_dm_data->dm_data.level1;
                        m_tonemap.plCspSrc.hdr.avg_pq_y = extL1->avg_pq / 4095.0f;
                        m_tonemap.plCspSrc.hdr.max_pq_y = extL1->max_pq / 4095.0f;
                        m_tonemap.plCspSrc.hdr.scene_avg = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, extL1->avg_pq / 4095.0f);
                        m_tonemap.plCspSrc.hdr.scene_max[0] = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS, extL1->max_pq / 4095.0f);
                        m_tonemap.plCspSrc.hdr.scene_max[1] = m_tonemap.plCspSrc.hdr.scene_max[0];
                        m_tonemap.plCspSrc.hdr.scene_max[2] = m_tonemap.plCspSrc.hdr.scene_max[0];
                    }

                    if (vdr_dm_data->dm_data.level6) {
                        const DoviExtMetadataBlockLevel6* extL6 = vdr_dm_data->dm_data.level6;
                        m_tonemap.plCspSrc.hdr.max_cll = extL6->max_content_light_level;
                        m_tonemap.plCspSrc.hdr.max_fall = extL6->max_frame_average_light_level;
                    }
                }
            }
#endif
        }
    }

    pl_color_space_infer_map(&m_tonemap.plCspSrc, &m_tonemap.plCspDst);

    return RGY_ERR_NONE;
}

RGY_ERR RGYFilterLibplaceboToneMapping::procFrame(pl_tex texOut[RGY_MAX_PLANES], [[maybe_unused]] const RGYFrameInfo *pDstFrame, pl_tex texIn[RGY_MAX_PLANES], [[maybe_unused]] const RGYFrameInfo *pSrcFrame) {

    pl_frame frameIn = { 0 };
    frameIn.num_planes = 3;
    frameIn.repr = *m_tonemap.reprSrc.get();
    frameIn.color = m_tonemap.plCspSrc;
    for (int iplane = 0; iplane < 3; iplane++) {
        frameIn.planes[iplane].texture = texIn[iplane];
        frameIn.planes[iplane].components = 1;
        frameIn.planes[iplane].component_mapping[0] = iplane;
    }

    pl_frame frameOut = { 0 };
    frameOut.num_planes = 3;
    frameOut.repr = * m_tonemap.reprDst.get();
    frameOut.color = m_tonemap.plCspDst;
    for (int iplane = 0; iplane < 3; iplane++) {
        frameOut.planes[iplane].texture = texOut[iplane];
        frameOut.planes[iplane].components = 1;
        frameOut.planes[iplane].component_mapping[0] = iplane;
    }

    if (!pl_render_image(m_renderer.get(), &frameIn, &frameOut, m_tonemap.renderParams.get())) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to render image.\n"));
        return RGY_ERR_UNKNOWN;
    }
    return RGY_ERR_NONE;
}

void RGYFilterLibplaceboToneMapping::setFrameProp(RGYFrameInfo *dst, const RGYFrameInfo *src) const {
    dst->picstruct = src->picstruct;
    dst->timestamp = src->timestamp;
    dst->duration = src->duration;
    dst->inputFrameId = src->inputFrameId;
    dst->flags = src->flags;
    for (const auto& frameData : src->dataList) {
        if ((m_tonemap.cspDst == VppLibplaceboToneMappingCSP::SDR || m_tonemap.cspDst == VppLibplaceboToneMappingCSP::RGB)
            && (frameData->dataType() == RGY_FRAME_DATA_HDR10PLUS || frameData->dataType() == RGY_FRAME_DATA_DOVIRPU)) {
            // skip HDR data
        } else {
            dst->dataList.push_back(frameData);
        }
    }
}

VideoVUIInfo RGYFilterLibplaceboToneMapping::VuiOut() const {
    return m_tonemap.outVui;
}

#else

RGYFilterLibplaceboResample::RGYFilterLibplaceboResample(shared_ptr<RGYOpenCLContext> context) : RGYFilterDisabled(context) { m_name = _T("libplacebo-resample"); }
RGYFilterLibplaceboResample::~RGYFilterLibplaceboResample() {};

RGYFilterLibplaceboDeband::RGYFilterLibplaceboDeband(shared_ptr<RGYOpenCLContext> context) : RGYFilterDisabled(context) { m_name = _T("libplacebo-deband"); }
RGYFilterLibplaceboDeband::~RGYFilterLibplaceboDeband() {};

RGYFilterLibplaceboToneMapping::RGYFilterLibplaceboToneMapping(shared_ptr<RGYOpenCLContext> context) : RGYFilterDisabled(context) { m_name = _T("libplacebo-deband"); }
RGYFilterLibplaceboToneMapping::~RGYFilterLibplaceboToneMapping() {};

#endif // ENABLE_LIBPLACEBO
