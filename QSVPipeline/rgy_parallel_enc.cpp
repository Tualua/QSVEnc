﻿// -----------------------------------------------------------------------------------------
// QSVEnc/NVEnc by rigaya
// -----------------------------------------------------------------------------------------
// The MIT License
//
// Copyright (c) 2011-2016 rigaya
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
// --------------------------------------------------------------------------------------------

#include "rgy_parallel_enc.h"
#include "rgy_filesystem.h"
#include "rgy_input.h"
#include "rgy_output.h"
#if ENCODER_QSV
#include "qsv_pipeline.h"
#elif ENCODER_NVENC
#include "nvenc_cmd.h"
#elif ENCODER_VCEENC
#include "vce_cmd.h"
#elif ENCODER_RKMPP
#include "rkmppenc_cmd.h"
#endif

static const int RGY_PARALLEL_ENC_TIMEOUT = 10000;

RGYParallelEncodeStatusData::RGYParallelEncodeStatusData() : encStatusData(), mtx_() {};

void RGYParallelEncodeStatusData::set(const EncodeStatusData& data) {
    std::lock_guard<std::mutex> lock(mtx_);
    if (encStatusData) {
        *encStatusData = data;
    } else {
        encStatusData = std::make_unique<EncodeStatusData>(data);
    }
}

bool RGYParallelEncodeStatusData::get(EncodeStatusData& data) {
    if (!encStatusData) {
        return false;
    }
    std::lock_guard<std::mutex> lock(mtx_);
    if (!encStatusData) {
        return false;
    }
    data = *encStatusData;
    return true;
}

void RGYParallelEncodeStatusData::reset() {
    std::lock_guard<std::mutex> lock(mtx_);
    encStatusData.reset();
}

RGYParallelEncProcess::RGYParallelEncProcess(const int id, const tstring& tmpfile, std::shared_ptr<RGYLog> log) :
    m_id(id),
    m_process(),
    m_qFirstProcessData(),
    m_qFirstProcessDataFree(),
    m_qFirstProcessDataFreeLarge(),
    m_sendData(),
    m_tmpfile(tmpfile),
    m_thRunProcess(),
    m_thRunProcessRet(),
    m_processFinished(unique_event(nullptr, nullptr)),
    m_thAbort(false),
    m_log(log) {
}

RGYParallelEncProcess::~RGYParallelEncProcess() {
    close();
}

RGY_ERR RGYParallelEncProcess::close() {
    auto err = RGY_ERR_NONE;
    if (m_thRunProcess.joinable()) {
        m_thAbort = true;
        m_thRunProcess.join();
        if (m_qFirstProcessData) {
            m_qFirstProcessData->close([](RGYOutputRawPEExtHeader **ptr) { if (*ptr) free(*ptr); });
            m_qFirstProcessData.reset();
        }
        if (m_qFirstProcessDataFree) {
            m_qFirstProcessDataFree->close([](RGYOutputRawPEExtHeader **ptr) { if (*ptr) free(*ptr); });
            m_qFirstProcessDataFree.reset();
        }
        if (m_qFirstProcessDataFreeLarge) {
            m_qFirstProcessDataFreeLarge->close([](RGYOutputRawPEExtHeader **ptr) { if (*ptr) free(*ptr); });
            m_qFirstProcessDataFreeLarge.reset();
        }
    }
    m_processFinished.reset();
    return err;
}

RGY_ERR RGYParallelEncProcess::run(const encParams& peParams) {
    m_process = std::make_unique<CQSVPipeline>();

    encParams encParam = peParams;
    encParam.ctrl.parallelEnc.sendData = &m_sendData;
    auto sts = m_process->Init(&encParam);
    if (sts != RGY_ERR_NONE) {
        return sts;
    }
    m_process->SetAbortFlagPointer(&m_thAbort);

    if ((sts = m_process->CheckCurrentVideoParam()) == RGY_ERR_NONE
        && (sts = m_process->Run()) == RGY_ERR_NONE) {
        m_process->Close();
    }
    return sts;
}

RGY_ERR RGYParallelEncProcess::startThread(const encParams& peParams) {
    m_sendData.eventChildHasSentFirstKeyPts = CreateEventUnique(nullptr, FALSE, FALSE);
    m_sendData.eventParentHasSentFinKeyPts = CreateEventUnique(nullptr, FALSE, FALSE);
    m_processFinished = CreateEventUnique(nullptr, FALSE, FALSE); // 処理終了の通知用
    if (peParams.ctrl.parallelEnc.parallelId == 0) {
        // 最初のプロセスのみ、キューを介してデータをやり取りする
        m_qFirstProcessData = std::make_unique<RGYQueueMPMP<RGYOutputRawPEExtHeader*>>();
        m_qFirstProcessDataFree = std::make_unique<RGYQueueMPMP<RGYOutputRawPEExtHeader*>>();
        m_qFirstProcessDataFreeLarge = std::make_unique<RGYQueueMPMP<RGYOutputRawPEExtHeader*>>();
        m_qFirstProcessData->init();
        m_qFirstProcessDataFree->init();
        m_qFirstProcessDataFreeLarge->init();
        m_sendData.qFirstProcessData = m_qFirstProcessData.get(); // キューのポインタを渡す
        m_sendData.qFirstProcessDataFree = m_qFirstProcessDataFree.get(); // キューのポインタを渡す
        m_sendData.qFirstProcessDataFreeLarge = m_qFirstProcessDataFreeLarge.get(); // キューのポインタを渡す
    }
    m_thRunProcess = std::thread([&]() {
        try {
            m_thRunProcessRet = run(peParams);
        } catch (...) {
            m_thRunProcessRet = RGY_ERR_UNKNOWN;
        }
        // 進捗表示のfpsを0にする
        EncodeStatusData encStatusData;
        if (m_sendData.encStatus.get(encStatusData)) {
            encStatusData.encodeFps = 0.0;
            m_sendData.encStatus.set(encStatusData);
        }
        SetEvent(m_processFinished.get()); // 処理終了を通知するのを忘れないように
        m_process->PrintMes(RGY_LOG_DEBUG, _T("\nPE%d: Processing finished: %s\n"), m_id, get_err_mes(m_thRunProcessRet.value()));
    });
    return RGY_ERR_NONE;
}

RGY_ERR RGYParallelEncProcess::getNextPacket(RGYOutputRawPEExtHeader **ptr) {
    if (!m_qFirstProcessData) {
        return RGY_ERR_NULL_PTR;
    }
    size_t nSize = 0;
    *ptr = nullptr;
    while (!m_qFirstProcessData->front_copy_and_pop_no_lock(ptr, &nSize)) {
        rgy_yield();
    }
    if ((*ptr == nullptr)) {
        return RGY_ERR_MORE_BITSTREAM;
    }
    return RGY_ERR_NONE;
}

RGY_ERR RGYParallelEncProcess::putFreePacket(RGYOutputRawPEExtHeader *ptr) {
    if (!m_qFirstProcessDataFree) {
        return RGY_ERR_NULL_PTR;
    }
    if (ptr->allocSize == 0) {
        return RGY_ERR_UNKNOWN;
    }
    RGYQueueMPMP<RGYOutputRawPEExtHeader*> *freeQueue = (ptr->allocSize <= RGY_PE_EXT_HEADER_DATA_NORMAL_BUF_SIZE) ? m_qFirstProcessDataFree.get() : m_qFirstProcessDataFreeLarge.get();
    freeQueue->push(ptr);
    return RGY_ERR_NONE;
}

int RGYParallelEncProcess::waitProcessStarted(const uint32_t timeout) {
    return WaitForSingleObject(m_sendData.eventChildHasSentFirstKeyPts.get(), timeout) == WAIT_OBJECT_0 ? 0 : 1;
}

RGY_ERR RGYParallelEncProcess::sendEndPts(const int64_t endPts) {
    if (!m_sendData.eventParentHasSentFinKeyPts) {
        return RGY_ERR_UNDEFINED_BEHAVIOR;
    }
    m_sendData.videoFinKeyPts = endPts;
    SetEvent(m_sendData.eventParentHasSentFinKeyPts.get());
    return RGY_ERR_NONE;
}

int RGYParallelEncProcess::waitProcessFinished(const uint32_t timeout) {
    if (!m_processFinished) {
        return -1;
    }
    return WaitForSingleObject(m_processFinished.get(), timeout);
}

RGYParallelEnc::RGYParallelEnc(std::shared_ptr<RGYLog> log) :
    m_id(-1),
    m_encProcess(),
    m_log(log),
    m_videoEndKeyPts(-1),
    m_videoFinished(false) {}

RGYParallelEnc::~RGYParallelEnc() {
    close();
}

void RGYParallelEnc::close() {
    for (auto &proc : m_encProcess) {
        proc->close();
    }
    m_encProcess.clear();
    m_videoEndKeyPts = -1;
}

int64_t RGYParallelEnc::getVideofirstKeyPts(const int processID) {
    if (processID >= m_encProcess.size()) {
        return -1;
    }
    return m_encProcess[processID]->getVideoFirstKeyPts();
}

std::vector<RGYParallelEncProcessData> RGYParallelEnc::peRawFilePaths() const {
    std::vector<RGYParallelEncProcessData> files;
    for (const auto &proc : m_encProcess) {
        files.push_back(proc->tmpfile());
    }
    return files;
}

RGY_ERR RGYParallelEnc::getNextPacketFromFirst(RGYOutputRawPEExtHeader **ptr) {
    if (m_encProcess.size() == 0) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid call for getNextPacketFromFirst.\n"));
        return RGY_ERR_UNKNOWN;
    }
    return m_encProcess.front()->getNextPacket(ptr);
}

RGY_ERR RGYParallelEnc::putFreePacket(RGYOutputRawPEExtHeader *ptr) {
    if (m_encProcess.size() == 0) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid call for pushNextPacket.\n"));
        return RGY_ERR_UNKNOWN;
    }
    return m_encProcess.front()->putFreePacket(ptr);
}

int RGYParallelEnc::waitProcessFinished(const int id, const uint32_t timeout) {
    if (id >= m_encProcess.size()) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parallel id #%d for waitProcess.\n"), id);
        return -1;
    }
    return m_encProcess[id]->waitProcessFinished(timeout);
}

std::optional<RGY_ERR> RGYParallelEnc::processReturnCode(const int id) {
    if (id >= m_encProcess.size()) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parallel id #%d for processReturnCode.\n"), id);
        return std::nullopt;
    }
    return m_encProcess[id]->processReturnCode();
}

std::vector< RGYParallelEncDevInfo> RGYParallelEnc::devInfo() const {
    std::vector< RGYParallelEncDevInfo> devInfoList;
    for (const auto &proc : m_encProcess) {
        devInfoList.push_back(proc->devInfo());
    }
    return devInfoList;
}

void RGYParallelEnc::encStatusReset(const int id) {
    if (id >= m_encProcess.size()) {
        AddMessage(RGY_LOG_ERROR, _T("Invalid parallel id #%d for encStatusReset.\n"), id);
        return;
    }
    m_encProcess[id]->getEncodeStatus()->reset();
}

std::pair<RGY_ERR, const TCHAR *> RGYParallelEnc::isParallelEncPossible(const encParams *prm, const RGYInput *input) {
    if (!input->seekable()) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: input is not seekable.\n") };
    }
    if (input->GetVideoFirstKeyPts() < 0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: invalid first key PTS.\n") };
    }
    if (prm->common.seekSec != 0.0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --seek is eanbled.\n") };
    }
    if (prm->common.seekToSec != 0.0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --seek-to is eanbled.\n") };
    }
    if (prm->common.nTrimCount != 0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --trim is eanbled.\n") };
    }
    if (prm->common.timecodeFile.length() != 0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --timecode is specified.\n") };
    }
    if (prm->common.tcfileIn.length() != 0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --tcfile-in is specified.\n") };
    }
    if (prm->common.keyFile.length() != 0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --keyfile is specified.\n") };
    }
    if (prm->common.metric.enabled()) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: ssim/psnr/vmaf is enabled.\n") };
    }
    if (prm->common.keyOnChapter) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --key-on-chapter is enabled.\n") };
    }
    if (prm->vpp.subburn.size() != 0) {
        return { RGY_ERR_UNSUPPORTED, _T("Parallel encoding is not possible: --vpp-subburn is specified.\n") };
    }
    return { RGY_ERR_NONE, _T("") };
}

RGY_ERR RGYParallelEnc::parallelChild(const encParams *prm, const RGYInput *input, const RGYParallelEncDevInfo& devInfo) {
    // 起動したプロセスから最初のキーフレームのptsを取得して、親プロセスに送る
    auto sendData = prm->ctrl.parallelEnc.sendData;
    sendData->videoFirstKeyPts = input->GetVideoFirstKeyPts();
    sendData->devInfo = devInfo;
    SetEvent(sendData->eventChildHasSentFirstKeyPts.get());

    // 親プロセスから終了時刻を受け取る
    WaitForSingleObject(sendData->eventParentHasSentFinKeyPts.get(), INFINITE);
    m_videoEndKeyPts = sendData->videoFinKeyPts;
    return RGY_ERR_NONE;
}

encParams RGYParallelEnc::genPEParam(const int ip, const encParams *prm, const tstring& tmpfile) {
    encParams prmParallel = *prm;
    prmParallel.ctrl.parallelEnc.parallelId = ip;
    prmParallel.ctrl.parentProcessID = GetCurrentProcessId();
    prmParallel.ctrl.loglevel = RGY_LOG_WARN;
    prmParallel.common.muxOutputFormat = _T("raw");
    prmParallel.common.outputFilename = tmpfile; // ip==0の場合のみ、実際にはキューを介してデータをやり取りするがとりあえずファイル名はそのまま入れる
    prmParallel.common.AVMuxTarget = RGY_MUX_NONE;
    prmParallel.common.audioSource.clear();
    prmParallel.common.subSource.clear();
    prmParallel.common.attachmentSource.clear();
    prmParallel.common.nAudioSelectCount = 0;
    prmParallel.common.ppAudioSelectList = nullptr;
    prmParallel.common.nSubtitleSelectCount = 0;
    prmParallel.common.ppSubtitleSelectList = nullptr;
    prmParallel.common.nDataSelectCount = 0;
    prmParallel.common.ppDataSelectList = nullptr;
    prmParallel.common.nAttachmentSelectCount = 0;
    prmParallel.common.ppAttachmentSelectList = nullptr;
    prmParallel.common.outReplayCodec = RGY_CODEC_UNKNOWN;
    prmParallel.common.outReplayFile.clear();
    prmParallel.common.seekRatio = ip / (float)prmParallel.ctrl.parallelEnc.parallelCount;
    return prmParallel;
}

RGY_ERR RGYParallelEnc::startParallelThreads(const encParams *prm, EncodeStatus *encStatus) {
    m_encProcess.clear();
    for (int ip = 0; ip < prm->ctrl.parallelEnc.parallelCount; ip++) {
        const auto tmpfile = prm->common.outputFilename + _T(".pe") + std::to_tstring(ip);
        const auto peParam = genPEParam(ip, prm, tmpfile);
        auto process = std::make_unique<RGYParallelEncProcess>(ip, tmpfile, m_log);
        if (auto err = process->startThread(peParam); err != RGY_ERR_NONE) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to run PE%d: %s.\n"), ip, get_err_mes(err));
            return err;
        }
        // 起動したプロセスから最初のキーフレームのptsを取得
        process->waitProcessStarted(INFINITE);
        const auto firstKeyPts = process->getVideoFirstKeyPts();
        if (firstKeyPts < 0) {
            AddMessage(RGY_LOG_ERROR, _T("Failed to get first key pts from PE%d.\n"), ip);
            return RGY_ERR_UNKNOWN;
        }
        AddMessage(RGY_LOG_DEBUG, _T("PE%d: Got first key pts %lld.\n"), ip, firstKeyPts);
        encStatus->addChildStatus({ 1.0f / prm->ctrl.parallelEnc.parallelCount, process->getEncodeStatus() });

        // 起動したプロセスの最初のキーフレームはひとつ前のプロセスのエンコード終了時刻
        if (ip > 0) {
            // ひとつ前のプロセスの終了時刻として転送
            AddMessage(RGY_LOG_DEBUG, _T("Send PE%d end key pts %lld.\n"), ip - 1, firstKeyPts);
            auto err = m_encProcess.back()->sendEndPts(firstKeyPts);
            if (err != RGY_ERR_NONE) {
                AddMessage(RGY_LOG_ERROR, _T("Failed to send end pts to PE%d: %s.\n"), ip - 1, get_err_mes(err));
                return err;
            }
        }
        AddMessage(RGY_LOG_DEBUG, _T("Started encoder PE%d.\n"), ip);
        m_encProcess.push_back(std::move(process));
    }
    //最後のプロセスの終了時刻(=終わりまで)を転送
    AddMessage(RGY_LOG_DEBUG, _T("Send PE%d end key pts -1.\n"), (int)m_encProcess.size() - 1);
    auto err = m_encProcess.back()->sendEndPts(-1);
    if (err != RGY_ERR_NONE) {
        AddMessage(RGY_LOG_ERROR, _T("Failed to send end pts to encoder PE%d: %s.\n"), (int)m_encProcess.size() - 1, get_err_mes(err));
        return err;
    }
    return RGY_ERR_NONE;
}

RGY_ERR RGYParallelEnc::parallelRun(encParams *prm, const RGYInput *input, EncodeStatus *encStatus, const RGYParallelEncDevInfo& devInfo) {
    if (!prm->ctrl.parallelEnc.isEnabled()) {
        return RGY_ERR_NONE;
    }
    m_id = prm->ctrl.parallelEnc.parallelId;
    if (prm->ctrl.parallelEnc.isChild()) { // 子プロセスから呼ばれた
        return parallelChild(prm, input, devInfo); // 子プロセスの処理
    }
    auto [sts, errmes ] = isParallelEncPossible(prm, input);
    if (sts != RGY_ERR_NONE
        || (sts = startParallelThreads(prm, encStatus)) != RGY_ERR_NONE) {
        // 並列処理を無効化して続行する
        m_encProcess.clear();
        prm->ctrl.parallelEnc.parallelCount = 0;
        prm->ctrl.parallelEnc.parallelId = -1;
        return sts;
    }
    return RGY_ERR_NONE;
}