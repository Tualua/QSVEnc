// qsv_surf_trace.h -- DIAGNOSTIC ONLY (phase 02.1, D-02/D-03). Own commit, never part of the fix.
// Lock-free in-memory ring of surface-path events; nothing is written until process exit.
// Enable at run time with QSVENC_TRACE_FILE=<path>; QSVENC_TRACE_CAP=<log2 events> (default 18 = 262144 rec = 14.7 MB).
#pragma once
#ifndef QSV_SURF_TRACE
#define QSV_SURF_TRACE 1
#endif
#if QSV_SURF_TRACE
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mfxstructures.h>   // mfxFrameSurface1

enum QsvTraceEv : uint16_t {
    QT_POOL      = 1,  // one record per pool slot at allocation: pool, a=slot, surf, memid, vaid ; frame=NumFrameActual
    QT_GET_FREE  = 2,  // getFreeSurf result: pool, a=slot(-1 none), b=non-free bitmask (slots 0..31), c=retry count i from getWorkSurf
    QT_DEC_CALL  = 3,  // after DecodeFrameAsync: surf=work, a=sts, b=out slot(-1), c=syncpoint!=0 ; frame=inputFrameId(-1 none)
    QT_VPP_CALL  = 4,  // after RunFrameVPPAsync: surf=out, a=sts, b=in slot, c=syncpoint!=0 ; frame=vpp out counter
    QT_ENC_CALL  = 5,  // after EncodeFrameAsync: surf=in, a=sts, b=Data.Locked after, c=syncpoint!=0 ; frame=chunk frame index (m_inFrames)
    QT_BS_SYNC   = 6,  // waitsync() done: a=SyncOperation sts, b=wait us, c=type (1 surf, 2 bitstream)
    QT_POLL      = 7,  // optional SyncOperation(sp,0) probe: a=sts (MFX_WRN_IN_EXECUTION=10 => producer still running), b=stage (0 dec,1 vpp)
};
#pragma pack(push, 1)
struct QsvTraceRec {            // 56 bytes
    uint64_t t_ns;
    uint64_t surf;              // mfxFrameSurface1*
    uint64_t memid;             // Data.MemId (vaapiMemId*)
    int64_t  ts;                // Data.TimeStamp of the surface at the event (tells WHICH input frame the surface carries)
    uint32_t vaid;              // VASurfaceID (0 if unknown)
    int32_t  frame;
    int32_t  a, b, c;
    uint16_t ev;
    uint16_t pool;              // 0 = dec->vpp edge pool, 1 = vpp->enc edge pool
};
#pragma pack(pop)
static_assert(sizeof(QsvTraceRec) == 56, "QsvTraceRec layout");

class QsvSurfTrace {
    std::unique_ptr<QsvTraceRec[]> m_buf;
    uint64_t m_mask = 0;
    std::atomic<uint64_t> m_n{0};
    const char *m_path = nullptr;
public:
    static QsvSurfTrace& get() { static QsvSurfTrace t; return t; }
    bool on() const { return m_path != nullptr; }
    QsvSurfTrace() {
        m_path = std::getenv("QSVENC_TRACE_FILE");
        if (!m_path || !*m_path) { m_path = nullptr; return; }
        const char *cap = std::getenv("QSVENC_TRACE_CAP");
        const int lg = (cap && *cap) ? std::atoi(cap) : 18;
        m_mask = (1ull << ((lg < 10 || lg > 24) ? 18 : lg)) - 1;
        m_buf.reset(new QsvTraceRec[m_mask + 1]());
    }
    ~QsvSurfTrace() { flush(); }
    void rec(uint16_t ev, uint16_t pool, int32_t frame, const mfxFrameSurface1 *s, int32_t a, int32_t b, int32_t c, uint32_t vaid = 0) {
        if (!on()) return;
        const uint64_t i = m_n.fetch_add(1, std::memory_order_relaxed);
        QsvTraceRec& r = m_buf[i & m_mask];
        r.t_ns = (uint64_t)std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
        r.surf = (uint64_t)(uintptr_t)s; r.memid = s ? (uint64_t)(uintptr_t)s->Data.MemId : 0; r.ts = s ? (int64_t)s->Data.TimeStamp : -1; r.vaid = vaid;
        r.frame = frame; r.a = a; r.b = b; r.c = c; r.ev = ev; r.pool = pool;
    }
    void flush() {                                    // O_EXCL-style: never clobber an existing file
        if (!on() || m_n.load() == 0) return;
        FILE *fp = std::fopen(m_path, "wbx");
        if (!fp) return;
        const uint64_t n = m_n.load(), cap = m_mask + 1, cnt = n < cap ? n : cap, first = n < cap ? 0 : (n & m_mask);
        const char magic[8] = {'Q','S','V','T','R','C','0','1'};
        const uint32_t recsz = sizeof(QsvTraceRec), c32 = (uint32_t)cnt;
        std::fwrite(magic, 1, 8, fp); std::fwrite(&recsz, 4, 1, fp); std::fwrite(&c32, 4, 1, fp);
        for (uint64_t k = 0; k < cnt; k++) std::fwrite(&m_buf[(first + k) & m_mask], sizeof(QsvTraceRec), 1, fp);
        std::fclose(fp);
        m_path = nullptr;
    }
};
#define QSV_TRACE(...) do { auto& _t = QsvSurfTrace::get(); if (_t.on()) _t.rec(__VA_ARGS__); } while (0)
#else
#define QSV_TRACE(...) do { } while (0)
#endif
