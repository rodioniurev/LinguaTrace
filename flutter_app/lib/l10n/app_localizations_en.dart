// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tabTranslate => 'Translate';

  @override
  String get tabCorrect => 'Correct';

  @override
  String get tabHistory => 'History';

  @override
  String get tabPatterns => 'Patterns';

  @override
  String get tabSettings => 'Settings';

  @override
  String get copied => 'Copied!';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get tooltipClear => 'Clear';

  @override
  String get tooltipCopy => 'Copy';

  @override
  String get tooltipPaste => 'Paste';

  @override
  String get typeOrSpeak => 'Type or speak...';

  @override
  String get listening => 'Listening...';

  @override
  String get chipIdiom => 'Idiom';

  @override
  String get chipWords => 'Words';

  @override
  String get chipContext => 'Context';

  @override
  String viaProvider(String name) {
    return 'via $name';
  }

  @override
  String get noProverbsFound => 'No proverbs found for this phrase';

  @override
  String idiomsFoundHeader(int count, String lang) {
    return 'Found: $count · language: $lang';
  }

  @override
  String get pickSourceBeforeSwap => 'Pick a source language before swapping';

  @override
  String get culturalContext => 'Cultural context';

  @override
  String contextFailed(String error) {
    return 'Failed to get context: $error';
  }

  @override
  String get addAiKeyHint =>
      'AI is needed. On a computer: Settings → AI assistant → “Claude · subscription”. Free: a compatible service (Gemini, Groq) or Ollama with a model.';

  @override
  String get tooltipStop => 'Stop';

  @override
  String get tooltipDictate =>
      'Tap: dictate at cursor · Long-press: clear & dictate';

  @override
  String get allMeanings => 'All meanings';

  @override
  String get grammar => 'Grammar';

  @override
  String get breakingDown => 'Breaking down...';

  @override
  String get searchingProverbs => 'Searching proverbs...';

  @override
  String literalLabel(String text) {
    return 'literal: $text';
  }

  @override
  String get autoDetect => 'Auto-detect';

  @override
  String get autoMarker => '(auto)';

  @override
  String pluralTag(String plural) {
    return 'pl. $plural';
  }

  @override
  String get etymLabel => 'etym.';

  @override
  String historyTitle(int count) {
    return 'History ($count)';
  }

  @override
  String get searchHint => 'Search...';

  @override
  String get confirmDeletion => 'Confirm deletion';

  @override
  String deleteEntriesQuestion(int count) {
    return 'Delete $count entries?';
  }

  @override
  String deleteEntriesFilteredQuestion(int count, String filter) {
    return 'Delete $count entries ($filter)?';
  }

  @override
  String olderThanDaysDesc(int days) {
    return '>$days days old';
  }

  @override
  String get selectEntries => 'Select entries';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get allLabel => 'All';

  @override
  String get tooltipDeleteSelected => 'Delete selected';

  @override
  String get tooltipDeleteShown => 'Delete shown entries';

  @override
  String get tooltipSelect => 'Select';

  @override
  String olderThanChip(int days) {
    return '>$days d';
  }

  @override
  String get clearFilters => 'Clear';

  @override
  String get noEntriesMatchFilter => 'No entries match the filter';

  @override
  String get noTranslationsYet =>
      'No translations yet.\nUse the Translate tab!';

  @override
  String get patternsTitle => 'Patterns';

  @override
  String get statTotal => 'Total';

  @override
  String get statPairs => 'Pairs';

  @override
  String get statHard => 'Hard';

  @override
  String myMistakes(int count) {
    return 'My mistakes ($count)';
  }

  @override
  String get training => 'Training';

  @override
  String get mistakesHint =>
      'Check your texts in the Correct tab — mistakes will be remembered here and turned into training sessions.';

  @override
  String get wordsLookedUpRepeatedly => 'Words you look up repeatedly';

  @override
  String get noRepeatedPatterns => 'No repeated patterns yet.';

  @override
  String timesCount(int count) {
    return '${count}x';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeMedium => 'Medium';

  @override
  String get themeLight => 'Light';

  @override
  String get themeExtra => 'Extra';

  @override
  String get fontSizeLabel => 'Font size';

  @override
  String get fontPreview => 'Preview: Aa Бб Ññ';

  @override
  String get sectionOfflineTranslation => 'Offline Translation';

  @override
  String get preferOffline => 'Prefer offline translation';

  @override
  String get preferOfflineDesc =>
      'Use on-device engines (ML Kit / local LLM) instead of online APIs.';

  @override
  String get sectionAiAssistant => 'AI assistant (Claude / ChatGPT)';

  @override
  String get aiKeyDesc =>
      'AI checks what you write, explains mistakes and idioms, and builds practice from YOUR data. On a computer the simplest option is your Claude subscription through Claude Code — no API key or extra payment.';

  @override
  String get providerLabel => 'Provider';

  @override
  String get providerAuto => 'Auto (any configured)';

  @override
  String get providerCustom => 'Custom / free';

  @override
  String get customApiHint =>
      'Any OpenAI-compatible service. Free options: Gemini (aistudio.google.com), Groq (console.groq.com), OpenRouter (models tagged “:free”), or a local LM Studio / llama.cpp server.';

  @override
  String get customBaseUrlLabel => 'API base URL (without /chat/completions)';

  @override
  String get customModelLabel => 'Model name';

  @override
  String get customKeyLabel => 'API key (leave empty for a local server)';

  @override
  String get presetLabel => 'Presets';

  @override
  String get freeLocalHintTitle => 'Free and local';

  @override
  String get freeLocalHintBody =>
      'Ollama needs no keys and has no limits. Install it from ollama.com, run “ollama pull qwen2.5:3b”, then turn on the switch below — Correct, Context and Training all work for free.';

  @override
  String get ollamaTitle => 'Ollama — local and free';

  @override
  String get ollamaDesc =>
      'Your own model on this computer: no keys, no limits, no text leaving the machine.';

  @override
  String get ollamaUrlLabel => 'Ollama address';

  @override
  String get ollamaModelLabel => 'Model';

  @override
  String get ollamaCheck => 'Test connection';

  @override
  String get ollamaChecking => 'Checking…';

  @override
  String ollamaOk(String models) {
    return 'Ollama responds. Available models: $models';
  }

  @override
  String ollamaNoModels(String model) {
    return 'Ollama responds but has no models. Run: ollama pull $model';
  }

  @override
  String ollamaModelMissing(String model) {
    return 'Model “$model” is not installed. Run: ollama pull $model';
  }

  @override
  String ollamaUnreachable(String url) {
    return 'Ollama is not responding at $url. Start the Ollama app and retry.';
  }

  @override
  String providerKeyMissing(String provider) {
    return 'No API key for “$provider” — enter it below or pick another provider';
  }

  @override
  String get anthropicKeyLabel => 'Anthropic API key (Claude)';

  @override
  String get openaiKeyLabel => 'OpenAI API key (ChatGPT)';

  @override
  String get sectionOnlineTranslators => 'Online Translators';

  @override
  String get preferredLabel => 'Preferred';

  @override
  String get googleFreeDesc => 'Free, no key needed';

  @override
  String get apiKeyLabel => 'API Key';

  @override
  String get sectionAbout => 'About';

  @override
  String get mlkitModelsTitle => 'ML Kit offline models';

  @override
  String get mlkitOnlyMobile =>
      'Only available on Android/iOS. On desktop use the on-device LLM below.';

  @override
  String get mlkitModelsSize => 'ML Kit offline models (~30 MB each)';

  @override
  String get modelDownloadedOffline => 'Downloaded — works offline';

  @override
  String get modelNotDownloaded => 'Not downloaded';

  @override
  String get deleteModel => 'Delete model';

  @override
  String get downloadModel => 'Download model';

  @override
  String downloadFailedWithError(String error) {
    return 'Download failed: $error';
  }

  @override
  String deleteFailedWithError(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get onDeviceLlmTitle => 'On-device LLM (Gemma / Qwen)';

  @override
  String llmInstalledReady(String name) {
    return '$name — installed, ready';
  }

  @override
  String get llmDownloadDesc => '~500 MB – 1.6 GB download, runs fully offline';

  @override
  String downloadingPercent(String percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get modelTokenButton => 'Model / token';

  @override
  String get modelUrlLabel => 'Model URL (.task / .litertlm)';

  @override
  String get hfTokenLabel => 'HuggingFace token (gated models)';

  @override
  String get saveUrlToken => 'Save URL / token';

  @override
  String get modelSettingsSaved => 'Model settings saved';

  @override
  String get modelInstalled => 'Model installed';

  @override
  String get modelDownloadFailed => 'Download failed';

  @override
  String get modelGatedHint =>
      'This model is license-gated on Hugging Face (HTTP 401). Paste an HF token under “Model / token” (after accepting the license on the model page) or keep the open default model (Qwen2.5).';

  @override
  String get deleteOnDeviceModelQuestion => 'Delete on-device model?';

  @override
  String get deleteOnDeviceModelDesc =>
      'This frees disk space but the next on-device translation will need to download the model again.';

  @override
  String get polishTitle => 'Polish';

  @override
  String get detailsButton => 'Explain in depth';

  @override
  String get detailsLoading => 'Preparing the breakdown…';

  @override
  String get detailsTitle => 'Breakdown: rules, examples, word history';

  @override
  String mistakesRecorded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mistakes recorded — they will feed your training',
      one: '$count mistake recorded — it will feed your training',
    );
    return '$_temp0';
  }

  @override
  String get toTraining => 'Go to training';

  @override
  String dueForReview(int count) {
    return 'Due for review today: $count';
  }

  @override
  String get nothingDue =>
      'Nothing due today — a new session will pick up fresh mistakes';

  @override
  String get repetitionExplained =>
      'Covered mistakes come back for review after 1, 3, 7, 21 and 60 days.';

  @override
  String get noBackendHint =>
      'Writing correction needs an AI: on a computer pick “Claude · subscription” in Settings → AI assistant; on a phone add a Claude API key or a free compatible service.';

  @override
  String writeSomethingIn(String lang) {
    return 'Write something in $lang…';
  }

  @override
  String get checking => 'Checking…';

  @override
  String get checkButton => 'Check';

  @override
  String get looksPerfect => 'Looks perfect!';

  @override
  String fixesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fixes',
      one: '1 fix',
    );
    return '$_temp0';
  }

  @override
  String get catGrammar => 'grammar';

  @override
  String get catWord => 'word';

  @override
  String get catArticle => 'article';

  @override
  String get catSpelling => 'spelling';

  @override
  String get catPunctuation => 'punct.';

  @override
  String get catStyle => 'style';

  @override
  String get generating => 'Generating…';

  @override
  String get newTrainingFromMistakes => 'New training from my mistakes';

  @override
  String get noTrainingsYet =>
      'No trainings yet.\n\nCheck your texts in the Correct tab — mistakes are remembered, and a personal course is built from them: rule explanations, exercises and texts tailored to your weak spots.';

  @override
  String get saveToNotebook => 'To notebook';

  @override
  String get savedToNotebook => 'In notebook';

  @override
  String savedToNotebookSnack(String text) {
    return 'Added to your notebook: $text';
  }

  @override
  String ownTextCheckTitle(String lang) {
    return 'Your $lang';
  }

  @override
  String get ownTextChecking => 'Checking what you wrote…';

  @override
  String get ownTextPerfect => 'Written correctly';

  @override
  String ownTextFixes(int count) {
    return 'Fixes: $count';
  }

  @override
  String get notAnError => 'Not a mistake';

  @override
  String get markedNotError => 'Removed from your mistakes';

  @override
  String get upgradeLabel => 'could be more natural';

  @override
  String get notRecordedLocal =>
      'Not recorded as mistakes: small local models are often wrong.';

  @override
  String get sectionLearning => 'What I\'m developing';

  @override
  String get learningLangLabel => 'Language I\'m developing';

  @override
  String autoCheckLabel(String lang) {
    return 'Check my $lang automatically';
  }

  @override
  String get autoCheckDesc =>
      'Whatever you type in this language on the Translate screen is checked in the background; real mistakes go to your notebook.';

  @override
  String get providerClaudeCode => 'Claude · subscription (Claude Code)';

  @override
  String get providerClaudeApi => 'Claude · API key';

  @override
  String get claudeModelLabel => 'Claude model';

  @override
  String get claudeCodeTitle => 'Claude Code on this computer';

  @override
  String claudeCodeReady(String version, String plan) {
    return 'Installed $version · signed in ($plan)';
  }

  @override
  String get claudeCodeChecking => 'Checking Claude Code…';

  @override
  String get refresh => 'Refresh';

  @override
  String get checkConnection => 'Test connection';

  @override
  String get checkingConnection => 'Testing…';

  @override
  String connectionOk(String backend, String seconds) {
    return 'Works: $backend · $seconds s';
  }

  @override
  String aiUsageMonth(int count, int ok, String cost) {
    return 'This month: $count AI requests ($ok successful), pay-per-use ≈ \$$cost';
  }

  @override
  String get sectionDiagnostics => 'Data and diagnostics';

  @override
  String get dataFolderLabel => 'Data folder';

  @override
  String get settingsFileLabel => 'Settings file';

  @override
  String get openFolder => 'Open folder';

  @override
  String settingsSaveFailed(String error) {
    return 'Settings were NOT saved: $error';
  }

  @override
  String importedLegacy(int files, int rows) {
    return 'History from older versions merged: $files file(s), $rows records';
  }

  @override
  String get notebookTitle => 'Notebook';

  @override
  String notebookCounts(int expressions, int mistakes) {
    return '$expressions words and expressions · $mistakes mistakes to work on';
  }

  @override
  String get notebookEmpty =>
      'Empty so far. Tap “To notebook” next to words and proverbs, and write in the language you are developing — mistakes will be added by themselves.';

  @override
  String get topConstructions => 'My problem constructions';

  @override
  String get removeFromNotebook => 'Remove from notebook';

  @override
  String get aiNeededTitle => 'AI is not set up';

  @override
  String get trainingDone => 'I\'ve done this session';

  @override
  String get trainingDoneMarked =>
      'Done — these mistakes come back on schedule (1 → 3 → 7 → 21 → 60 days).';

  @override
  String get removeWordLabel => '(remove)';

  @override
  String get tabFeed => 'Feed';

  @override
  String get feedTitle => 'Feed';

  @override
  String feedToday(int count, int due) {
    return 'Today: $count stories · $due due for review';
  }

  @override
  String get feedBuildMore => 'More stories';

  @override
  String get feedBuilding => 'Writing today\'s edition…';

  @override
  String get feedEmpty =>
      'Your feed is empty. It is written from today\'s real news and uses YOUR mistakes and the expressions you are taking into use.';

  @override
  String get feedBuildToday => 'Write today\'s edition';

  @override
  String feedFailedItems(int count) {
    return '$count stories were dropped: the model failed the fact or target checks.';
  }

  @override
  String feedOpenOriginal(String outlet) {
    return 'Source: $outlet — open the original';
  }

  @override
  String get tasksTitle => 'PRACTICE';

  @override
  String yourMistakeShort(String wrong, String right) {
    return 'you wrote «$wrong» → «$right»';
  }

  @override
  String yourMistake(String wrong, String right) {
    return 'You wrote: «$wrong» → correct: «$right»';
  }

  @override
  String get gotIt => 'Got it';

  @override
  String get taskCorrect => 'Correct!';

  @override
  String taskAccents(String answer) {
    return 'Correct — mind the accents: $answer';
  }

  @override
  String taskWrong(String answer) {
    return 'Answer: $answer';
  }

  @override
  String get taskPlaceholder => 'Write in Spanish…';

  @override
  String get taskCheck => 'Check';

  @override
  String get taskTargetMissing =>
      'The target expression wasn\'t used — try to include it next time.';

  @override
  String taskModelAnswer(String answer) {
    return 'Model answer: $answer';
  }

  @override
  String get journalTitle => 'Journal';

  @override
  String get taskPending =>
      'Saved. It will be checked when an AI is available — e.g. on your computer after the next exchange.';

  @override
  String get taskChecked => 'Checked.';

  @override
  String get sectionExchange => 'Exchange between devices';

  @override
  String get exchangeDesc =>
      'Everything you accumulate — history, notebook, mistakes, trainings and feed editions with your answers — is kept in one exchange file per device and merged on the other one. Editions written on the computer with your Claude subscription can be read and practised on the phone; answers come back.';

  @override
  String get exchangeFolderLabel => 'Exchange folder (one file per device)';

  @override
  String get exchangeUseOneDrive => 'Use OneDrive';

  @override
  String get exchangeSyncNow => 'Sync now';

  @override
  String get exchangeSyncing => 'Syncing…';

  @override
  String get exchangeShare => 'Send exchange file';

  @override
  String get exchangeLoad => 'Load exchange file';

  @override
  String exchangeReport(
      int items, int mistakes, int feed, int tasks, int history) {
    return 'Merged: $items notebook items, $mistakes mistakes, $feed stories, $tasks answers, $history history records.';
  }

  @override
  String get exchangeNothingNew =>
      'Nothing new to merge. Your file is updated.';

  @override
  String exchangeGraded(int count) {
    return 'Checked answers from the other device: $count';
  }

  @override
  String get exchangePhoneHint =>
      'On the computer: save the file into its exchange folder (e.g. OneDrive\\LinguaTrace). Here: load the computer\'s file linguatrace-windows-….json.';

  @override
  String get feedPhoneHint =>
      'Editions are written on the computer (Claude subscription). Load its exchange file: Settings → Exchange.';

  @override
  String get feedGlossAfterTask =>
      'Explanations of the marked words appear after you answer the task below.';

  @override
  String feedCannotOpen(String url) {
    return 'Could not open $url';
  }

  @override
  String exchangeErrors(String errors) {
    return 'Not everything was merged: $errors';
  }

  @override
  String get exchangeFullHistory => 'Include the full translation history';

  @override
  String get exchangeFullHistoryHint =>
      'By default the file carries the notebook, mistakes, the feed and short lookups; long texts (letters) stay on this device. The file is plain text (JSON) — keep it in your own folders.';

  @override
  String exchangeTooLarge(int mb) {
    return 'This file is too large for an exchange file ($mb MB).';
  }

  @override
  String claudeCodeTokenInUse(String version) {
    return 'Installed $version · using the subscription token';
  }

  @override
  String get claudeCodeLogin => 'Sign in to Claude Code';

  @override
  String get claudeCodeSetupToken => 'Create a subscription token (1 year)';

  @override
  String get claudeCodeTokenLabel => 'Subscription token (optional)';

  @override
  String get claudeCodeTokenHelp =>
      'From `claude setup-token`: valid for a year, no repeated sign-in. Not an API key: it uses your subscription limits, no extra charge. Stored in settings.json on this computer.';

  @override
  String get claudeCodeConsoleLogin1 =>
      'Sign in to Claude Code with the account that has the subscription.';

  @override
  String get claudeCodeConsoleLogin2 =>
      'A browser opens: sign in and allow access. Then close this window and return to LinguaTrace.';

  @override
  String get claudeCodeConsoleToken1 =>
      'A one-year subscription token for LinguaTrace (not an API key, no extra charge).';

  @override
  String get claudeCodeConsoleToken2 =>
      'A browser opens: sign in. Then copy the line sk-ant-oat01-... and paste it into LinguaTrace: Settings - AI - Subscription token.';

  @override
  String get providerPcRelay => 'Claude via your computer (subscription)';

  @override
  String get relayClientDesc =>
      'The phone sends requests to LinguaTrace on your computer, which asks Claude on your subscription. No keys, no extra charge. On the PC: Settings - AI assistant - «Claude for the phone» shows the address and code.';

  @override
  String get relayAddressLabel => 'Computer address';

  @override
  String get relayCodeLabel => 'Pairing code';

  @override
  String get relayServerTitle => 'Claude for the phone';

  @override
  String get relayServerDesc =>
      'The phone can use this computer\'s Claude (your subscription, no extra charge) while LinguaTrace is running.';

  @override
  String get relayServerRunning =>
      'Running. On the phone enter the address and the code:';

  @override
  String get relayNoNetwork =>
      'No network — connect the computer to Wi-Fi or a local network.';

  @override
  String get relayNewCode => 'New code';

  @override
  String get relayServerHint =>
      'The phone and the computer must be on the same Wi-Fi. Away from home: install Tailscale on both and use the computer\'s 100.x.x.x address. The first time, Windows asks for network access — allow it for private networks.';

  @override
  String get fastModelLabel => 'Model for quick answers';

  @override
  String get fastModelHint =>
      'Text check, hints, word choice, origins. The main model above writes the feed and trainings.';

  @override
  String get claudeWarmLabel => 'Keep Claude ready';

  @override
  String get claudeWarmHint =>
      'Answers in 1–3 s instead of ~10 s: Claude Code stays running (≈150–250 MB of memory).';

  @override
  String get startupTimesLabel => 'Startup time';

  @override
  String get copy => 'Copy';

  @override
  String get askClaudeApp => 'Ask in the Claude app';

  @override
  String get chipChoice => 'Word choice';

  @override
  String get chipOrigin => 'Origin';

  @override
  String get chosenTranslation => 'Claude · chosen';

  @override
  String etymologyAskPrompt(String term, String lang) {
    return 'Tell me the origin of «$term» ($lang): its path from Latin and other languages, why it is named so, related words in Spanish, Russian and English, the history of the expression. Briefly.';
  }

  @override
  String get etymologyRebuild => 'Write again';

  @override
  String get etymologyWriting => 'Claude is writing the page…';

  @override
  String get etymologyPhoneHint =>
      'Origin pages are written by Claude. Turn on «Claude via your computer» (Settings - AI assistant) or load the exchange file — it carries the pages written on the computer.';

  @override
  String etymologyCertainty(String certainty) {
    String _temp0 = intl.Intl.selectLogic(
      certainty,
      {
        'documented': 'documented',
        'probable': 'probable',
        'disputed': 'disputed',
        'folk': 'folk story',
        'other': '?',
      },
    );
    return '$_temp0';
  }

  @override
  String get etymologyChain => 'The word\'s path';

  @override
  String get etymologyWhy => 'Why it is named so';

  @override
  String get etymologyIdiomStory => 'Where the expression comes from';

  @override
  String get etymologyHistory => 'History';

  @override
  String get etymologyRelatives => 'Related words';

  @override
  String get etymologyFalseFriends => 'False friends';

  @override
  String get etymologyMnemonic => 'Remember';

  @override
  String get etymologySources => 'Source';

  @override
  String get etymologyNoSources =>
      'No dictionary entry — from general knowledge';

  @override
  String wordChoiceAskPrompt(String source, String translation, String focus) {
    return 'I am translating into Spanish: «$source». Machine translation: «$translation». I do not like the word: $focus. Suggest options with their nuances and rewrite the sentence with each.';
  }

  @override
  String get wordChoiceTitle => 'Word choice';

  @override
  String get wordChoiceNow => 'Current translation:';

  @override
  String get wordChoicePick =>
      'Which word should be better? Tap it — or pick none for the whole sentence.';

  @override
  String get wordChoiceHintLabel => 'What you want to say (optional)';

  @override
  String get wordChoiceHintExample =>
      'e.g. to contribute, not to bring a thing';

  @override
  String get wordChoiceRunSentence => 'Find options';

  @override
  String wordChoiceRunWord(String word) {
    return 'Options for «$word»';
  }

  @override
  String get wordChoiceNoAiDesktop =>
      'Without AI these are dictionary options. Connect Claude in Settings for explanations and ready sentences.';

  @override
  String get wordChoiceNoAiPhone =>
      'Without AI these are dictionary options. Turn on «Claude via your computer» in Settings for explanations and ready sentences.';

  @override
  String get wordChoiceUse => 'Use';

  @override
  String get wordChoiceDictionaryNote =>
      'Dictionary options: the back-translation next to each shows its sense.';

  @override
  String wordChoiceFit(String fit) {
    String _temp0 = intl.Intl.selectLogic(
      fit,
      {
        'best': 'best',
        'good': 'fits',
        'possible': 'possible',
        'wrong': 'not this',
        'other': '',
      },
    );
    return '$_temp0';
  }

  @override
  String get wordChoiceOrigin => 'Origin?';

  @override
  String get tabIdeas => 'Ideas';

  @override
  String get ideasTitle => 'Ideas';

  @override
  String get ideasEmpty =>
      'Thoughts for articles and inventions gather here. Create a project and describe its context — then just dictate on the go. In the background I add punctuation, search the web for what is already known, and assemble a draft.';

  @override
  String get ideasNewProject => 'New project';

  @override
  String get ideasDictate => 'Dictate';

  @override
  String get ideasProjectTitleLabel => 'Title';

  @override
  String get ideasContextLabel =>
      'Context: what it is about, for whom, what matters';

  @override
  String get ideasKindArticle => 'Article';

  @override
  String get ideasKindInvention => 'Invention';

  @override
  String get ideasKindOther => 'Other';

  @override
  String get ideasCreate => 'Create';

  @override
  String ideasCounts(int notes, int sources) {
    return 'thoughts: $notes · sources: $sources';
  }

  @override
  String get ideasContext => 'Context';

  @override
  String get ideasEditContext => 'Edit project';

  @override
  String get ideasSources => 'Sources';

  @override
  String get ideasAddSource => 'Add';

  @override
  String get ideasAddText => 'Paste text';

  @override
  String get ideasAddUrl => 'Link to an article';

  @override
  String get ideasAddFile => 'File (txt, md, html, pdf)';

  @override
  String get ideasUrlLabel => 'Page address';

  @override
  String get ideasTextLabel => 'Text';

  @override
  String get ideasAdding => 'Loading…';

  @override
  String get ideasSourceText => 'Text';

  @override
  String get ideasFound => 'Found by search';

  @override
  String get ideasNotes => 'Thoughts';

  @override
  String get ideasNoNotes => 'No thoughts yet — tap «Dictate».';

  @override
  String get ideasStatusQueued => 'queued';

  @override
  String get ideasStatusWorking => 'searching and analysing…';

  @override
  String get ideasStatusOffline => 'waiting for AI';

  @override
  String get ideasStatusFailed => 'failed';

  @override
  String get ideasRetry => 'Analyse again';

  @override
  String get ideasInsight => 'Analysis';

  @override
  String get ideasWithWeb => 'with search';

  @override
  String get ideasDraft => 'Assemble a draft';

  @override
  String get ideasDrafting => 'Assembling the draft…';

  @override
  String get ideasDraftLabel => 'Draft';

  @override
  String get ideasShare => 'Share (Markdown)';

  @override
  String get ideasDelete => 'Delete project';

  @override
  String ideasDeleteConfirm(String title) {
    return 'Delete «$title» with all its thoughts and sources?';
  }

  @override
  String get ideasRaw => 'Original dictation';

  @override
  String get ideasNoAi =>
      'Without AI thoughts are only saved. Claude adds punctuation, searches and analyses: connect it (Settings - AI assistant) or sync with your computer.';

  @override
  String get ideasWebLabel => 'Search the web for ideas';

  @override
  String get ideasWebHint =>
      'Claude looks for prior art, facts and sources for each thought. With an API key: up to 5 searches per thought, \$10 per 1,000 searches.';

  @override
  String get dictationListening => 'Listening';

  @override
  String get dictationPaused => 'Paused';

  @override
  String get dictationNewNote => 'New thought';

  @override
  String get dictationStop => 'Stop';

  @override
  String get dictationResume => 'Continue';

  @override
  String get dictationHint =>
      'Speak freely, pauses are fine. «New thought» starts the next one, «what do you think?» — Claude answers and asks, «stop recording» ends. You can turn the screen off.';

  @override
  String dictationSaved(int n) {
    return 'thoughts saved: $n';
  }

  @override
  String get dictationNoVoice =>
      'No speech recognition on this device — type the thought.';

  @override
  String dictationError(String error) {
    return 'Recognition stopped ($error). Tap «Continue».';
  }

  @override
  String get dictationTypeHint => 'Thought';

  @override
  String get dictationSave => 'Save';

  @override
  String get anthropicKeyHelp =>
      'Create a key at console.anthropic.com → API keys. API requests are billed separately from a claude.ai subscription. With a key Claude works on the phone too — no PC needed.';

  @override
  String dictationReconnecting(String reason) {
    return 'Reconnecting recognition: $reason';
  }

  @override
  String get dictationTroubleNet => 'no connection';

  @override
  String get dictationTroubleMic => 'the microphone is busy';

  @override
  String get dictationTroubleBackground =>
      'Android gives no microphone in the background — turn the screen on';

  @override
  String get dictationTroubleBusy => 'the recogniser is busy';

  @override
  String get dictationErrPermission =>
      'no microphone access — allow it for LinguaTrace in the phone settings';

  @override
  String get dictationErrLanguage =>
      'this language is not recognised on the phone — add it in Google voice typing settings';

  @override
  String get dictationErrInit =>
      'speech recognition unavailable — check microphone access and Google voice typing';

  @override
  String get dictationErrNoRecognizer =>
      'the phone has no speech recognition service (the Google app is needed)';

  @override
  String get dictationMuteBeeps => 'No beeps: mute media sound while recording';

  @override
  String get dictationLog => 'Recognition log';

  @override
  String get dictationLogHint =>
      'If dictation misbehaves, copy the log and send it.';

  @override
  String get dictationLogEmpty => 'The log is empty.';

  @override
  String get dictationCopy => 'Copy';

  @override
  String get dictationCopied => 'Copied';

  @override
  String get syncServerTitle => 'Sync server';

  @override
  String get syncServerHint =>
      'Your own server where every device\'s data comes together (the program in the project\'s server folder). The phone and computers exchange through it by themselves: at start, every 10 minutes and after dictation.';

  @override
  String get syncServerUrlLabel => 'Server address';

  @override
  String get syncServerKeyLabel => 'Access key';

  @override
  String get syncServerNow => 'Sync with the server';

  @override
  String get syncServerSent => 'This device\'s data was sent to the server.';

  @override
  String get dictationDiscuss => 'Discuss';

  @override
  String get dictationThinking => 'Claude is thinking…';

  @override
  String get dictationSpeaking => 'Claude is speaking…';

  @override
  String get dictationStopSpeaking => 'Interrupt';

  @override
  String get dictationBluetooth => 'Bluetooth headset microphone';

  @override
  String dictationDiscussFailed(String error) {
    return 'Claude did not answer: $error';
  }

  @override
  String get ideasClaude => 'Claude';
}
