// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get tabTranslate => 'Перевод';

  @override
  String get tabCorrect => 'Проверка';

  @override
  String get tabHistory => 'История';

  @override
  String get tabPatterns => 'Инсайты';

  @override
  String get tabSettings => 'Настройки';

  @override
  String get copied => 'Скопировано!';

  @override
  String get cancel => 'Отмена';

  @override
  String get delete => 'Удалить';

  @override
  String get tooltipClear => 'Очистить';

  @override
  String get tooltipCopy => 'Копировать';

  @override
  String get tooltipPaste => 'Вставить';

  @override
  String get typeOrSpeak => 'Введите или продиктуйте...';

  @override
  String get listening => 'Слушаю...';

  @override
  String get chipIdiom => 'Идиома';

  @override
  String get chipWords => 'Слова';

  @override
  String get chipContext => 'Контекст';

  @override
  String viaProvider(String name) {
    return 'через $name';
  }

  @override
  String get noProverbsFound => 'Поговорки для этой фразы не найдены';

  @override
  String idiomsFoundHeader(int count, String lang) {
    return 'Найдено: $count · язык: $lang';
  }

  @override
  String get pickSourceBeforeSwap =>
      'Выберите исходный язык, чтобы поменять направление';

  @override
  String get culturalContext => 'Культурный контекст';

  @override
  String contextFailed(String error) {
    return 'Не удалось получить контекст: $error';
  }

  @override
  String get addAiKeyHint =>
      'Нужен ИИ. На компьютере: Настройки → ИИ-помощник → «Claude · подписка». Бесплатно: совместимый сервис (Gemini, Groq) или Ollama с моделью.';

  @override
  String get tooltipStop => 'Стоп';

  @override
  String get tooltipDictate =>
      'Нажатие: диктовка у курсора · Долгое нажатие: очистить и диктовать';

  @override
  String get allMeanings => 'Все значения';

  @override
  String get grammar => 'Грамматика';

  @override
  String get breakingDown => 'Разбираю по словам...';

  @override
  String get searchingProverbs => 'Ищу поговорки...';

  @override
  String literalLabel(String text) {
    return 'дословно: $text';
  }

  @override
  String get autoDetect => 'Автоопределение';

  @override
  String get autoMarker => '(авто)';

  @override
  String pluralTag(String plural) {
    return 'мн. $plural';
  }

  @override
  String get etymLabel => 'этим.';

  @override
  String historyTitle(int count) {
    return 'История ($count)';
  }

  @override
  String get searchHint => 'Поиск...';

  @override
  String get confirmDeletion => 'Подтвердите удаление';

  @override
  String deleteEntriesQuestion(int count) {
    return 'Удалить записей: $count?';
  }

  @override
  String deleteEntriesFilteredQuestion(int count, String filter) {
    return 'Удалить записей: $count ($filter)?';
  }

  @override
  String olderThanDaysDesc(int days) {
    return 'старше $days дн.';
  }

  @override
  String get selectEntries => 'Выберите записи';

  @override
  String selectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get allLabel => 'Все';

  @override
  String get tooltipDeleteSelected => 'Удалить выбранные';

  @override
  String get tooltipDeleteShown => 'Удалить показанные записи';

  @override
  String get tooltipSelect => 'Выбрать';

  @override
  String olderThanChip(int days) {
    return '>$days дн';
  }

  @override
  String get clearFilters => 'Сбросить';

  @override
  String get noEntriesMatchFilter => 'Нет записей, подходящих под фильтр';

  @override
  String get noTranslationsYet =>
      'Пока нет переводов.\nОткройте вкладку «Перевод»!';

  @override
  String get patternsTitle => 'Инсайты';

  @override
  String get statTotal => 'Всего';

  @override
  String get statPairs => 'Пары';

  @override
  String get statHard => 'Сложные';

  @override
  String myMistakes(int count) {
    return 'Мои ошибки ($count)';
  }

  @override
  String get training => 'Тренировка';

  @override
  String get mistakesHint =>
      'Проверяйте свои тексты во вкладке «Проверка» — ошибки будут запоминаться здесь и превращаться в тренировки.';

  @override
  String get wordsLookedUpRepeatedly => 'Слова, которые вы ищете снова и снова';

  @override
  String get noRepeatedPatterns => 'Повторяющихся запросов пока нет.';

  @override
  String timesCount(int count) {
    return '${count}x';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get sectionAppearance => 'Оформление';

  @override
  String get themeLabel => 'Тема';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeMedium => 'Средняя';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeExtra => 'Белая';

  @override
  String get fontSizeLabel => 'Размер шрифта';

  @override
  String get fontPreview => 'Пример: Aa Бб Ññ';

  @override
  String get sectionOfflineTranslation => 'Офлайн-перевод';

  @override
  String get preferOffline => 'Предпочитать офлайн-перевод';

  @override
  String get preferOfflineDesc =>
      'Использовать движки на устройстве (ML Kit / локальная LLM) вместо онлайн-API.';

  @override
  String get sectionAiAssistant => 'ИИ-помощник (Claude / ChatGPT)';

  @override
  String get aiKeyDesc =>
      'ИИ проверяет то, что вы пишете, объясняет ошибки и выражения и строит практику из ВАШИХ данных. На компьютере проще всего использовать подписку Claude через Claude Code — без API-ключа и доплаты.';

  @override
  String get providerLabel => 'Провайдер';

  @override
  String get providerAuto => 'Авто (какой настроен)';

  @override
  String get providerCustom => 'Свой / бесплатный';

  @override
  String get customApiHint =>
      'Любой OpenAI-совместимый сервис. Бесплатные варианты: Gemini (aistudio.google.com), Groq (console.groq.com), OpenRouter (модели с «:free»), а также локальные LM Studio / llama.cpp.';

  @override
  String get customBaseUrlLabel => 'Адрес API (без /chat/completions)';

  @override
  String get customModelLabel => 'Название модели';

  @override
  String get customKeyLabel => 'Ключ API (пусто — для локального сервера)';

  @override
  String get presetLabel => 'Готовые настройки';

  @override
  String get freeLocalHintTitle => 'Бесплатно и локально';

  @override
  String get freeLocalHintBody =>
      'Ollama работает без ключей и лимитов. Установите ollama.com, выполните в терминале «ollama pull qwen2.5:3b» и включите переключатель ниже — «Проверка», «Контекст» и «Тренировка» заработают бесплатно.';

  @override
  String get ollamaTitle => 'Ollama — локально и бесплатно';

  @override
  String get ollamaDesc =>
      'Своя модель на этом компьютере: без ключей, лимитов и отправки текста в интернет.';

  @override
  String get ollamaUrlLabel => 'Адрес Ollama';

  @override
  String get ollamaModelLabel => 'Модель';

  @override
  String get ollamaCheck => 'Проверить связь';

  @override
  String get ollamaChecking => 'Проверяю…';

  @override
  String ollamaOk(String models) {
    return 'Ollama отвечает. Доступные модели: $models';
  }

  @override
  String ollamaNoModels(String model) {
    return 'Ollama отвечает, но моделей нет. Выполните в терминале: ollama pull $model';
  }

  @override
  String ollamaModelMissing(String model) {
    return 'Модель «$model» не установлена. Выполните: ollama pull $model';
  }

  @override
  String ollamaUnreachable(String url) {
    return 'Ollama не отвечает по адресу $url. Запустите приложение Ollama и повторите.';
  }

  @override
  String providerKeyMissing(String provider) {
    return 'Ключ для «$provider» не задан — введите его ниже или выберите другого провайдера';
  }

  @override
  String get anthropicKeyLabel => 'Ключ API Anthropic (Claude)';

  @override
  String get openaiKeyLabel => 'Ключ API OpenAI (ChatGPT)';

  @override
  String get sectionOnlineTranslators => 'Онлайн-переводчики';

  @override
  String get preferredLabel => 'Предпочтительный';

  @override
  String get googleFreeDesc => 'Бесплатно, ключ не нужен';

  @override
  String get apiKeyLabel => 'Ключ API';

  @override
  String get sectionAbout => 'О приложении';

  @override
  String get mlkitModelsTitle => 'Офлайн-модели ML Kit';

  @override
  String get mlkitOnlyMobile =>
      'Доступно только на Android/iOS. На компьютере используйте локальную LLM ниже.';

  @override
  String get mlkitModelsSize => 'Офлайн-модели ML Kit (~30 МБ каждая)';

  @override
  String get modelDownloadedOffline => 'Загружена — работает офлайн';

  @override
  String get modelNotDownloaded => 'Не загружена';

  @override
  String get deleteModel => 'Удалить модель';

  @override
  String get downloadModel => 'Скачать модель';

  @override
  String downloadFailedWithError(String error) {
    return 'Не удалось скачать: $error';
  }

  @override
  String deleteFailedWithError(String error) {
    return 'Не удалось удалить: $error';
  }

  @override
  String get onDeviceLlmTitle => 'Локальная LLM (Gemma / Qwen)';

  @override
  String llmInstalledReady(String name) {
    return '$name — установлена, готова';
  }

  @override
  String get llmDownloadDesc =>
      'Загрузка ~500 МБ – 1,6 ГБ, работает полностью офлайн';

  @override
  String downloadingPercent(String percent) {
    return 'Загрузка… $percent%';
  }

  @override
  String get modelTokenButton => 'Модель / токен';

  @override
  String get modelUrlLabel => 'URL модели (.task / .litertlm)';

  @override
  String get hfTokenLabel => 'Токен HuggingFace (для закрытых моделей)';

  @override
  String get saveUrlToken => 'Сохранить URL / токен';

  @override
  String get modelSettingsSaved => 'Настройки модели сохранены';

  @override
  String get modelInstalled => 'Модель установлена';

  @override
  String get modelDownloadFailed => 'Не удалось скачать модель';

  @override
  String get modelGatedHint =>
      'Эта модель закрыта лицензией на Hugging Face (ошибка 401). Вставьте токен HF в «Модель / токен» (приняв лицензию на сайте) или оставьте открытую модель по умолчанию (Qwen2.5).';

  @override
  String get deleteOnDeviceModelQuestion => 'Удалить локальную модель?';

  @override
  String get deleteOnDeviceModelDesc =>
      'Это освободит место на диске, но при следующем локальном переводе модель придётся скачать заново.';

  @override
  String get polishTitle => 'Проверка текста';

  @override
  String get detailsButton => 'Подробнее';

  @override
  String get detailsLoading => 'Готовлю разбор…';

  @override
  String get detailsTitle => 'Разбор: правила, примеры, происхождение';

  @override
  String mistakesRecorded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Записано $count ошибок — пойдут в тренировку',
      few: 'Записаны $count ошибки — пойдут в тренировку',
      one: 'Записана $count ошибка — пойдёт в тренировку',
    );
    return '$_temp0';
  }

  @override
  String get toTraining => 'К тренировке';

  @override
  String dueForReview(int count) {
    return 'К повторению сегодня: $count';
  }

  @override
  String get nothingDue =>
      'На сегодня всё повторено — новая тренировка возьмёт свежие ошибки';

  @override
  String get repetitionExplained =>
      'Разобранные ошибки возвращаются на повторение через 1, 3, 7, 21 и 60 дней.';

  @override
  String get noBackendHint =>
      'Для проверки текста нужен ИИ: на компьютере выберите «Claude · подписка» в Настройках → ИИ-помощник; на телефоне — ключ Claude API или бесплатный совместимый сервис.';

  @override
  String writeSomethingIn(String lang) {
    return 'Напишите что-нибудь ($lang)…';
  }

  @override
  String get checking => 'Проверяю…';

  @override
  String get checkButton => 'Проверить';

  @override
  String get looksPerfect => 'Всё отлично!';

  @override
  String fixesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count исправлений',
      few: '$count исправления',
      one: '$count исправление',
    );
    return '$_temp0';
  }

  @override
  String get catGrammar => 'грамматика';

  @override
  String get catWord => 'лексика';

  @override
  String get catArticle => 'артикль';

  @override
  String get catSpelling => 'орфография';

  @override
  String get catPunctuation => 'пунктуация';

  @override
  String get catStyle => 'стиль';

  @override
  String get generating => 'Составляю…';

  @override
  String get newTrainingFromMistakes => 'Новая тренировка из моих ошибок';

  @override
  String get noTrainingsYet =>
      'Пока нет тренировок.\n\nПроверяйте свои тексты во вкладке «Проверка» — ошибки запоминаются, и из них собирается персональный курс: разбор правил, упражнения и тексты именно под ваши слабые места.';

  @override
  String get saveToNotebook => 'В тетрадь';

  @override
  String get savedToNotebook => 'В тетради';

  @override
  String savedToNotebookSnack(String text) {
    return 'Добавлено в тетрадь: $text';
  }

  @override
  String ownTextCheckTitle(String lang) {
    return 'Ваш $lang';
  }

  @override
  String get ownTextChecking => 'Проверяю, как вы написали…';

  @override
  String get ownTextPerfect => 'Написано верно';

  @override
  String ownTextFixes(int count) {
    return 'Правок: $count';
  }

  @override
  String get notAnError => 'Это не ошибка';

  @override
  String get markedNotError => 'Убрано из ваших ошибок';

  @override
  String get upgradeLabel => 'можно естественнее';

  @override
  String get notRecordedLocal =>
      'Не записано в ошибки: маленькая локальная модель часто ошибается.';

  @override
  String get sectionLearning => 'Что я развиваю';

  @override
  String get learningLangLabel => 'Развиваемый язык';

  @override
  String autoCheckLabel(String lang) {
    return 'Проверять мой $lang автоматически';
  }

  @override
  String get autoCheckDesc =>
      'Всё, что вы пишете на этом языке в «Переводе», проверяется в фоне; настоящие ошибки попадают в тетрадь.';

  @override
  String get providerClaudeCode => 'Claude · подписка (Claude Code)';

  @override
  String get providerClaudeApi => 'Claude · API-ключ';

  @override
  String get claudeModelLabel => 'Модель Claude';

  @override
  String get claudeCodeTitle => 'Claude Code на этом компьютере';

  @override
  String claudeCodeReady(String version, String plan) {
    return 'Установлен $version · вход выполнен ($plan)';
  }

  @override
  String get claudeCodeChecking => 'Проверяю Claude Code…';

  @override
  String get refresh => 'Обновить';

  @override
  String get checkConnection => 'Проверить подключение';

  @override
  String get checkingConnection => 'Проверяю…';

  @override
  String connectionOk(String backend, String seconds) {
    return 'Работает: $backend · $seconds с';
  }

  @override
  String aiUsageMonth(int count, int ok, String cost) {
    return 'В этом месяце: $count запросов к ИИ (успешных $ok), оплата по API ≈ \$$cost';
  }

  @override
  String get sectionDiagnostics => 'Данные и диагностика';

  @override
  String get dataFolderLabel => 'Папка с данными';

  @override
  String get settingsFileLabel => 'Файл настроек';

  @override
  String get openFolder => 'Открыть папку';

  @override
  String settingsSaveFailed(String error) {
    return 'Настройки НЕ сохранились: $error';
  }

  @override
  String importedLegacy(int files, int rows) {
    return 'Перенесена история из старых версий: файлов $files, записей $rows';
  }

  @override
  String get notebookTitle => 'Тетрадь';

  @override
  String notebookCounts(int expressions, int mistakes) {
    return 'Слов и выражений: $expressions · ошибок на отработке: $mistakes';
  }

  @override
  String get notebookEmpty =>
      'Пока пусто. Нажимайте «В тетрадь» у слов и поговорок и пишите на развиваемом языке — ошибки добавятся сами.';

  @override
  String get topConstructions => 'Мои проблемные конструкции';

  @override
  String get removeFromNotebook => 'Убрать из тетради';

  @override
  String get aiNeededTitle => 'ИИ не настроен';

  @override
  String get trainingDone => 'Я выполнил(а) эту тренировку';

  @override
  String get trainingDoneMarked =>
      'Выполнено — эти ошибки вернутся по расписанию (1 → 3 → 7 → 21 → 60 дней).';

  @override
  String get removeWordLabel => '(убрать)';

  @override
  String get tabFeed => 'Лента';

  @override
  String get feedTitle => 'Лента';

  @override
  String feedToday(int count, int due) {
    return 'Сегодня: новостей $count · на повторении $due';
  }

  @override
  String get feedBuildMore => 'Ещё новости';

  @override
  String get feedBuilding => 'Пишу сегодняшний выпуск…';

  @override
  String get feedEmpty =>
      'Лента пока пуста. Она пишется из сегодняшних настоящих новостей и использует ВАШИ ошибки и выражения, которые вы берёте в оборот.';

  @override
  String get feedBuildToday => 'Собрать сегодняшний выпуск';

  @override
  String feedFailedItems(int count) {
    return 'Отброшено новостей: $count — модель не прошла проверку фактов или целей.';
  }

  @override
  String feedOpenOriginal(String outlet) {
    return 'Источник: $outlet — открыть оригинал';
  }

  @override
  String get tasksTitle => 'ЗАДАНИЯ';

  @override
  String yourMistakeShort(String wrong, String right) {
    return 'вы писали «$wrong» → «$right»';
  }

  @override
  String yourMistake(String wrong, String right) {
    return 'Вы писали: «$wrong» → правильно: «$right»';
  }

  @override
  String get gotIt => 'Понятно';

  @override
  String get taskCorrect => 'Верно!';

  @override
  String taskAccents(String answer) {
    return 'Верно — но проверьте ударения: $answer';
  }

  @override
  String taskWrong(String answer) {
    return 'Правильно: $answer';
  }

  @override
  String get taskPlaceholder => 'Напишите по-испански…';

  @override
  String get taskCheck => 'Проверить';

  @override
  String get taskTargetMissing =>
      'Целевое выражение не использовано — попробуйте включить его в следующий раз.';

  @override
  String taskModelAnswer(String answer) {
    return 'Пример ответа: $answer';
  }

  @override
  String get journalTitle => 'Журнал';

  @override
  String get taskPending =>
      'Сохранено. Проверю, когда будет доступен ИИ — например, на компьютере после следующего обмена.';

  @override
  String get taskChecked => 'Проверено.';

  @override
  String get sectionExchange => 'Обмен между устройствами';

  @override
  String get exchangeDesc =>
      'Всё накопленное — история, тетрадь, ошибки, тренировки и выпуски ленты с вашими ответами — хранится в одном файле обмена на каждое устройство и объединяется на другом. Выпуски, написанные на компьютере через подписку Claude, можно читать и решать на телефоне; ответы возвращаются обратно.';

  @override
  String get exchangeFolderLabel => 'Папка обмена (по файлу на устройство)';

  @override
  String get exchangeUseOneDrive => 'Хранить в OneDrive';

  @override
  String get exchangeSyncNow => 'Синхронизировать сейчас';

  @override
  String get exchangeSyncing => 'Синхронизирую…';

  @override
  String get exchangeShare => 'Отправить файл обмена';

  @override
  String get exchangeLoad => 'Загрузить файл обмена';

  @override
  String exchangeReport(
      int items, int mistakes, int feed, int tasks, int history) {
    return 'Объединено: тетрадь $items, ошибки $mistakes, новости $feed, ответы $tasks, история $history.';
  }

  @override
  String get exchangeNothingNew =>
      'Нового для объединения нет. Ваш файл обновлён.';

  @override
  String exchangeGraded(int count) {
    return 'Проверено ответов с другого устройства: $count';
  }

  @override
  String get exchangePhoneHint =>
      'На компьютер: сохраните файл в его папку обмена (например, OneDrive\\LinguaTrace). Сюда: загрузите файл компьютера linguatrace-windows-….json.';

  @override
  String get feedPhoneHint =>
      'Выпуски пишутся на компьютере (подписка Claude). Загрузите файл обмена: Настройки → Обмен.';

  @override
  String get feedGlossAfterTask =>
      'Пояснения к выделенным словам появятся после ответа на задание ниже.';

  @override
  String feedCannotOpen(String url) {
    return 'Не удалось открыть $url';
  }

  @override
  String exchangeErrors(String errors) {
    return 'Объединено не всё: $errors';
  }

  @override
  String get exchangeFullHistory => 'Включать всю историю переводов';

  @override
  String get exchangeFullHistoryHint =>
      'По умолчанию в файл попадают тетрадь, ошибки, лента и короткие запросы; длинные тексты (письма) остаются на этом устройстве. Файл — обычный текст (JSON): храните его в своих папках.';

  @override
  String exchangeTooLarge(int mb) {
    return 'Файл слишком большой для файла обмена ($mb МБ).';
  }

  @override
  String claudeCodeTokenInUse(String version) {
    return 'Установлен $version · используется токен подписки';
  }

  @override
  String get claudeCodeLogin => 'Войти в Claude Code';

  @override
  String get claudeCodeSetupToken => 'Создать токен подписки (на год)';

  @override
  String get claudeCodeTokenLabel => 'Токен подписки (необязательно)';

  @override
  String get claudeCodeTokenHelp =>
      'Из `claude setup-token`: действует год, повторный вход не нужен. Это не API-ключ — расходует лимиты подписки, без доплат. Хранится в settings.json на этом компьютере.';

  @override
  String get claudeCodeConsoleLogin1 =>
      'Вход в Claude Code аккаунтом с подпиской.';

  @override
  String get claudeCodeConsoleLogin2 =>
      'Откроется браузер: войдите и разрешите доступ. Потом закройте это окно и вернитесь в LinguaTrace.';

  @override
  String get claudeCodeConsoleToken1 =>
      'Токен подписки на год для LinguaTrace (не API-ключ, без доплат).';

  @override
  String get claudeCodeConsoleToken2 =>
      'Откроется браузер: войдите. Затем скопируйте строку sk-ant-oat01-... и вставьте в LinguaTrace: Настройки - ИИ-помощник - Токен подписки.';

  @override
  String get providerPcRelay => 'Claude через компьютер (подписка)';

  @override
  String get relayClientDesc =>
      'Телефон отправляет запросы в LinguaTrace на вашем компьютере, а тот — в Claude по вашей подписке. Без ключей и доплат. Адрес и код показаны на ПК: Настройки → ИИ-помощник → «Claude для телефона».';

  @override
  String get relayAddressLabel => 'Адрес компьютера';

  @override
  String get relayCodeLabel => 'Код подключения';

  @override
  String get relayServerTitle => 'Claude для телефона';

  @override
  String get relayServerDesc =>
      'Телефон сможет пользоваться Claude этого компьютера (ваша подписка, без доплат), пока LinguaTrace здесь запущен.';

  @override
  String get relayServerRunning => 'Работает. На телефоне введите адрес и код:';

  @override
  String get relayNoNetwork =>
      'Нет сети — подключите компьютер к Wi‑Fi или локальной сети.';

  @override
  String get relayNewCode => 'Новый код';

  @override
  String get relayServerHint =>
      'Телефон и компьютер должны быть в одной сети Wi‑Fi. Вне дома: установите Tailscale на оба устройства и введите адрес компьютера вида 100.x.x.x. При первом включении Windows спросит разрешение для сети — разрешите для частных сетей.';

  @override
  String get fastModelLabel => 'Модель для быстрых ответов';

  @override
  String get fastModelHint =>
      'Проверка текста, подсказки, подбор слова, происхождение. Основная модель выше пишет ленту и тренировки.';

  @override
  String get claudeWarmLabel => 'Держать Claude наготове';

  @override
  String get claudeWarmHint =>
      'Ответ за 1–3 с вместо ~10 с: Claude Code остаётся запущенным (≈150–250 МБ памяти).';

  @override
  String get startupTimesLabel => 'Время запуска';

  @override
  String get copy => 'Копировать';

  @override
  String get askClaudeApp => 'Спросить в приложении Claude';

  @override
  String get chipChoice => 'Подбор слова';

  @override
  String get chipOrigin => 'Происхождение';

  @override
  String get chosenTranslation => 'Claude · подбор';

  @override
  String etymologyAskPrompt(String term, String lang) {
    return 'Расскажи о происхождении «$term» ($lang): путь из латыни и других языков, почему так называется, родственные слова в испанском, русском и английском, история выражения. По-русски, кратко.';
  }

  @override
  String get etymologyRebuild => 'Написать заново';

  @override
  String get etymologyWriting => 'Claude пишет страницу…';

  @override
  String get etymologyPhoneHint =>
      'Страницы происхождения пишет Claude. Включите «Claude через компьютер» (Настройки → ИИ-помощник) или загрузите файл обмена — в нём страницы, созданные на компьютере.';

  @override
  String etymologyCertainty(String certainty) {
    String _temp0 = intl.Intl.selectLogic(
      certainty,
      {
        'documented': 'достоверно',
        'probable': 'вероятно',
        'disputed': 'спорно',
        'folk': 'народная версия',
        'other': '?',
      },
    );
    return '$_temp0';
  }

  @override
  String get etymologyChain => 'Путь слова';

  @override
  String get etymologyWhy => 'Почему так называется';

  @override
  String get etymologyIdiomStory => 'Откуда выражение';

  @override
  String get etymologyHistory => 'История';

  @override
  String get etymologyRelatives => 'Родственные слова';

  @override
  String get etymologyFalseFriends => 'Ложные друзья';

  @override
  String get etymologyMnemonic => 'Запомнить';

  @override
  String get etymologySources => 'Источник';

  @override
  String get etymologyNoSources => 'Словарь не найден — по общим сведениям';

  @override
  String wordChoiceAskPrompt(String source, String translation, String focus) {
    return 'Перевожу на испанский: «$source». Машинный перевод: «$translation». Не нравится слово: $focus. Предложи варианты с оттенками значения и перепиши предложение с каждым.';
  }

  @override
  String get wordChoiceTitle => 'Подбор слова';

  @override
  String get wordChoiceNow => 'Сейчас переведено так:';

  @override
  String get wordChoicePick =>
      'Какое слово подобрать? Нажмите на него — или не выбирайте, тогда подберу для всего предложения.';

  @override
  String get wordChoiceHintLabel => 'Что вы хотите сказать (необязательно)';

  @override
  String get wordChoiceHintExample =>
      'например: внести вклад, а не принести вещь';

  @override
  String get wordChoiceRunSentence => 'Подобрать варианты';

  @override
  String wordChoiceRunWord(String word) {
    return 'Подобрать для «$word»';
  }

  @override
  String get wordChoiceNoAiDesktop =>
      'Без ИИ показываю словарные варианты. Подключите Claude в Настройках — будут объяснения и готовые фразы.';

  @override
  String get wordChoiceNoAiPhone =>
      'Без ИИ показываю словарные варианты. Подключите «Claude через компьютер» в Настройках — будут объяснения и готовые фразы.';

  @override
  String get wordChoiceUse => 'Взять';

  @override
  String get wordChoiceDictionaryNote =>
      'Словарные варианты: рядом — обратный перевод, по нему видно значение.';

  @override
  String wordChoiceFit(String fit) {
    String _temp0 = intl.Intl.selectLogic(
      fit,
      {
        'best': 'лучше всего',
        'good': 'подходит',
        'possible': 'возможно',
        'wrong': 'не то',
        'other': '',
      },
    );
    return '$_temp0';
  }

  @override
  String get wordChoiceOrigin => 'Откуда слово?';

  @override
  String get tabIdeas => 'Идеи';

  @override
  String get ideasTitle => 'Идеи';

  @override
  String get ideasEmpty =>
      'Здесь собираются мысли для статей и изобретений. Создайте проект и опишите контекст — потом просто диктуйте на ходу. В фоне я расставлю пунктуацию, найду в интернете, что уже известно, и соберу черновик.';

  @override
  String get ideasNewProject => 'Новый проект';

  @override
  String get ideasDictate => 'Диктовать';

  @override
  String get ideasProjectTitleLabel => 'Название';

  @override
  String get ideasContextLabel => 'Контекст: о чём это, для кого, что важно';

  @override
  String get ideasKindArticle => 'Статья';

  @override
  String get ideasKindInvention => 'Изобретение';

  @override
  String get ideasKindOther => 'Другое';

  @override
  String get ideasCreate => 'Создать';

  @override
  String ideasCounts(int notes, int sources) {
    return 'мыслей: $notes · источников: $sources';
  }

  @override
  String get ideasContext => 'Контекст';

  @override
  String get ideasEditContext => 'Изменить проект';

  @override
  String get ideasSources => 'Источники';

  @override
  String get ideasAddSource => 'Добавить';

  @override
  String get ideasAddText => 'Вставить текст';

  @override
  String get ideasAddUrl => 'Ссылка на статью';

  @override
  String get ideasAddFile => 'Файл (txt, md, html, pdf)';

  @override
  String get ideasUrlLabel => 'Адрес страницы';

  @override
  String get ideasTextLabel => 'Текст';

  @override
  String get ideasAdding => 'Загружаю…';

  @override
  String get ideasSourceText => 'Текст';

  @override
  String get ideasFound => 'Найдено при поиске';

  @override
  String get ideasNotes => 'Мысли';

  @override
  String get ideasNoNotes => 'Пока нет мыслей — нажмите «Диктовать».';

  @override
  String get ideasStatusQueued => 'в очереди';

  @override
  String get ideasStatusWorking => 'ищу и разбираю…';

  @override
  String get ideasStatusOffline => 'ждёт ИИ';

  @override
  String get ideasStatusFailed => 'не получилось';

  @override
  String get ideasRetry => 'Разобрать заново';

  @override
  String get ideasInsight => 'Разбор';

  @override
  String get ideasWithWeb => 'с поиском';

  @override
  String get ideasDraft => 'Собрать черновик';

  @override
  String get ideasDrafting => 'Собираю черновик…';

  @override
  String get ideasDraftLabel => 'Черновик';

  @override
  String get ideasShare => 'Поделиться (Markdown)';

  @override
  String get ideasDelete => 'Удалить проект';

  @override
  String ideasDeleteConfirm(String title) {
    return 'Удалить проект «$title» со всеми мыслями и источниками?';
  }

  @override
  String get ideasRaw => 'Исходная диктовка';

  @override
  String get ideasNoAi =>
      'Без ИИ мысли просто сохраняются. Пунктуацию, поиск и разбор сделает Claude: подключите его (Настройки → ИИ-помощник) или синхронизируйте с компьютером.';

  @override
  String get ideasWebLabel => 'Искать в интернете для идей';

  @override
  String get ideasWebHint =>
      'Claude ищет аналоги, факты и источники к каждой мысли. Через API-ключ: до 5 поисков на мысль, \$10 за 1000 поисков.';

  @override
  String get dictationListening => 'Слушаю';

  @override
  String get dictationPaused => 'Пауза';

  @override
  String get dictationNewNote => 'Новая мысль';

  @override
  String get dictationStop => 'Стоп';

  @override
  String get dictationResume => 'Продолжить';

  @override
  String get dictationHint =>
      'Говорите свободно, паузы не страшны. «Новая мысль» — следующая, «что думаешь?» — Claude ответит и задаст вопрос, «стоп запись» — конец. Экран можно погасить кнопкой.';

  @override
  String dictationSaved(int n) {
    return 'сохранено мыслей: $n';
  }

  @override
  String get dictationNoVoice =>
      'На этом устройстве нет распознавания речи — запишите мысль текстом.';

  @override
  String dictationError(String error) {
    return 'Распознавание остановилось ($error). Нажмите «Продолжить».';
  }

  @override
  String get dictationTypeHint => 'Мысль';

  @override
  String get dictationSave => 'Сохранить';

  @override
  String get anthropicKeyHelp =>
      'Ключ создаётся на console.anthropic.com → API keys. Запросы по ключу оплачиваются отдельно от подписки claude.ai. С ключом Claude работает и на телефоне — без компьютера.';

  @override
  String dictationReconnecting(String reason) {
    return 'Переподключаю распознавание: $reason';
  }

  @override
  String get dictationTroubleNet => 'нет связи';

  @override
  String get dictationTroubleMic => 'микрофон занят';

  @override
  String get dictationTroubleBackground =>
      'в фоне Android не даёт микрофон — включите экран';

  @override
  String get dictationTroubleBusy => 'распознаватель занят';

  @override
  String get dictationErrPermission =>
      'нет доступа к микрофону — разрешите его LinguaTrace в настройках телефона';

  @override
  String get dictationErrLanguage =>
      'этот язык не распознаётся на телефоне — добавьте его в настройках голосового ввода Google';

  @override
  String get dictationErrInit =>
      'распознавание речи недоступно — проверьте доступ к микрофону и голосовой ввод Google';

  @override
  String get dictationErrNoRecognizer =>
      'на телефоне нет службы распознавания речи (нужно приложение Google)';

  @override
  String get dictationMuteBeeps =>
      'Без сигналов: выключать звук медиа на время записи';

  @override
  String get dictationLog => 'Журнал распознавания';

  @override
  String get dictationLogHint =>
      'Если диктовка работает не так — скопируйте журнал и пришлите его.';

  @override
  String get dictationLogEmpty => 'Журнал пуст.';

  @override
  String get dictationCopy => 'Копировать';

  @override
  String get dictationCopied => 'Скопировано';

  @override
  String get syncServerTitle => 'Сервер синхронизации';

  @override
  String get syncServerHint =>
      'Свой сервер, где собираются данные всех устройств (программа в папке server проекта). Телефон и компьютеры обмениваются через него сами: при запуске, раз в 10 минут и после диктовки.';

  @override
  String get syncServerUrlLabel => 'Адрес сервера';

  @override
  String get syncServerKeyLabel => 'Ключ доступа';

  @override
  String get syncServerNow => 'Синхронизировать с сервером';

  @override
  String get syncServerSent => 'Данные этого устройства отправлены на сервер.';

  @override
  String get dictationDiscuss => 'Обсудить';

  @override
  String get dictationThinking => 'Claude думает…';

  @override
  String get dictationSpeaking => 'Claude говорит…';

  @override
  String get dictationStopSpeaking => 'Прервать';

  @override
  String get dictationBluetooth => 'Микрофон Bluetooth-гарнитуры';

  @override
  String dictationDiscussFailed(String error) {
    return 'Claude не ответил: $error';
  }

  @override
  String get ideasClaude => 'Claude';
}
