LUCKYJET EXACT — ПРОЕКТ ПРИЛОЖЕНИЯ ДЛЯ IPHONE
================================================

В папку www/index.html уже помещён исходный HTML.
API разрешает origin capacitor://localhost, поэтому сетевые запросы приложения
совместимы с этой оболочкой.

СБОРКА UNSIGNED IPA
-------------------
Файл .github/workflows/build-unsigned-ipa.yml собирает на macOS готовый
LuckyJetExact-unsigned.ipa без подписи. Такой IPA можно переподписать через
KSign, Scarlet, AltStore или Sideloadly. Workflow запускается автоматически
после push в GitHub либо вручную через Actions > Build unsigned IPA.

КАК ПОЛУЧИТЬ IPA НА MAC
-----------------------
1. Установите Xcode и Node.js.
2. Откройте Terminal в этой папке.
3. Выполните:

   chmod +x build-ipa-on-mac.sh
   ./build-ipa-on-mac.sh

4. В Xcode откройте Signing & Capabilities и выберите свой Team.
5. Выберите реальное устройство или Any iOS Device (arm64).
6. Нажмите Product > Archive.
7. В Organizer нажмите Distribute App и выберите подходящий способ:
   Development / Ad Hoc / TestFlight / App Store Connect.

Для установки только на свой iPhone можно использовать бесплатный Apple ID в
Xcode. Такая установка обычно требует периодического обновления подписи.

ОБНОВЛЕНИЕ HTML
---------------
Замените www/index.html, затем выполните:

   npm ci
   npx cap sync ios

После этого снова соберите Archive в Xcode.

ВАЖНО
-----
В HTML находятся customer-id и session-id API. Если сервер изменит или отзовёт
их, приложение перестанет получать данные; это не связано с IPA-оболочкой.
