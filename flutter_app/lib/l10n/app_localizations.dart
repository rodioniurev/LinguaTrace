import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru')
  ];

  /// No description provided for @tabTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get tabTranslate;

  /// No description provided for @tabCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get tabCorrect;

  /// No description provided for @tabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get tabHistory;

  /// No description provided for @tabPatterns.
  ///
  /// In en, this message translates to:
  /// **'Patterns'**
  String get tabPatterns;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get copied;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @tooltipClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get tooltipClear;

  /// No description provided for @tooltipCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get tooltipCopy;

  /// No description provided for @tooltipPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get tooltipPaste;

  /// No description provided for @typeOrSpeak.
  ///
  /// In en, this message translates to:
  /// **'Type or speak...'**
  String get typeOrSpeak;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get listening;

  /// No description provided for @chipIdiom.
  ///
  /// In en, this message translates to:
  /// **'Idiom'**
  String get chipIdiom;

  /// No description provided for @chipWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get chipWords;

  /// No description provided for @chipContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get chipContext;

  /// No description provided for @viaProvider.
  ///
  /// In en, this message translates to:
  /// **'via {name}'**
  String viaProvider(String name);

  /// No description provided for @noProverbsFound.
  ///
  /// In en, this message translates to:
  /// **'No proverbs found for this phrase'**
  String get noProverbsFound;

  /// No description provided for @idiomsFoundHeader.
  ///
  /// In en, this message translates to:
  /// **'Found: {count} · language: {lang}'**
  String idiomsFoundHeader(int count, String lang);

  /// No description provided for @pickSourceBeforeSwap.
  ///
  /// In en, this message translates to:
  /// **'Pick a source language before swapping'**
  String get pickSourceBeforeSwap;

  /// No description provided for @culturalContext.
  ///
  /// In en, this message translates to:
  /// **'Cultural context'**
  String get culturalContext;

  /// No description provided for @contextFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to get context: {error}'**
  String contextFailed(String error);

  /// No description provided for @addAiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'AI is needed. On a computer: Settings → AI assistant → “Claude · subscription”. Free: a compatible service (Gemini, Groq) or Ollama with a model.'**
  String get addAiKeyHint;

  /// No description provided for @tooltipStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get tooltipStop;

  /// No description provided for @tooltipDictate.
  ///
  /// In en, this message translates to:
  /// **'Tap: dictate at cursor · Long-press: clear & dictate'**
  String get tooltipDictate;

  /// No description provided for @allMeanings.
  ///
  /// In en, this message translates to:
  /// **'All meanings'**
  String get allMeanings;

  /// No description provided for @grammar.
  ///
  /// In en, this message translates to:
  /// **'Grammar'**
  String get grammar;

  /// No description provided for @breakingDown.
  ///
  /// In en, this message translates to:
  /// **'Breaking down...'**
  String get breakingDown;

  /// No description provided for @searchingProverbs.
  ///
  /// In en, this message translates to:
  /// **'Searching proverbs...'**
  String get searchingProverbs;

  /// No description provided for @literalLabel.
  ///
  /// In en, this message translates to:
  /// **'literal: {text}'**
  String literalLabel(String text);

  /// No description provided for @autoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get autoDetect;

  /// No description provided for @autoMarker.
  ///
  /// In en, this message translates to:
  /// **'(auto)'**
  String get autoMarker;

  /// No description provided for @pluralTag.
  ///
  /// In en, this message translates to:
  /// **'pl. {plural}'**
  String pluralTag(String plural);

  /// No description provided for @etymLabel.
  ///
  /// In en, this message translates to:
  /// **'etym.'**
  String get etymLabel;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History ({count})'**
  String historyTitle(int count);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchHint;

  /// No description provided for @confirmDeletion.
  ///
  /// In en, this message translates to:
  /// **'Confirm deletion'**
  String get confirmDeletion;

  /// No description provided for @deleteEntriesQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} entries?'**
  String deleteEntriesQuestion(int count);

  /// No description provided for @deleteEntriesFilteredQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} entries ({filter})?'**
  String deleteEntriesFilteredQuestion(int count, String filter);

  /// No description provided for @olderThanDaysDesc.
  ///
  /// In en, this message translates to:
  /// **'>{days} days old'**
  String olderThanDaysDesc(int days);

  /// No description provided for @selectEntries.
  ///
  /// In en, this message translates to:
  /// **'Select entries'**
  String get selectEntries;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @allLabel.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allLabel;

  /// No description provided for @tooltipDeleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get tooltipDeleteSelected;

  /// No description provided for @tooltipDeleteShown.
  ///
  /// In en, this message translates to:
  /// **'Delete shown entries'**
  String get tooltipDeleteShown;

  /// No description provided for @tooltipSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get tooltipSelect;

  /// No description provided for @olderThanChip.
  ///
  /// In en, this message translates to:
  /// **'>{days} d'**
  String olderThanChip(int days);

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearFilters;

  /// No description provided for @noEntriesMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No entries match the filter'**
  String get noEntriesMatchFilter;

  /// No description provided for @noTranslationsYet.
  ///
  /// In en, this message translates to:
  /// **'No translations yet.\nUse the Translate tab!'**
  String get noTranslationsYet;

  /// No description provided for @patternsTitle.
  ///
  /// In en, this message translates to:
  /// **'Patterns'**
  String get patternsTitle;

  /// No description provided for @statTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get statTotal;

  /// No description provided for @statPairs.
  ///
  /// In en, this message translates to:
  /// **'Pairs'**
  String get statPairs;

  /// No description provided for @statHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get statHard;

  /// No description provided for @myMistakes.
  ///
  /// In en, this message translates to:
  /// **'My mistakes ({count})'**
  String myMistakes(int count);

  /// No description provided for @training.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get training;

  /// No description provided for @mistakesHint.
  ///
  /// In en, this message translates to:
  /// **'Check your texts in the Correct tab — mistakes will be remembered here and turned into training sessions.'**
  String get mistakesHint;

  /// No description provided for @wordsLookedUpRepeatedly.
  ///
  /// In en, this message translates to:
  /// **'Words you look up repeatedly'**
  String get wordsLookedUpRepeatedly;

  /// No description provided for @noRepeatedPatterns.
  ///
  /// In en, this message translates to:
  /// **'No repeated patterns yet.'**
  String get noRepeatedPatterns;

  /// No description provided for @timesCount.
  ///
  /// In en, this message translates to:
  /// **'{count}x'**
  String timesCount(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get themeMedium;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeExtra.
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get themeExtra;

  /// No description provided for @fontSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSizeLabel;

  /// No description provided for @fontPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview: Aa Бб Ññ'**
  String get fontPreview;

  /// No description provided for @sectionOfflineTranslation.
  ///
  /// In en, this message translates to:
  /// **'Offline Translation'**
  String get sectionOfflineTranslation;

  /// No description provided for @preferOffline.
  ///
  /// In en, this message translates to:
  /// **'Prefer offline translation'**
  String get preferOffline;

  /// No description provided for @preferOfflineDesc.
  ///
  /// In en, this message translates to:
  /// **'Use on-device engines (ML Kit / local LLM) instead of online APIs.'**
  String get preferOfflineDesc;

  /// No description provided for @sectionAiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI assistant (Claude / ChatGPT)'**
  String get sectionAiAssistant;

  /// No description provided for @aiKeyDesc.
  ///
  /// In en, this message translates to:
  /// **'AI checks what you write, explains mistakes and idioms, and builds practice from YOUR data. On a computer the simplest option is your Claude subscription through Claude Code — no API key or extra payment.'**
  String get aiKeyDesc;

  /// No description provided for @providerLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get providerLabel;

  /// No description provided for @providerAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (any configured)'**
  String get providerAuto;

  /// No description provided for @providerCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom / free'**
  String get providerCustom;

  /// No description provided for @customApiHint.
  ///
  /// In en, this message translates to:
  /// **'Any OpenAI-compatible service. Free options: Gemini (aistudio.google.com), Groq (console.groq.com), OpenRouter (models tagged “:free”), or a local LM Studio / llama.cpp server.'**
  String get customApiHint;

  /// No description provided for @customBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'API base URL (without /chat/completions)'**
  String get customBaseUrlLabel;

  /// No description provided for @customModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model name'**
  String get customModelLabel;

  /// No description provided for @customKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API key (leave empty for a local server)'**
  String get customKeyLabel;

  /// No description provided for @presetLabel.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presetLabel;

  /// No description provided for @freeLocalHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Free and local'**
  String get freeLocalHintTitle;

  /// No description provided for @freeLocalHintBody.
  ///
  /// In en, this message translates to:
  /// **'Ollama needs no keys and has no limits. Install it from ollama.com, run “ollama pull qwen2.5:3b”, then turn on the switch below — Correct, Context and Training all work for free.'**
  String get freeLocalHintBody;

  /// No description provided for @ollamaTitle.
  ///
  /// In en, this message translates to:
  /// **'Ollama — local and free'**
  String get ollamaTitle;

  /// No description provided for @ollamaDesc.
  ///
  /// In en, this message translates to:
  /// **'Your own model on this computer: no keys, no limits, no text leaving the machine.'**
  String get ollamaDesc;

  /// No description provided for @ollamaUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Ollama address'**
  String get ollamaUrlLabel;

  /// No description provided for @ollamaModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get ollamaModelLabel;

  /// No description provided for @ollamaCheck.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get ollamaCheck;

  /// No description provided for @ollamaChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get ollamaChecking;

  /// No description provided for @ollamaOk.
  ///
  /// In en, this message translates to:
  /// **'Ollama responds. Available models: {models}'**
  String ollamaOk(String models);

  /// No description provided for @ollamaNoModels.
  ///
  /// In en, this message translates to:
  /// **'Ollama responds but has no models. Run: ollama pull {model}'**
  String ollamaNoModels(String model);

  /// No description provided for @ollamaModelMissing.
  ///
  /// In en, this message translates to:
  /// **'Model “{model}” is not installed. Run: ollama pull {model}'**
  String ollamaModelMissing(String model);

  /// No description provided for @ollamaUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Ollama is not responding at {url}. Start the Ollama app and retry.'**
  String ollamaUnreachable(String url);

  /// No description provided for @providerKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'No API key for “{provider}” — enter it below or pick another provider'**
  String providerKeyMissing(String provider);

  /// No description provided for @anthropicKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Anthropic API key (Claude)'**
  String get anthropicKeyLabel;

  /// No description provided for @openaiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API key (ChatGPT)'**
  String get openaiKeyLabel;

  /// No description provided for @sectionOnlineTranslators.
  ///
  /// In en, this message translates to:
  /// **'Online Translators'**
  String get sectionOnlineTranslators;

  /// No description provided for @preferredLabel.
  ///
  /// In en, this message translates to:
  /// **'Preferred'**
  String get preferredLabel;

  /// No description provided for @googleFreeDesc.
  ///
  /// In en, this message translates to:
  /// **'Free, no key needed'**
  String get googleFreeDesc;

  /// No description provided for @apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKeyLabel;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @mlkitModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'ML Kit offline models'**
  String get mlkitModelsTitle;

  /// No description provided for @mlkitOnlyMobile.
  ///
  /// In en, this message translates to:
  /// **'Only available on Android/iOS. On desktop use the on-device LLM below.'**
  String get mlkitOnlyMobile;

  /// No description provided for @mlkitModelsSize.
  ///
  /// In en, this message translates to:
  /// **'ML Kit offline models (~30 MB each)'**
  String get mlkitModelsSize;

  /// No description provided for @modelDownloadedOffline.
  ///
  /// In en, this message translates to:
  /// **'Downloaded — works offline'**
  String get modelDownloadedOffline;

  /// No description provided for @modelNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get modelNotDownloaded;

  /// No description provided for @deleteModel.
  ///
  /// In en, this message translates to:
  /// **'Delete model'**
  String get deleteModel;

  /// No description provided for @downloadModel.
  ///
  /// In en, this message translates to:
  /// **'Download model'**
  String get downloadModel;

  /// No description provided for @downloadFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailedWithError(String error);

  /// No description provided for @deleteFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailedWithError(String error);

  /// No description provided for @onDeviceLlmTitle.
  ///
  /// In en, this message translates to:
  /// **'On-device LLM (Gemma / Qwen)'**
  String get onDeviceLlmTitle;

  /// No description provided for @llmInstalledReady.
  ///
  /// In en, this message translates to:
  /// **'{name} — installed, ready'**
  String llmInstalledReady(String name);

  /// No description provided for @llmDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'~500 MB – 1.6 GB download, runs fully offline'**
  String get llmDownloadDesc;

  /// No description provided for @downloadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String downloadingPercent(String percent);

  /// No description provided for @modelTokenButton.
  ///
  /// In en, this message translates to:
  /// **'Model / token'**
  String get modelTokenButton;

  /// No description provided for @modelUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Model URL (.task / .litertlm)'**
  String get modelUrlLabel;

  /// No description provided for @hfTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'HuggingFace token (gated models)'**
  String get hfTokenLabel;

  /// No description provided for @saveUrlToken.
  ///
  /// In en, this message translates to:
  /// **'Save URL / token'**
  String get saveUrlToken;

  /// No description provided for @modelSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Model settings saved'**
  String get modelSettingsSaved;

  /// No description provided for @modelInstalled.
  ///
  /// In en, this message translates to:
  /// **'Model installed'**
  String get modelInstalled;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get modelDownloadFailed;

  /// No description provided for @modelGatedHint.
  ///
  /// In en, this message translates to:
  /// **'This model is license-gated on Hugging Face (HTTP 401). Paste an HF token under “Model / token” (after accepting the license on the model page) or keep the open default model (Qwen2.5).'**
  String get modelGatedHint;

  /// No description provided for @deleteOnDeviceModelQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete on-device model?'**
  String get deleteOnDeviceModelQuestion;

  /// No description provided for @deleteOnDeviceModelDesc.
  ///
  /// In en, this message translates to:
  /// **'This frees disk space but the next on-device translation will need to download the model again.'**
  String get deleteOnDeviceModelDesc;

  /// No description provided for @polishTitle.
  ///
  /// In en, this message translates to:
  /// **'Polish'**
  String get polishTitle;

  /// No description provided for @detailsButton.
  ///
  /// In en, this message translates to:
  /// **'Explain in depth'**
  String get detailsButton;

  /// No description provided for @detailsLoading.
  ///
  /// In en, this message translates to:
  /// **'Preparing the breakdown…'**
  String get detailsLoading;

  /// No description provided for @detailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Breakdown: rules, examples, word history'**
  String get detailsTitle;

  /// No description provided for @mistakesRecorded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} mistake recorded — it will feed your training} other{{count} mistakes recorded — they will feed your training}}'**
  String mistakesRecorded(int count);

  /// No description provided for @toTraining.
  ///
  /// In en, this message translates to:
  /// **'Go to training'**
  String get toTraining;

  /// No description provided for @dueForReview.
  ///
  /// In en, this message translates to:
  /// **'Due for review today: {count}'**
  String dueForReview(int count);

  /// No description provided for @nothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing due today — a new session will pick up fresh mistakes'**
  String get nothingDue;

  /// No description provided for @repetitionExplained.
  ///
  /// In en, this message translates to:
  /// **'Covered mistakes come back for review after 1, 3, 7, 21 and 60 days.'**
  String get repetitionExplained;

  /// No description provided for @noBackendHint.
  ///
  /// In en, this message translates to:
  /// **'Writing correction needs an AI: on a computer pick “Claude · subscription” in Settings → AI assistant; on a phone add a Claude API key or a free compatible service.'**
  String get noBackendHint;

  /// No description provided for @writeSomethingIn.
  ///
  /// In en, this message translates to:
  /// **'Write something in {lang}…'**
  String writeSomethingIn(String lang);

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// No description provided for @checkButton.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get checkButton;

  /// No description provided for @looksPerfect.
  ///
  /// In en, this message translates to:
  /// **'Looks perfect!'**
  String get looksPerfect;

  /// No description provided for @fixesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 fix} other{{count} fixes}}'**
  String fixesCount(int count);

  /// No description provided for @catGrammar.
  ///
  /// In en, this message translates to:
  /// **'grammar'**
  String get catGrammar;

  /// No description provided for @catWord.
  ///
  /// In en, this message translates to:
  /// **'word'**
  String get catWord;

  /// No description provided for @catArticle.
  ///
  /// In en, this message translates to:
  /// **'article'**
  String get catArticle;

  /// No description provided for @catSpelling.
  ///
  /// In en, this message translates to:
  /// **'spelling'**
  String get catSpelling;

  /// No description provided for @catPunctuation.
  ///
  /// In en, this message translates to:
  /// **'punct.'**
  String get catPunctuation;

  /// No description provided for @catStyle.
  ///
  /// In en, this message translates to:
  /// **'style'**
  String get catStyle;

  /// No description provided for @generating.
  ///
  /// In en, this message translates to:
  /// **'Generating…'**
  String get generating;

  /// No description provided for @newTrainingFromMistakes.
  ///
  /// In en, this message translates to:
  /// **'New training from my mistakes'**
  String get newTrainingFromMistakes;

  /// No description provided for @noTrainingsYet.
  ///
  /// In en, this message translates to:
  /// **'No trainings yet.\n\nCheck your texts in the Correct tab — mistakes are remembered, and a personal course is built from them: rule explanations, exercises and texts tailored to your weak spots.'**
  String get noTrainingsYet;

  /// No description provided for @saveToNotebook.
  ///
  /// In en, this message translates to:
  /// **'To notebook'**
  String get saveToNotebook;

  /// No description provided for @savedToNotebook.
  ///
  /// In en, this message translates to:
  /// **'In notebook'**
  String get savedToNotebook;

  /// No description provided for @savedToNotebookSnack.
  ///
  /// In en, this message translates to:
  /// **'Added to your notebook: {text}'**
  String savedToNotebookSnack(String text);

  /// No description provided for @ownTextCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Your {lang}'**
  String ownTextCheckTitle(String lang);

  /// No description provided for @ownTextChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking what you wrote…'**
  String get ownTextChecking;

  /// No description provided for @ownTextPerfect.
  ///
  /// In en, this message translates to:
  /// **'Written correctly'**
  String get ownTextPerfect;

  /// No description provided for @ownTextFixes.
  ///
  /// In en, this message translates to:
  /// **'Fixes: {count}'**
  String ownTextFixes(int count);

  /// No description provided for @notAnError.
  ///
  /// In en, this message translates to:
  /// **'Not a mistake'**
  String get notAnError;

  /// No description provided for @markedNotError.
  ///
  /// In en, this message translates to:
  /// **'Removed from your mistakes'**
  String get markedNotError;

  /// No description provided for @upgradeLabel.
  ///
  /// In en, this message translates to:
  /// **'could be more natural'**
  String get upgradeLabel;

  /// No description provided for @notRecordedLocal.
  ///
  /// In en, this message translates to:
  /// **'Not recorded as mistakes: small local models are often wrong.'**
  String get notRecordedLocal;

  /// No description provided for @sectionLearning.
  ///
  /// In en, this message translates to:
  /// **'What I\'m developing'**
  String get sectionLearning;

  /// No description provided for @learningLangLabel.
  ///
  /// In en, this message translates to:
  /// **'Language I\'m developing'**
  String get learningLangLabel;

  /// No description provided for @autoCheckLabel.
  ///
  /// In en, this message translates to:
  /// **'Check my {lang} automatically'**
  String autoCheckLabel(String lang);

  /// No description provided for @autoCheckDesc.
  ///
  /// In en, this message translates to:
  /// **'Whatever you type in this language on the Translate screen is checked in the background; real mistakes go to your notebook.'**
  String get autoCheckDesc;

  /// No description provided for @providerClaudeCode.
  ///
  /// In en, this message translates to:
  /// **'Claude · subscription (Claude Code)'**
  String get providerClaudeCode;

  /// No description provided for @providerClaudeApi.
  ///
  /// In en, this message translates to:
  /// **'Claude · API key'**
  String get providerClaudeApi;

  /// No description provided for @claudeModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Claude model'**
  String get claudeModelLabel;

  /// No description provided for @claudeCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Claude Code on this computer'**
  String get claudeCodeTitle;

  /// No description provided for @claudeCodeReady.
  ///
  /// In en, this message translates to:
  /// **'Installed {version} · signed in ({plan})'**
  String claudeCodeReady(String version, String plan);

  /// No description provided for @claudeCodeChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking Claude Code…'**
  String get claudeCodeChecking;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @checkConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get checkConnection;

  /// No description provided for @checkingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get checkingConnection;

  /// No description provided for @connectionOk.
  ///
  /// In en, this message translates to:
  /// **'Works: {backend} · {seconds} s'**
  String connectionOk(String backend, String seconds);

  /// No description provided for @aiUsageMonth.
  ///
  /// In en, this message translates to:
  /// **'This month: {count} AI requests ({ok} successful), pay-per-use ≈ \${cost}'**
  String aiUsageMonth(int count, int ok, String cost);

  /// No description provided for @sectionDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Data and diagnostics'**
  String get sectionDiagnostics;

  /// No description provided for @dataFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Data folder'**
  String get dataFolderLabel;

  /// No description provided for @settingsFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Settings file'**
  String get settingsFileLabel;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Settings were NOT saved: {error}'**
  String settingsSaveFailed(String error);

  /// No description provided for @importedLegacy.
  ///
  /// In en, this message translates to:
  /// **'History from older versions merged: {files} file(s), {rows} records'**
  String importedLegacy(int files, int rows);

  /// No description provided for @notebookTitle.
  ///
  /// In en, this message translates to:
  /// **'Notebook'**
  String get notebookTitle;

  /// No description provided for @notebookCounts.
  ///
  /// In en, this message translates to:
  /// **'{expressions} words and expressions · {mistakes} mistakes to work on'**
  String notebookCounts(int expressions, int mistakes);

  /// No description provided for @notebookEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty so far. Tap “To notebook” next to words and proverbs, and write in the language you are developing — mistakes will be added by themselves.'**
  String get notebookEmpty;

  /// No description provided for @topConstructions.
  ///
  /// In en, this message translates to:
  /// **'My problem constructions'**
  String get topConstructions;

  /// No description provided for @removeFromNotebook.
  ///
  /// In en, this message translates to:
  /// **'Remove from notebook'**
  String get removeFromNotebook;

  /// No description provided for @aiNeededTitle.
  ///
  /// In en, this message translates to:
  /// **'AI is not set up'**
  String get aiNeededTitle;

  /// No description provided for @trainingDone.
  ///
  /// In en, this message translates to:
  /// **'I\'ve done this session'**
  String get trainingDone;

  /// No description provided for @trainingDoneMarked.
  ///
  /// In en, this message translates to:
  /// **'Done — these mistakes come back on schedule (1 → 3 → 7 → 21 → 60 days).'**
  String get trainingDoneMarked;

  /// No description provided for @removeWordLabel.
  ///
  /// In en, this message translates to:
  /// **'(remove)'**
  String get removeWordLabel;

  /// No description provided for @tabFeed.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get tabFeed;

  /// No description provided for @feedTitle.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get feedTitle;

  /// No description provided for @feedToday.
  ///
  /// In en, this message translates to:
  /// **'Today: {count} stories · {due} due for review'**
  String feedToday(int count, int due);

  /// No description provided for @feedBuildMore.
  ///
  /// In en, this message translates to:
  /// **'More stories'**
  String get feedBuildMore;

  /// No description provided for @feedBuilding.
  ///
  /// In en, this message translates to:
  /// **'Writing today\'s edition…'**
  String get feedBuilding;

  /// No description provided for @feedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your feed is empty. It is written from today\'s real news and uses YOUR mistakes and the expressions you are taking into use.'**
  String get feedEmpty;

  /// No description provided for @feedBuildToday.
  ///
  /// In en, this message translates to:
  /// **'Write today\'s edition'**
  String get feedBuildToday;

  /// No description provided for @feedFailedItems.
  ///
  /// In en, this message translates to:
  /// **'{count} stories were dropped: the model failed the fact or target checks.'**
  String feedFailedItems(int count);

  /// No description provided for @feedOpenOriginal.
  ///
  /// In en, this message translates to:
  /// **'Source: {outlet} — open the original'**
  String feedOpenOriginal(String outlet);

  /// No description provided for @tasksTitle.
  ///
  /// In en, this message translates to:
  /// **'PRACTICE'**
  String get tasksTitle;

  /// No description provided for @yourMistakeShort.
  ///
  /// In en, this message translates to:
  /// **'you wrote «{wrong}» → «{right}»'**
  String yourMistakeShort(String wrong, String right);

  /// No description provided for @yourMistake.
  ///
  /// In en, this message translates to:
  /// **'You wrote: «{wrong}» → correct: «{right}»'**
  String yourMistake(String wrong, String right);

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @taskCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct!'**
  String get taskCorrect;

  /// No description provided for @taskAccents.
  ///
  /// In en, this message translates to:
  /// **'Correct — mind the accents: {answer}'**
  String taskAccents(String answer);

  /// No description provided for @taskWrong.
  ///
  /// In en, this message translates to:
  /// **'Answer: {answer}'**
  String taskWrong(String answer);

  /// No description provided for @taskPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Write in Spanish…'**
  String get taskPlaceholder;

  /// No description provided for @taskCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get taskCheck;

  /// No description provided for @taskTargetMissing.
  ///
  /// In en, this message translates to:
  /// **'The target expression wasn\'t used — try to include it next time.'**
  String get taskTargetMissing;

  /// No description provided for @taskModelAnswer.
  ///
  /// In en, this message translates to:
  /// **'Model answer: {answer}'**
  String taskModelAnswer(String answer);

  /// No description provided for @journalTitle.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalTitle;

  /// No description provided for @taskPending.
  ///
  /// In en, this message translates to:
  /// **'Saved. It will be checked when an AI is available — e.g. on your computer after the next exchange.'**
  String get taskPending;

  /// No description provided for @taskChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked.'**
  String get taskChecked;

  /// No description provided for @sectionExchange.
  ///
  /// In en, this message translates to:
  /// **'Exchange between devices'**
  String get sectionExchange;

  /// No description provided for @exchangeDesc.
  ///
  /// In en, this message translates to:
  /// **'Everything you accumulate — history, notebook, mistakes, trainings and feed editions with your answers — is kept in one exchange file per device and merged on the other one. Editions written on the computer with your Claude subscription can be read and practised on the phone; answers come back.'**
  String get exchangeDesc;

  /// No description provided for @exchangeFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Exchange folder (one file per device)'**
  String get exchangeFolderLabel;

  /// No description provided for @exchangeUseOneDrive.
  ///
  /// In en, this message translates to:
  /// **'Use OneDrive'**
  String get exchangeUseOneDrive;

  /// No description provided for @exchangeSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get exchangeSyncNow;

  /// No description provided for @exchangeSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get exchangeSyncing;

  /// No description provided for @exchangeShare.
  ///
  /// In en, this message translates to:
  /// **'Send exchange file'**
  String get exchangeShare;

  /// No description provided for @exchangeLoad.
  ///
  /// In en, this message translates to:
  /// **'Load exchange file'**
  String get exchangeLoad;

  /// No description provided for @exchangeReport.
  ///
  /// In en, this message translates to:
  /// **'Merged: {items} notebook items, {mistakes} mistakes, {feed} stories, {tasks} answers, {history} history records.'**
  String exchangeReport(
      int items, int mistakes, int feed, int tasks, int history);

  /// No description provided for @exchangeNothingNew.
  ///
  /// In en, this message translates to:
  /// **'Nothing new to merge. Your file is updated.'**
  String get exchangeNothingNew;

  /// No description provided for @exchangeGraded.
  ///
  /// In en, this message translates to:
  /// **'Checked answers from the other device: {count}'**
  String exchangeGraded(int count);

  /// No description provided for @exchangePhoneHint.
  ///
  /// In en, this message translates to:
  /// **'On the computer: save the file into its exchange folder (e.g. OneDrive\\LinguaTrace). Here: load the computer\'s file linguatrace-windows-….json.'**
  String get exchangePhoneHint;

  /// No description provided for @feedPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Editions are written on the computer (Claude subscription). Load its exchange file: Settings → Exchange.'**
  String get feedPhoneHint;

  /// No description provided for @feedGlossAfterTask.
  ///
  /// In en, this message translates to:
  /// **'Explanations of the marked words appear after you answer the task below.'**
  String get feedGlossAfterTask;

  /// No description provided for @feedCannotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String feedCannotOpen(String url);

  /// No description provided for @exchangeErrors.
  ///
  /// In en, this message translates to:
  /// **'Not everything was merged: {errors}'**
  String exchangeErrors(String errors);

  /// No description provided for @exchangeFullHistory.
  ///
  /// In en, this message translates to:
  /// **'Include the full translation history'**
  String get exchangeFullHistory;

  /// No description provided for @exchangeFullHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'By default the file carries the notebook, mistakes, the feed and short lookups; long texts (letters) stay on this device. The file is plain text (JSON) — keep it in your own folders.'**
  String get exchangeFullHistoryHint;

  /// No description provided for @exchangeTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This file is too large for an exchange file ({mb} MB).'**
  String exchangeTooLarge(int mb);

  /// No description provided for @claudeCodeTokenInUse.
  ///
  /// In en, this message translates to:
  /// **'Installed {version} · using the subscription token'**
  String claudeCodeTokenInUse(String version);

  /// No description provided for @claudeCodeLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Claude Code'**
  String get claudeCodeLogin;

  /// No description provided for @claudeCodeSetupToken.
  ///
  /// In en, this message translates to:
  /// **'Create a subscription token (1 year)'**
  String get claudeCodeSetupToken;

  /// No description provided for @claudeCodeTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Subscription token (optional)'**
  String get claudeCodeTokenLabel;

  /// No description provided for @claudeCodeTokenHelp.
  ///
  /// In en, this message translates to:
  /// **'From `claude setup-token`: valid for a year, no repeated sign-in. Not an API key: it uses your subscription limits, no extra charge. Stored in settings.json on this computer.'**
  String get claudeCodeTokenHelp;

  /// No description provided for @claudeCodeConsoleLogin1.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Claude Code with the account that has the subscription.'**
  String get claudeCodeConsoleLogin1;

  /// No description provided for @claudeCodeConsoleLogin2.
  ///
  /// In en, this message translates to:
  /// **'A browser opens: sign in and allow access. Then close this window and return to LinguaTrace.'**
  String get claudeCodeConsoleLogin2;

  /// No description provided for @claudeCodeConsoleToken1.
  ///
  /// In en, this message translates to:
  /// **'A one-year subscription token for LinguaTrace (not an API key, no extra charge).'**
  String get claudeCodeConsoleToken1;

  /// No description provided for @claudeCodeConsoleToken2.
  ///
  /// In en, this message translates to:
  /// **'A browser opens: sign in. Then copy the line sk-ant-oat01-... and paste it into LinguaTrace: Settings - AI - Subscription token.'**
  String get claudeCodeConsoleToken2;

  /// No description provided for @providerPcRelay.
  ///
  /// In en, this message translates to:
  /// **'Claude via your computer (subscription)'**
  String get providerPcRelay;

  /// No description provided for @relayClientDesc.
  ///
  /// In en, this message translates to:
  /// **'The phone sends requests to LinguaTrace on your computer, which asks Claude on your subscription. No keys, no extra charge. On the PC: Settings - AI assistant - «Claude for the phone» shows the address and code.'**
  String get relayClientDesc;

  /// No description provided for @relayAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Computer address'**
  String get relayAddressLabel;

  /// No description provided for @relayCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get relayCodeLabel;

  /// No description provided for @relayServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Claude for the phone'**
  String get relayServerTitle;

  /// No description provided for @relayServerDesc.
  ///
  /// In en, this message translates to:
  /// **'The phone can use this computer\'s Claude (your subscription, no extra charge) while LinguaTrace is running.'**
  String get relayServerDesc;

  /// No description provided for @relayServerRunning.
  ///
  /// In en, this message translates to:
  /// **'Running. On the phone enter the address and the code:'**
  String get relayServerRunning;

  /// No description provided for @relayNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'No network — connect the computer to Wi-Fi or a local network.'**
  String get relayNoNetwork;

  /// No description provided for @relayNewCode.
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get relayNewCode;

  /// No description provided for @relayServerHint.
  ///
  /// In en, this message translates to:
  /// **'The phone and the computer must be on the same Wi-Fi. Away from home: install Tailscale on both and use the computer\'s 100.x.x.x address. The first time, Windows asks for network access — allow it for private networks.'**
  String get relayServerHint;

  /// No description provided for @fastModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model for quick answers'**
  String get fastModelLabel;

  /// No description provided for @fastModelHint.
  ///
  /// In en, this message translates to:
  /// **'Text check, hints, word choice, origins. The main model above writes the feed and trainings.'**
  String get fastModelHint;

  /// No description provided for @claudeWarmLabel.
  ///
  /// In en, this message translates to:
  /// **'Keep Claude ready'**
  String get claudeWarmLabel;

  /// No description provided for @claudeWarmHint.
  ///
  /// In en, this message translates to:
  /// **'Answers in 1–3 s instead of ~10 s: Claude Code stays running (≈150–250 MB of memory).'**
  String get claudeWarmHint;

  /// No description provided for @startupTimesLabel.
  ///
  /// In en, this message translates to:
  /// **'Startup time'**
  String get startupTimesLabel;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @askClaudeApp.
  ///
  /// In en, this message translates to:
  /// **'Ask in the Claude app'**
  String get askClaudeApp;

  /// No description provided for @chipChoice.
  ///
  /// In en, this message translates to:
  /// **'Word choice'**
  String get chipChoice;

  /// No description provided for @chipOrigin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get chipOrigin;

  /// No description provided for @chosenTranslation.
  ///
  /// In en, this message translates to:
  /// **'Claude · chosen'**
  String get chosenTranslation;

  /// No description provided for @etymologyAskPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tell me the origin of «{term}» ({lang}): its path from Latin and other languages, why it is named so, related words in Spanish, Russian and English, the history of the expression. Briefly.'**
  String etymologyAskPrompt(String term, String lang);

  /// No description provided for @etymologyRebuild.
  ///
  /// In en, this message translates to:
  /// **'Write again'**
  String get etymologyRebuild;

  /// No description provided for @etymologyWriting.
  ///
  /// In en, this message translates to:
  /// **'Claude is writing the page…'**
  String get etymologyWriting;

  /// No description provided for @etymologyPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Origin pages are written by Claude. Turn on «Claude via your computer» (Settings - AI assistant) or load the exchange file — it carries the pages written on the computer.'**
  String get etymologyPhoneHint;

  /// No description provided for @etymologyCertainty.
  ///
  /// In en, this message translates to:
  /// **'{certainty, select, documented{documented} probable{probable} disputed{disputed} folk{folk story} other{?}}'**
  String etymologyCertainty(String certainty);

  /// No description provided for @etymologyChain.
  ///
  /// In en, this message translates to:
  /// **'The word\'s path'**
  String get etymologyChain;

  /// No description provided for @etymologyWhy.
  ///
  /// In en, this message translates to:
  /// **'Why it is named so'**
  String get etymologyWhy;

  /// No description provided for @etymologyIdiomStory.
  ///
  /// In en, this message translates to:
  /// **'Where the expression comes from'**
  String get etymologyIdiomStory;

  /// No description provided for @etymologyHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get etymologyHistory;

  /// No description provided for @etymologyRelatives.
  ///
  /// In en, this message translates to:
  /// **'Related words'**
  String get etymologyRelatives;

  /// No description provided for @etymologyFalseFriends.
  ///
  /// In en, this message translates to:
  /// **'False friends'**
  String get etymologyFalseFriends;

  /// No description provided for @etymologyMnemonic.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get etymologyMnemonic;

  /// No description provided for @etymologySources.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get etymologySources;

  /// No description provided for @etymologyNoSources.
  ///
  /// In en, this message translates to:
  /// **'No dictionary entry — from general knowledge'**
  String get etymologyNoSources;

  /// No description provided for @wordChoiceAskPrompt.
  ///
  /// In en, this message translates to:
  /// **'I am translating into Spanish: «{source}». Machine translation: «{translation}». I do not like the word: {focus}. Suggest options with their nuances and rewrite the sentence with each.'**
  String wordChoiceAskPrompt(String source, String translation, String focus);

  /// No description provided for @wordChoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Word choice'**
  String get wordChoiceTitle;

  /// No description provided for @wordChoiceNow.
  ///
  /// In en, this message translates to:
  /// **'Current translation:'**
  String get wordChoiceNow;

  /// No description provided for @wordChoicePick.
  ///
  /// In en, this message translates to:
  /// **'Which word should be better? Tap it — or pick none for the whole sentence.'**
  String get wordChoicePick;

  /// No description provided for @wordChoiceHintLabel.
  ///
  /// In en, this message translates to:
  /// **'What you want to say (optional)'**
  String get wordChoiceHintLabel;

  /// No description provided for @wordChoiceHintExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. to contribute, not to bring a thing'**
  String get wordChoiceHintExample;

  /// No description provided for @wordChoiceRunSentence.
  ///
  /// In en, this message translates to:
  /// **'Find options'**
  String get wordChoiceRunSentence;

  /// No description provided for @wordChoiceRunWord.
  ///
  /// In en, this message translates to:
  /// **'Options for «{word}»'**
  String wordChoiceRunWord(String word);

  /// No description provided for @wordChoiceNoAiDesktop.
  ///
  /// In en, this message translates to:
  /// **'Without AI these are dictionary options. Connect Claude in Settings for explanations and ready sentences.'**
  String get wordChoiceNoAiDesktop;

  /// No description provided for @wordChoiceNoAiPhone.
  ///
  /// In en, this message translates to:
  /// **'Without AI these are dictionary options. Turn on «Claude via your computer» in Settings for explanations and ready sentences.'**
  String get wordChoiceNoAiPhone;

  /// No description provided for @wordChoiceUse.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get wordChoiceUse;

  /// No description provided for @wordChoiceDictionaryNote.
  ///
  /// In en, this message translates to:
  /// **'Dictionary options: the back-translation next to each shows its sense.'**
  String get wordChoiceDictionaryNote;

  /// No description provided for @wordChoiceFit.
  ///
  /// In en, this message translates to:
  /// **'{fit, select, best{best} good{fits} possible{possible} wrong{not this} other{}}'**
  String wordChoiceFit(String fit);

  /// No description provided for @wordChoiceOrigin.
  ///
  /// In en, this message translates to:
  /// **'Origin?'**
  String get wordChoiceOrigin;

  /// No description provided for @tabIdeas.
  ///
  /// In en, this message translates to:
  /// **'Ideas'**
  String get tabIdeas;

  /// No description provided for @ideasTitle.
  ///
  /// In en, this message translates to:
  /// **'Ideas'**
  String get ideasTitle;

  /// No description provided for @ideasEmpty.
  ///
  /// In en, this message translates to:
  /// **'Thoughts for articles and inventions gather here. Create a project and describe its context — then just dictate on the go. In the background I add punctuation, search the web for what is already known, and assemble a draft.'**
  String get ideasEmpty;

  /// No description provided for @ideasNewProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get ideasNewProject;

  /// No description provided for @ideasDictate.
  ///
  /// In en, this message translates to:
  /// **'Dictate'**
  String get ideasDictate;

  /// No description provided for @ideasProjectTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get ideasProjectTitleLabel;

  /// No description provided for @ideasContextLabel.
  ///
  /// In en, this message translates to:
  /// **'Context: what it is about, for whom, what matters'**
  String get ideasContextLabel;

  /// No description provided for @ideasKindArticle.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get ideasKindArticle;

  /// No description provided for @ideasKindInvention.
  ///
  /// In en, this message translates to:
  /// **'Invention'**
  String get ideasKindInvention;

  /// No description provided for @ideasKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get ideasKindOther;

  /// No description provided for @ideasCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get ideasCreate;

  /// No description provided for @ideasCounts.
  ///
  /// In en, this message translates to:
  /// **'thoughts: {notes} · sources: {sources}'**
  String ideasCounts(int notes, int sources);

  /// No description provided for @ideasContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get ideasContext;

  /// No description provided for @ideasEditContext.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get ideasEditContext;

  /// No description provided for @ideasSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get ideasSources;

  /// No description provided for @ideasAddSource.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get ideasAddSource;

  /// No description provided for @ideasAddText.
  ///
  /// In en, this message translates to:
  /// **'Paste text'**
  String get ideasAddText;

  /// No description provided for @ideasAddUrl.
  ///
  /// In en, this message translates to:
  /// **'Link to an article'**
  String get ideasAddUrl;

  /// No description provided for @ideasAddFile.
  ///
  /// In en, this message translates to:
  /// **'File (txt, md, html, pdf)'**
  String get ideasAddFile;

  /// No description provided for @ideasUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Page address'**
  String get ideasUrlLabel;

  /// No description provided for @ideasTextLabel.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get ideasTextLabel;

  /// No description provided for @ideasAdding.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get ideasAdding;

  /// No description provided for @ideasSourceText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get ideasSourceText;

  /// No description provided for @ideasFound.
  ///
  /// In en, this message translates to:
  /// **'Found by search'**
  String get ideasFound;

  /// No description provided for @ideasNotes.
  ///
  /// In en, this message translates to:
  /// **'Thoughts'**
  String get ideasNotes;

  /// No description provided for @ideasNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No thoughts yet — tap «Dictate».'**
  String get ideasNoNotes;

  /// No description provided for @ideasStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'queued'**
  String get ideasStatusQueued;

  /// No description provided for @ideasStatusWorking.
  ///
  /// In en, this message translates to:
  /// **'searching and analysing…'**
  String get ideasStatusWorking;

  /// No description provided for @ideasStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'waiting for AI'**
  String get ideasStatusOffline;

  /// No description provided for @ideasStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get ideasStatusFailed;

  /// No description provided for @ideasRetry.
  ///
  /// In en, this message translates to:
  /// **'Analyse again'**
  String get ideasRetry;

  /// No description provided for @ideasInsight.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get ideasInsight;

  /// No description provided for @ideasWithWeb.
  ///
  /// In en, this message translates to:
  /// **'with search'**
  String get ideasWithWeb;

  /// No description provided for @ideasDraft.
  ///
  /// In en, this message translates to:
  /// **'Assemble a draft'**
  String get ideasDraft;

  /// No description provided for @ideasDrafting.
  ///
  /// In en, this message translates to:
  /// **'Assembling the draft…'**
  String get ideasDrafting;

  /// No description provided for @ideasDraftLabel.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get ideasDraftLabel;

  /// No description provided for @ideasShare.
  ///
  /// In en, this message translates to:
  /// **'Share (Markdown)'**
  String get ideasShare;

  /// No description provided for @ideasDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get ideasDelete;

  /// No description provided for @ideasDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete «{title}» with all its thoughts and sources?'**
  String ideasDeleteConfirm(String title);

  /// No description provided for @ideasRaw.
  ///
  /// In en, this message translates to:
  /// **'Original dictation'**
  String get ideasRaw;

  /// No description provided for @ideasNoAi.
  ///
  /// In en, this message translates to:
  /// **'Without AI thoughts are only saved. Claude adds punctuation, searches and analyses: connect it (Settings - AI assistant) or sync with your computer.'**
  String get ideasNoAi;

  /// No description provided for @ideasWebLabel.
  ///
  /// In en, this message translates to:
  /// **'Search the web for ideas'**
  String get ideasWebLabel;

  /// No description provided for @ideasWebHint.
  ///
  /// In en, this message translates to:
  /// **'Claude looks for prior art, facts and sources for each thought. With an API key: up to 5 searches per thought, \$10 per 1,000 searches.'**
  String get ideasWebHint;

  /// No description provided for @dictationListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get dictationListening;

  /// No description provided for @dictationPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get dictationPaused;

  /// No description provided for @dictationNewNote.
  ///
  /// In en, this message translates to:
  /// **'New thought'**
  String get dictationNewNote;

  /// No description provided for @dictationStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get dictationStop;

  /// No description provided for @dictationResume.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get dictationResume;

  /// No description provided for @dictationHint.
  ///
  /// In en, this message translates to:
  /// **'Speak freely, pauses are fine. «New thought» starts the next one, «what do you think?» — Claude answers and asks, «stop recording» ends. You can turn the screen off.'**
  String get dictationHint;

  /// No description provided for @dictationSaved.
  ///
  /// In en, this message translates to:
  /// **'thoughts saved: {n}'**
  String dictationSaved(int n);

  /// No description provided for @dictationNoVoice.
  ///
  /// In en, this message translates to:
  /// **'No speech recognition on this device — type the thought.'**
  String get dictationNoVoice;

  /// No description provided for @dictationError.
  ///
  /// In en, this message translates to:
  /// **'Recognition stopped ({error}). Tap «Continue».'**
  String dictationError(String error);

  /// No description provided for @dictationTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Thought'**
  String get dictationTypeHint;

  /// No description provided for @dictationSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get dictationSave;

  /// No description provided for @anthropicKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Create a key at console.anthropic.com → API keys. API requests are billed separately from a claude.ai subscription. With a key Claude works on the phone too — no PC needed.'**
  String get anthropicKeyHelp;

  /// No description provided for @dictationReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting recognition: {reason}'**
  String dictationReconnecting(String reason);

  /// No description provided for @dictationTroubleNet.
  ///
  /// In en, this message translates to:
  /// **'no connection'**
  String get dictationTroubleNet;

  /// No description provided for @dictationTroubleMic.
  ///
  /// In en, this message translates to:
  /// **'the microphone is busy'**
  String get dictationTroubleMic;

  /// No description provided for @dictationTroubleBackground.
  ///
  /// In en, this message translates to:
  /// **'Android gives no microphone in the background — turn the screen on'**
  String get dictationTroubleBackground;

  /// No description provided for @dictationTroubleBusy.
  ///
  /// In en, this message translates to:
  /// **'the recogniser is busy'**
  String get dictationTroubleBusy;

  /// No description provided for @dictationErrPermission.
  ///
  /// In en, this message translates to:
  /// **'no microphone access — allow it for LinguaTrace in the phone settings'**
  String get dictationErrPermission;

  /// No description provided for @dictationErrLanguage.
  ///
  /// In en, this message translates to:
  /// **'this language is not recognised on the phone — add it in Google voice typing settings'**
  String get dictationErrLanguage;

  /// No description provided for @dictationErrInit.
  ///
  /// In en, this message translates to:
  /// **'speech recognition unavailable — check microphone access and Google voice typing'**
  String get dictationErrInit;

  /// No description provided for @dictationErrNoRecognizer.
  ///
  /// In en, this message translates to:
  /// **'the phone has no speech recognition service (the Google app is needed)'**
  String get dictationErrNoRecognizer;

  /// No description provided for @dictationMuteBeeps.
  ///
  /// In en, this message translates to:
  /// **'No beeps: mute media sound while recording'**
  String get dictationMuteBeeps;

  /// No description provided for @dictationLog.
  ///
  /// In en, this message translates to:
  /// **'Recognition log'**
  String get dictationLog;

  /// No description provided for @dictationLogHint.
  ///
  /// In en, this message translates to:
  /// **'If dictation misbehaves, copy the log and send it.'**
  String get dictationLogHint;

  /// No description provided for @dictationLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'The log is empty.'**
  String get dictationLogEmpty;

  /// No description provided for @dictationCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get dictationCopy;

  /// No description provided for @dictationCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get dictationCopied;

  /// No description provided for @syncServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync server'**
  String get syncServerTitle;

  /// No description provided for @syncServerHint.
  ///
  /// In en, this message translates to:
  /// **'Your own server where every device\'s data comes together (the program in the project\'s server folder). The phone and computers exchange through it by themselves: at start, every 10 minutes and after dictation.'**
  String get syncServerHint;

  /// No description provided for @syncServerUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get syncServerUrlLabel;

  /// No description provided for @syncServerKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Access key'**
  String get syncServerKeyLabel;

  /// No description provided for @syncServerNow.
  ///
  /// In en, this message translates to:
  /// **'Sync with the server'**
  String get syncServerNow;

  /// No description provided for @syncServerSent.
  ///
  /// In en, this message translates to:
  /// **'This device\'s data was sent to the server.'**
  String get syncServerSent;

  /// No description provided for @dictationDiscuss.
  ///
  /// In en, this message translates to:
  /// **'Discuss'**
  String get dictationDiscuss;

  /// No description provided for @dictationThinking.
  ///
  /// In en, this message translates to:
  /// **'Claude is thinking…'**
  String get dictationThinking;

  /// No description provided for @dictationSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Claude is speaking…'**
  String get dictationSpeaking;

  /// No description provided for @dictationStopSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Interrupt'**
  String get dictationStopSpeaking;

  /// No description provided for @dictationBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth headset microphone'**
  String get dictationBluetooth;

  /// No description provided for @dictationDiscussFailed.
  ///
  /// In en, this message translates to:
  /// **'Claude did not answer: {error}'**
  String dictationDiscussFailed(String error);

  /// No description provided for @ideasClaude.
  ///
  /// In en, this message translates to:
  /// **'Claude'**
  String get ideasClaude;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
