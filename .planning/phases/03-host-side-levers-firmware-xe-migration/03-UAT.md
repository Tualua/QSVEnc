---
status: testing
phase: 03-host-side-levers-firmware-xe-migration
source: [03-01-SUMMARY.md]
started: 2026-10-24T17:21:08Z
updated: 2026-10-25T15:08:37Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 4
name: Приватные данные не попали в git
expected: |
  В 03-EVIDENCE.md в разделе хостовой пробы и в ответах оператора нет вашего логина на NAS, пути /home/..., hostname, IP- или MAC-адресов. Вместо 13 строк dnf про GPG-ключи стоит одна строка-маркер об удалении по вашей просьбе, строки "Available upgrades" с версиями сохранены. В ответе (c) вместо логина стоит REDACTED-USER. Остальной текст пробы и ответов совпадает с оригиналом дословно.
awaiting: user response

## Tests

### 1. Проба на NAS отработала как read-only
expected: Запуск tools/capability_probe.sh на NAS завершился за 1-3 минуты и дал только файл scratch/host-levers/host_probe.txt. На хосте ничего не изменилось: пакеты не ставились и не обновлялись, модули не загружались, записи GRUB не менялись, перезагрузки не было, во временном каталоге dnf ничего не осталось.
result: pass

### 2. Хостовая колонка матрицы DIAG-01 совпадает с вашими ответами
expected: В 03-EVIDENCE.md, раздел "Capability matrix (DIAG-01)", хостовая колонка показывает: CAP-PRIV = available (настоящий root), CAP-REBOOT = blocked on host с вашей цитатой "Нет." и пометкой, что это политика оператора, CAP-CONSOLE = operator-declared (not tested) с цитатой про консоль, три строки *-CHG = operator-declared (not tested) с цитатой "Могу и вправе". Ни одна строка *-CHG не помечена available.
result: pass

### 3. Базовая линия прошивок и железа соответствует NAS
expected: Раздел "Firmware & driver versions (D-03 baseline)" в 03-EVIDENCE.md показывает для хоста: Arc Pro B50 (8086:e212) на драйвере xe в слоте 0000:19:00.0, GuC 70.60.0, HuC 8.2.10 (RUNNING на GT1, явной строки об аутентификации нет), DMC 2.6, пакеты linux-firmware / intel-gpu-firmware 20260410-1.fc43 с доступным обновлением 20261019-1.fc43. Это совпадает с тем, что вы знаете о машине.
result: pass

### 4. Приватные данные не попали в git
expected: В 03-EVIDENCE.md в разделе хостовой пробы и в ответах оператора нет вашего логина на NAS, пути /home/..., hostname, IP- или MAC-адресов. Вместо 13 строк dnf про GPG-ключи стоит одна строка-маркер об удалении по вашей просьбе, строки "Available upgrades" с версиями сохранены. В ответе (c) вместо логина стоит REDACTED-USER. Остальной текст пробы и ответов совпадает с оригиналом дословно.
result: [pending]

### 5. Смена A380 на B50 зафиксирована явно
expected: В 03-EVIDENCE.md есть отдельный раздел о замене GPU между пробами (A380/i915 3 октября, B50/xe 24 октября, перезагрузка хоста между ними), контейнерная колонка помечена датой 2026-10-03, а в 03-RUNBOOK.md рычаги L1 и L2 помечены как неприменимые к текущему железу с проверкой наличия устройства 0x56a5 перед запуском.
result: [pending]

### 6. Runbook можно выполнить позже без повторного анализа
expected: 03-RUNBOOK.md содержит для L1 (прошивка GuC/HuC) и L2 (i915 -> Xe): проверяемую гипотезу, предпосылки (root, окно перезагрузки, консоль), команды для Fedora 43 с пометкой "untested — verify on first use", подтверждение encode-path через gate против encode_path_baseline_i915.txt (с оговоркой, что baseline валиден только для A380), процедуру измерения со стоковым 8.31 и md5-оракулом, откат и аварийный откат. Текст понятен и достаточен, чтобы стартовать без чтения истории проекта.
result: [pending]

### 7. Требование DIAG-01 закрыто в трассировке
expected: В .planning/REQUIREMENTS.md строка DIAG-01 отмечена [x] со статусом Complete и ссылается на 03-EVIDENCE.md и 03-RUNBOOK.md; в ROADMAP.md фаза 3 отмечена завершённой 2026-10-24.
result: [pending]

## Summary

total: 7
passed: 3
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps

[none yet]
