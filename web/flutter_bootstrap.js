{{flutter_js}}
{{flutter_build_config}}

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
