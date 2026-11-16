// Song moods come from the shuffle server only: its labeller reads the lyrics
// (first verse + chorus) and the sound, and sends one or two labels per song in
// GET /catalog/songs (`moods`, most fitting first). The app never guesses a
// mood from genre words: a song with no label fits no mood.

/// The labels the server gives, in the order the mood pickers list them.
const moodLabels = ['sad', 'romantic', 'happy', 'energetic', 'calm', 'devotional', 'angry'];

/// What the mood picker offers: the labels plus Flow's sound-based "gym".
const pickableMoods = [...moodLabels, 'gym'];

/// The most moods a song carries.
const maxSongMoods = 2;

/// "Sad", "Gym": how a mood reads on screen.
String moodTitle(String mood) => mood.isEmpty ? mood : mood[0].toUpperCase() + mood.substring(1);

/// A song's labels as this listener sees them: the server's labels without the
/// ones they marked "Not this mood" ([notThese]).
List<String> effectiveMoods(List<String> labels, Set<String>? notThese) =>
    notThese == null || notThese.isEmpty ? labels : [for (final m in labels) if (!notThese.contains(m)) m];
