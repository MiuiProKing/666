# LUMORA X — AI Pro Camera

Независимая версия iOS-приложения камеры по ТЗ LUMORA X. Проект использует публичные API Apple и зафиксированную GPU-зависимость MetalPetal 1.25.2 (MIT).

## Что реализовано

- SwiftUI-интерфейс в стиле AMOLED black с золотыми акцентами;
- запрос доступа к камере и добавлению снимков в медиатеку;
- нативный `AVCaptureVideoPreviewLayer`;
- обнаружение реально доступных фронтальных и задних объективов;
- переключение камеры и выбор объектива;
- тап для фокуса и экспозиции;
- ручная экспокоррекция в диапазоне, который поддерживает устройство;
- режим PRO с реальными ручными ISO, выдержкой и положением фокуса (если поддерживается объективом);
- вспышка Auto/On/Off, если она доступна;
- захват HEVC/JPEG средствами `AVCapturePhotoOutput`;
- локальная GPU-обработка MetalPetal + Core Image и 11 оригинальных пресетов;
- сохранение обработанного снимка и, по выбору, оригинала;
- настройки, сохраняющиеся между запусками;
- обработка состояний разрешений, ошибок и перегрева;
- базовые unit-тесты модели пресетов.

Это рабочая камера и расширенный preset pipeline. Многокадровый HDR, Night Fusion, RAW, histogram, focus peaking, zebra и ML-защита кожи пока не заявляются как готовые без тестов на устройстве.

## Требования

- macOS с Xcode 16 или новее;
- iPhone с iOS 16 или новее (основная цель — iPhone 12+);
- Apple ID / Apple Developer Team для установки на реальный iPhone;
- реальное устройство: камера недоступна в iOS Simulator.

## Запуск в Xcode

1. Откройте `LUMORAX.xcodeproj`; Xcode автоматически получит MetalPetal 1.25.2 через Swift Package Manager.
2. В target **LUMORAX** откройте **Signing & Capabilities**.
3. Выберите вашу Team и при необходимости замените `com.yourname.lumorax` на уникальный Bundle Identifier.
4. Подключите iPhone, выберите его как Run Destination и нажмите Run.
5. При первом запуске разрешите доступ к камере и добавление фото.

## Сборка IPA

После настройки подписи выполните на Mac:

```bash
chmod +x Scripts/build-ipa.sh
DEVELOPMENT_TEAM=XXXXXXXXXX ./Scripts/build-ipa.sh
```

Для автоматической подписи также можно передать уникальный bundle id:

```bash
DEVELOPMENT_TEAM=XXXXXXXXXX \
PRODUCT_BUNDLE_IDENTIFIER=com.example.lumorax \
./Scripts/build-ipa.sh
```

Готовый экспорт появится в `build/export`. Скрипт создаёт `ExportOptions.plist` автоматически. По умолчанию используется `debugging`; для App Store используйте `EXPORT_METHOD=app-store-connect`, для зарегистрированных тестовых устройств — `EXPORT_METHOD=release-testing`.

### Неподписанный IPA через GitHub Actions

Workflow `.github/workflows/build-unsigned-ipa.yml` собирает устройство без подписи на macOS runner и публикует `LUMORAX-unsigned.ipa` как Actions artifact. Он запускается вручную либо при push в ветку `lumorax-build`. Такой IPA необходимо подписать перед установкой.

## Архитектура

- `App` — composition root и зависимости;
- `Camera` — сессия, устройства, фото, фокус, экспозиция;
- `Processing` — локальный Core Image pipeline;
- `Presets` — модель и каталог оригинальных пресетов;
- `Storage` — запись через PhotoKit;
- `Settings` — постоянные настройки;
- `UI` — SwiftUI-экраны и UIKit preview bridge.

## Важные ограничения

Windows не содержит Xcode, iOS SDK и Apple signing toolchain, поэтому проект нельзя скомпилировать или подписать в этой среде. Финальную проверку камеры, ориентации, качества, памяти и нагрева необходимо выполнить на реальном iPhone 12 или новее.

См. также [ROADMAP.md](ROADMAP.md) и [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
