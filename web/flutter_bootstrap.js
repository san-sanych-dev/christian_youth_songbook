// Кастомный загрузчик Flutter Web.
// Намеренно НЕ передаём serviceWorkerSettings в _flutter.loader.load(),
// чтобы Flutter не регистрировал свой устаревший саморазрегистрирующийся
// flutter_service_worker.js. Вместо него регистрируем собственный sw.js,
// который кэширует оболочку приложения и обеспечивает офлайн-режим и
// устанавливаемость PWA.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
  },
});

if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').catch(function (err) {
      console.warn('Service worker registration failed:', err);
    });
  });
}
