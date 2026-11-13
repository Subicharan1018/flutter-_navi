{{flutter_js}}
{{flutter_build_config}}

// App-shell cache for offline start and Android "Install app" (see sw.js).
if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').catch(function (e) {
      console.warn('NaviVibe service worker not registered', e);
    });
  });
}

// NaviVibe registers its own service worker (sw.js, from index.html), so
// Flutter's deprecated one is not passed here: two workers on one scope would
// replace each other on every load.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    const splash = document.getElementById('nv-splash');
    if (splash) {
      splash.style.opacity = '0';
      setTimeout(function () { splash.remove(); }, 300);
    }
  },
});
