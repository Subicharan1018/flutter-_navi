/// True in the builds published to GitHub Releases (`--dart-define=PUBLIC_BUILD=true`).
///
/// A public build leaves out everything that downloads songs from the web
/// (Search Online, Send a playlist link, Recognize > Download, the download
/// activity ring and banner) and does not pre-fill a sign-in server address.
/// Personal builds (the default, flag off) keep all of it. See docs/RELEASING.md.
const bool kPublicBuild = bool.fromEnvironment('PUBLIC_BUILD');
