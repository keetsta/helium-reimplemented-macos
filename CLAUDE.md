# Helium Reimplemented — macOS packaging (рабочий брифинг)

Это **личный форк** (владелец — keetsta). Репо отвечает за **macOS-упаковку**: тянет
кросс-платформенный core (`helium-chromium`, submodule), качает Chromium, накладывает
патчи и собирает подписанный `.dmg`. Core и три фичи (zoom bubble, sync, send-to-device)
описаны в `helium-chromium/CLAUDE.md` — здесь только macOS-специфика.

## Раскладка

Контейнерный toolchain (свой python venv, ninja, greadlink) живёт **рядом** с репо, не в нём:

```
<root>/
  helium-reimplemented-macos/   ← этот репо, тут лежат fork-* скрипты
  toolchain/                    ← env.fork.sh + venv/bin + bin (НЕ в git)
  helium-reimplemented-macos/build/   ← src, download_cache, out/ (git-ignored)
```

`fork-build`/`fork-rebuild` сорсят `../toolchain/env.fork.sh`, который задаёт
`FORK_ROOT`/`FORK_REPO`/PATH. При переносе скриптов держать эту раскладку (репо и
toolchain — соседи).

## Скрипты (все в корне репо)

- **`fork-build [arch]`** — полная чистая RELEASE-сборка (download → patches → PGO →
  sign → `.dmg`). Часы. **Сам пишет маркер** `build/.fork-sync-marker` сразу после
  наложения патчей — это единственный честный источник маркера.
- **`fork-rebuild`** — инкрементально (`ninja chrome chromedriver`) + перепаковка. Минуты.
  НЕ перепатчивает дерево.
- **`fork-sync [-r|--rebuild] [-n|--dry-run] [--no-pull]`** — pull core/platform и занос
  **только дельты патчей** в `build/src`. `-r` — затем `fork-rebuild`. `-n` — превью через
  read-only `git fetch` (показывает входящее, дерево не трогает). При небезопасной дельте
  (рискованные не-патчевые изменения: `deps.ini`, `*.list`, `*.gn`, ресурсы, `series`; либо
  патч не лёг чисто) — отказ с советом `fork-build`. Ручного `--init` НЕТ (был футган: маркер
  врал → no-op).
- **`fork-wipe-profile [-y] [-n]`** — сносит данные ТОЛЬКО форка
  (`~/Library/Application Support/net.imput.helium.reimplemented` + Caches/SavedState/
  HTTPStorages/WebKit/Preferences). Стоковый `net.imput.helium` не трогает (хард-гард по
  `*reimplemented*`). Отказывается при запущенном форке (кроме `-n`).

Цикл: первый раз `./fork-build`; после пуша core с другой машины `./fork-sync -r`; тест
онбординга — закрыть форк, `./fork-wipe-profile -y`, запустить `.app`.

## macOS-специфика (проверено)

- **Идентификаторы форка = `net.imput.helium.reimplemented`** (product_dir_name в
  `patches/helium/macos/change-product-dir-name.patch`, `MAC_BUNDLE_ID` в core
  `change-chromium-branding.patch`). Ставится **рядом** со стоковым Helium
  (`net.imput.helium`), не поверх. `MAC_BUNDLE_ID` — поле только macOS, Windows-ветку не
  задевает.
- **Онбординг** (`components/helium_onboarding`) собирается vite через GN-экшен; во `inputs`
  объявлен каталог `src` → `fork-rebuild`/`--dev` НЕ замечают правок Svelte/строк внутри src.
  Чтобы пересобрать онбординг: полный `fork-build` ИЛИ `touch
  build/src/components/helium_onboarding/vite.config.ts` + `fork-rebuild`. Список браузеров
  для импорта онбординг получает **динамически от бэкенда** → правки C++-импортёра видны после
  обычного `fork-rebuild` без пересборки бандла.
- **`src/lib/strings.ts` генерится** из `helium_onboarding_strings.grdp` скриптом
  `util/generate-i18n.mts` (prebuild). `build.sh` генерит его **до** наложения патчей
  (шаг с bundled host node, arch-независимый выбор) — иначе патчи на `strings.ts` вешают
  `patch` на «File to patch:».
- **Импорт из стокового Helium**: на macOS профиль в `~/Library/Application Support/
  net.imput.helium` (НЕ `Helium`) — путь в `chrome_importer_utils_mac.mm`
  (`GetHeliumUserDataFolder`). Бэкенд детекта зовётся на macOS (`DetectChromeProfiles` в
  `importer_list.cc`).
- **Тосты/строки**: новые `IDS_*` для тостов идут в `chrome/app/generated_resources.grd`
  (определение `<message>`), иначе компиляция падает «use of undeclared identifier».

## Двухуровневый git

Core — submodule `helium-chromium` (форк `keetsta/helium-reimplemented`, detached HEAD на
запиненном коммите). Правки патчей core коммить в submodule на ветке `main` и пушить, затем в
этом репо `git add helium-chromium` (бамп указателя) + коммит + пуш. Платформенные патчи — в
`patches/` этого репо.

> Личный форк, не для upstream.
