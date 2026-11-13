{{flutter_js}}
{{flutter_build_config}}

// This build's id: a hash of the build output that `flutter build web` fills in.
// A new deploy has a new id, which is how the page notices it is out of date.
var NAVIVIBE_BUILD = '{{flutter_service_worker_version}}';

// The app (lib/widgets/shell/web_update_prompt.dart) listens for the
// 'navivibe-update' event and shows "New version · Reload"; it calls apply().
window.navivibeBuild = NAVIVIBE_BUILD;
window.navivibeUpdate = { ready: false, apply: function () { window.location.reload(); } };

(function () {
  var registration = null;

  function announce() {
    if (window.navivibeUpdate.ready) return;
    window.navivibeUpdate.ready = true;
    window.dispatchEvent(new Event('navivibe-update'));
  }

  // App-shell cache for offline start and Android "Install app" (see sw.js).
  // The build id in the URL makes every deploy a new worker with its own cache.
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('sw.js?v=' + NAVIVIBE_BUILD).then(function (r) {
        registration = r;
      }).catch(function (e) {
        console.warn('NaviVibe service worker not registered', e);
      });
    });
  }

  // Asks the server which build is live. Works with or without a service
  // worker: flutter_bootstrap.js is fetched past every cache.
  var lastCheck = 0;
  function check() {
    var now = Date.now();
    if (now - lastCheck < 60 * 1000) return;
    lastCheck = now;
    if (registration) registration.update().catch(function () {});
    fetch('flutter_bootstrap.js', { cache: 'no-store' }).then(function (res) {
      return res.ok ? res.text() : '';
    }).then(function (text) {
      var m = text.match(/NAVIVIBE_BUILD = '([^']*)'/);
      if (m && m[1] && m[1] !== NAVIVIBE_BUILD) announce();
    }).catch(function () {});
  }

  window.addEventListener('load', function () { setTimeout(check, 15 * 1000); });
  window.addEventListener('focus', check);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') check();
  });
  setInterval(check, 30 * 60 * 1000);
})();

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
