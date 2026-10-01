#include "qsv_surf_trace.h"
int main() {
    mfxFrameSurface1 s[3] = {}; for (int i = 0; i < 3; i++) s[i].Data.TimeStamp = 90000 * (i + 1);
    for (int i = 0; i < 3; i++) s[i].Data.MemId = (mfxMemId)(uintptr_t)(0x1000 + i);
    for (int f = 0; f < 5; f++) QSV_TRACE(QT_ENC_CALL, 1, f, &s[f % 3], 0, f % 3, 1);
    QSV_TRACE(QT_GET_FREE, 0, 7, nullptr, 2, 0x5, 3);
    return 0;
}
